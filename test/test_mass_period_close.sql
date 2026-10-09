USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @studentAbsent UNIQUEIDENTIFIER, @studentPresent UNIQUEIDENTIFIER;
SELECT @studentAbsent = id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 1;
SELECT @studentPresent = id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 2;
IF @studentPresent IS NULL SET @studentPresent = @studentAbsent;
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @finished UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F');
DECLARE @cancelled UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI');
DECLARE @absence UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID(), @enrollment UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 600000 + ABS(CHECKSUM(NEWID()) % 100000);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @baseDetailCode INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR
   @adminUser IS NULL OR
   @studentAbsent IS NULL OR @studentPresent IS NULL OR @active IS NULL OR
   @finished IS NULL OR @cancelled IS NULL OR @absence IS NULL
    THROW 52010, 'TEST FAILED: MASS_CLOSE fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Cierre', @periodCode,
        DATEADD(DAY, -20, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Masivo', 30, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (@enrollment, @active, @studentAbsent, @group),
        (NEWID(), @active, @studentPresent, @group);

    DECLARE @firstDay DATE = DATEADD(DAY, -10, CAST(GETDATE() AS DATE));
    DECLARE @sessions TABLE (seq INT PRIMARY KEY, sessionId UNIQUEIDENTIFIER, attendanceId UNIQUEIDENTIFIER);
    INSERT INTO @sessions VALUES
        (1, NEWID(), NEWID()), (2, NEWID(), NEWID()), (3, NEWID(), NEWID());
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    SELECT sessionId, CONCAT(N'QA Cierre ', seq), seq,
        LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        DATEADD(HOUR, 9, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2)))
    FROM @sessions;
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion)
    SELECT attendanceId, @enrollment, sessionId FROM @sessions;
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    SELECT NEWID(), @baseDetailCode + seq, attendanceId, 0, @absence,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        DATEADD(HOUR, 9, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2)))
    FROM @sessions;

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'CierreMasivoPeriodo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:MASS_CLOSE_SUCCESS|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:MASS_CLOSE_SUCCESS|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:MASS_CLOSE_SUCCESS';
    EXEC dbo.usp_ejecutar_cierre_masivo_periodo
        @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL', @idCorrelacion = @corr,
        @idUsuarioEjecutor = @adminUser;
    PRINT 'TEST_RESULT_END:MASS_CLOSE_SUCCESS';
    IF @@TRANCOUNT <> 1
        THROW 52011, 'TEST FAILED: MASS_CLOSE_SUCCESS destroyed the caller transaction.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo
        WHERE id = @enrollment AND codigoEstadoEstudiante = 'CI')
        THROW 52012, 'TEST FAILED: MASS_CLOSE_SUCCESS did not cancel three absences.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo
        WHERE estudiante = @studentPresent AND grupo = @group AND estado = @finished)
        THROW 52013, 'TEST FAILED: MASS_CLOSE_SUCCESS did not finish active student.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Grupo
        WHERE id = @group AND cantidadEstudiantesFinalizaron = 1
        AND cantidadEstudiantesCancelaronAutomaticamente = 1)
        THROW 52014, 'TEST FAILED: MASS_CLOSE_SUCCESS counters incorrect.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.AuditoriaEvento
        WHERE correlationId = @corr AND resourceId = CONVERT(NVARCHAR(50), @period)
        AND action = N'CIERRE_MASIVO_PERIODO' AND result = N'SUCCESS' AND actorType = N'USER'
        AND ISJSON(metadata) = 1)
        THROW 52015, 'TEST FAILED: MASS_CLOSE_SUCCESS missing audit event.', 1;
    PRINT 'TEST_STATE_PASS:MASS_CLOSE_SUCCESS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group) OR
   EXISTS (SELECT 1 FROM dbo.PeriodoAcademico WHERE id = @period) OR
   EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corr)
    THROW 52016, 'TEST FAILED: MASS_CLOSE leaked fixtures.', 1;
IF @@TRANCOUNT <> 0 THROW 52017, 'TEST FAILED: MASS_CLOSE left transaction open.', 1;
GO

-- ---------------------------------------------------------------------------------------------
-- TD-058: periodo solicitado inexistente -> PER_001, cero escrituras. Nunca sustituir por otro periodo.
-- ---------------------------------------------------------------------------------------------
SET NOCOUNT ON;
DECLARE @adminUserUnknown UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @institutionUnknown UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @periodA UNIQUEIDENTIFIER = NEWID(), @periodB UNIQUEIDENTIFIER = NEWID();
DECLARE @codeA INT = 710000 + ABS(CHECKSUM(NEWID()) % 10000), @codeB INT = 720000 + ABS(CHECKSUM(NEWID()) % 10000);
DECLARE @codeMissing NVARCHAR(50) = N'PERIODO-QA-INEXISTENTE-' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @corrUnknown UNIQUEIDENTIFIER = NEWID(), @msgUnknownUser NVARCHAR(4000), @msgUnknownTech NVARCHAR(4000);
IF @adminUserUnknown IS NULL OR @institutionUnknown IS NULL THROW 52900, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD fixture missing.', 1;

CREATE TABLE #massUnknown (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);
CREATE TABLE #massSnap (
    fase VARCHAR(10) NOT NULL,
    periodos INT NOT NULL, periodosChk INT NOT NULL,
    grupos INT NOT NULL, gruposChk INT NOT NULL,
    matriculas INT NOT NULL, matriculasChk INT NOT NULL,
    auditorias INT NOT NULL,
    detalles INT NOT NULL, detallesChk INT NOT NULL
);

BEGIN TRANSACTION;
BEGIN TRY
    -- Preparar dos periodos existentes (A y B) dentro de la transaccion de prueba.
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@periodA, @institutionUnknown, N'Periodo QA A', @codeA, '2001-01-01', '2001-06-30', 2001),
           (@periodB, @institutionUnknown, N'Periodo QA B', @codeB, '2002-01-01', '2002-06-30', 2002);

    INSERT INTO #massSnap
    SELECT 'before',
        (SELECT COUNT(*) FROM dbo.PeriodoAcademico), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, codigo, nombre)), 0) FROM dbo.PeriodoAcademico),
        (SELECT COUNT(*) FROM dbo.Grupo), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronAutomaticamente, cantidadEstudiantesCancelaronVoluntadPropia)), 0) FROM dbo.Grupo),
        (SELECT COUNT(*) FROM dbo.EstudianteGrupo), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, estado, grupo, estudiante)), 0) FROM dbo.EstudianteGrupo),
        (SELECT COUNT(*) FROM dbo.AuditoriaEvento),
        (SELECT COUNT(*) FROM dbo.DetalleAsistencia), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, asistio, razonCausa)), 0) FROM dbo.DetalleAsistencia);

    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PER_001', @p_param1 = @codeMissing,
        @mensajeUsuarioResultado = @msgUnknownUser OUTPUT, @mensajeTecnicoResultado = @msgUnknownTech OUTPUT;

    INSERT INTO #massUnknown EXEC dbo.usp_ejecutar_cierre_masivo_periodo
        @codigoPeriodo = @codeMissing, @idActor = N'QA_LOCAL', @idCorrelacion = @corrUnknown,
        @idUsuarioEjecutor = @adminUserUnknown;

    IF NOT EXISTS (SELECT 1 FROM #massUnknown WHERE estadoResultado = 0 AND idCorrelacion = @corrUnknown
        AND mensajeUsuarioResultado = @msgUnknownUser AND mensajeTecnicoResultado = CONCAT(@msgUnknownTech, ' Correlacion: ', @corrUnknown))
        THROW 52901, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD expected canonical PER_001 with estado 0.', 1;

    INSERT INTO #massSnap
    SELECT 'after',
        (SELECT COUNT(*) FROM dbo.PeriodoAcademico), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, codigo, nombre)), 0) FROM dbo.PeriodoAcademico),
        (SELECT COUNT(*) FROM dbo.Grupo), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronAutomaticamente, cantidadEstudiantesCancelaronVoluntadPropia)), 0) FROM dbo.Grupo),
        (SELECT COUNT(*) FROM dbo.EstudianteGrupo), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, estado, grupo, estudiante)), 0) FROM dbo.EstudianteGrupo),
        (SELECT COUNT(*) FROM dbo.AuditoriaEvento),
        (SELECT COUNT(*) FROM dbo.DetalleAsistencia), (SELECT ISNULL(CHECKSUM_AGG(CHECKSUM(id, asistio, razonCausa)), 0) FROM dbo.DetalleAsistencia);

    IF EXISTS (SELECT 1 FROM #massSnap b INNER JOIN #massSnap a ON a.fase = 'after' WHERE b.fase = 'before'
        AND (a.periodos <> b.periodos OR a.periodosChk <> b.periodosChk OR a.grupos <> b.grupos OR a.gruposChk <> b.gruposChk
          OR a.matriculas <> b.matriculas OR a.matriculasChk <> b.matriculasChk OR a.auditorias <> b.auditorias
          OR a.detalles <> b.detalles OR a.detallesChk <> b.detallesChk))
        THROW 52902, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD produced writes on existing data.', 1;
    IF EXISTS (SELECT 1 FROM dbo.AuditoriaEvento WHERE correlationId = @corrUnknown)
        THROW 52903, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD wrote an audit event.', 1;
    IF @@TRANCOUNT <> 1 THROW 52904, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD changed the external transaction.', 1;
    PRINT 'TEST_PASS:MASS_CLOSE_UNKNOWN_PERIOD_ZERO_WRITES';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52905, 'TEST FAILED: MASS_CLOSE_UNKNOWN_PERIOD left transaction open.', 1;
GO
