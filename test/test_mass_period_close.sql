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
    -- CULM-001 B.2 ([SUPUESTO-B-20]): la columna obligatoria DetalleAsistencia.toma exige la toma 1 de la sesion (helper culm001_b2_toma_fixture.sql).
    DECLARE @culmb2Sesiones NVARCHAR(MAX) = (SELECT idSesion = sessionId FROM @sessions FOR JSON PATH);
    EXEC #culm001_b2_crear_tomas @sesionesJSON = @culmb2Sesiones;
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma)
    SELECT NEWID(), @baseDetailCode + seq, attendanceId, 0, @absence,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        DATEADD(HOUR, 9, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))),
        (SELECT t.id FROM dbo.TomaAsistencia t WHERE t.sesion = sessionId AND t.numero = 1)
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

-- CULM-001 B.2 (CONTRACT §1.4, §2.9 B-7, §2.16.2 B2-HOR-10): cambio minimo del cierre masivo con varias tomas.
-- Un estudiante con 3 tomas ausentes en UNA sola sesion no pasa a CI (cuenta como una sesion: queda F al cerrar);
-- otro con ausencias en 3 sesiones distintas pasa a CI (regla actual intacta).
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @stTresSesiones UNIQUEIDENTIFIER, @stUnaSesion UNIQUEIDENTIFIER;
SELECT @stTresSesiones = id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 1;
SELECT @stUnaSesion = id FROM (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM dbo.Estudiante) e WHERE rn = 2;
DECLARE @active UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
DECLARE @absence UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @modoManual UNIQUEIDENTIFIER = (SELECT id FROM dbo.ModoTomaAsistencia WHERE usaCodigoQr = 0);
DECLARE @cerrada UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoTomaAsistencia WHERE estaAbierta = 0);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID();
DECLARE @egTres UNIQUEIDENTIFIER = NEWID(), @egUna UNIQUEIDENTIFIER = NEWID();
DECLARE @periodCode INT = 700000 + ABS(CHECKSUM(NEWID()) % 99999);
DECLARE @periodCodeText NVARCHAR(50) = CONVERT(NVARCHAR(50), @periodCode);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @adminUser IS NULL OR @stTresSesiones IS NULL OR @stUnaSesion IS NULL
   OR @stTresSesiones = @stUnaSesion OR @active IS NULL OR @absence IS NULL OR @modoManual IS NULL OR @cerrada IS NULL
    THROW 52020, 'TEST FAILED: CULM001_B2_HOR_10 fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Cierre B2', @periodCode, DATEADD(DAY, -20, CAST(GETDATE() AS DATE)), DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), YEAR(GETDATE()));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000), N'Grupo QA Masivo B2', 30, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo) VALUES (@egTres, @active, @stTresSesiones, @group), (@egUna, @active, @stUnaSesion, @group);
    DECLARE @firstDay DATE = DATEADD(DAY, -10, CAST(GETDATE() AS DATE));
    DECLARE @s TABLE (seq INT PRIMARY KEY, id UNIQUEIDENTIFIER);
    INSERT INTO @s VALUES (1, NEWID()), (2, NEWID()), (3, NEWID());
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    SELECT id, CONCAT(N'QA Cierre B2 ', seq), seq, LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8), 1, @group,
        DATEADD(HOUR, 8, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2))), DATEADD(HOUR, 11, DATEADD(DAY, seq, CAST(@firstDay AS DATETIME2)))
    FROM @s;
    -- 3 tomas cerradas en cada sesion
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc, fechaCierreUtc, idCorrelacionApertura)
    SELECT NEWID(), s.id, v.n, @modoManual, @cerrada, 0, @teacher, CAST(se.fechaHoraInicio AS DATETIME2(0)), CAST(se.fechaHoraFin AS DATETIME2(0)), NEWID()
    FROM @s s INNER JOIN dbo.Sesion se ON se.id = s.id CROSS JOIN (VALUES (1), (2), (3)) v(n);
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) SELECT NEWID(), @egTres, id FROM @s;
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) SELECT NEWID(), @egUna, id FROM @s WHERE seq = 1;
    -- @egTres: una ausencia (toma 1) en cada una de las 3 sesiones; @egUna: 3 ausencias (tomas 1..3) en la sesion 1
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin, toma, registradoPorEstudiante, fechaRegistroUtc)
    SELECT NEWID(), NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, a.id, 0, @absence, se.fechaHoraInicio, se.fechaHoraFin, t.id, 0, SYSUTCDATETIME()
    FROM dbo.Asistencia a INNER JOIN dbo.Sesion se ON se.id = a.sesion INNER JOIN dbo.TomaAsistencia t ON t.sesion = a.sesion
    WHERE (a.estudianteGrupo = @egTres AND t.numero = 1) OR (a.estudianteGrupo = @egUna);
    IF (SELECT COUNT(*) FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia WHERE a.estudianteGrupo = @egUna) <> 3
        THROW 52021, 'TEST FAILED: CULM001_B2_HOR_10 fixture: se esperaban 3 tomas ausentes en una sesion.', 1;
    EXEC dbo.usp_ejecutar_cierre_masivo_periodo @codigoPeriodo = @periodCodeText, @idActor = N'QA_LOCAL_B2', @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @egTres AND codigoEstadoEstudiante = 'CI')
        THROW 52022, 'TEST FAILED: CULM001_B2_HOR_10 ausencias en 3 sesiones distintas deben pasar a CI (regla actual).', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE id = @egUna AND codigoEstadoEstudiante = 'F')
        THROW 52023, 'TEST FAILED: CULM001_B2_HOR_10 tres tomas ausentes de una sola sesion cuentan como una sesion (no CI).', 1;
    PRINT 'TEST_PASS:CULM001_B2_HOR_10_CIERRE_MASIVO_SESIONES_DISTINTAS';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 52024, 'TEST FAILED: CULM001_B2_HOR_10 left transaction open.', 1;
GO
