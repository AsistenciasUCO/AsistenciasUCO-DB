USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_asignatura);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_docente);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente WHERE id = @teacher);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @group UNIQUEIDENTIFIER = NEWID();
DECLARE @missingGroup UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @firstDay DATE = CAST(
    SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(
        (SELECT TOP 1 valor
         FROM dbo.CatalogoParametro
         WHERE grupo = 'TIEMPO'
           AND clave = 'ZONA_HORARIA_SQLSERVER'
           AND estaActivo = 1),
        'SA Pacific Standard Time'
    ) AS DATE
);
IF @institution IS NULL OR @assignment IS NULL OR @teacher IS NULL OR @teacherUser IS NULL
    THROW 51700, 'TEST FAILED: SESSION_GENERATION fixture missing.', 1;

CREATE TABLE #generationResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Generacion',
        400000 + ABS(CHECKSUM(NEWID()) % 100000), @firstDay, DATEADD(DAY, 7, @firstDay), YEAR(@firstDay));
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@group, @assignment, @period, 400000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Generacion', 20, 0, 0, 0, @teacher);
    INSERT dbo.Horario (id, grupo, dia, horaInicio, horaFin)
    SELECT NEWID(), @group, id, '08:00', '09:00' FROM dbo.uv_dia;
    IF (SELECT COUNT(*) FROM dbo.Horario WHERE grupo = @group) <> 7
        THROW 51701, 'TEST FAILED: SESSION_GENERATION requires seven day codes.', 1;

    DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'GeneracionSesionesGrupo',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #generationResult
    EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #generationResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51702, 'TEST FAILED: SESSION_GENERATION wrong canonical SUCCESS.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_sesion WHERE idGrupo = @group) <> 8
        THROW 51703, 'TEST FAILED: SESSION_GENERATION did not create eight visible sessions.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @group GROUP BY fechaHoraInicio, fechaHoraFin HAVING COUNT(*) > 1)
        THROW 51704, 'TEST FAILED: SESSION_GENERATION created duplicate times.', 1;
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Sesion
        WHERE grupo = @group
          AND CAST(fechaHoraInicio AS TIME) = '13:00'
          AND fechaHoraInicio = DATEADD(HOUR, 13, CAST(@firstDay AS DATETIME2))
    )
        THROW 51712, 'TEST FAILED: UTC_SESSION_GENERATION did not persist 08:00 America/Bogota as 13:00 UTC.', 1;
    PRINT 'TEST_PASS:SESSION_GENERATION_SUCCESS';
    PRINT 'TEST_PASS:UTC_SESSION_GENERATION';

    TRUNCATE TABLE #generationResult;
    SET @corr = NEWID();
    INSERT INTO #generationResult
    EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @group, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #generationResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1
        THROW 51705, 'TEST FAILED: SESSION_GENERATION repeat returned wrong result.', 1;
    IF (SELECT COUNT(*) FROM dbo.Sesion WHERE grupo = @group) <> 8
        THROW 51706, 'TEST FAILED: SESSION_GENERATION repeat created duplicates.', 1;
    PRINT 'TEST_PASS:SESSION_GENERATION_IDEMPOTENT';

    TRUNCATE TABLE #generationResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_GRUPO_NO_EXISTE',
        @p_param1 = @missingGroup, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #generationResult
    EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @missingGroup, @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #generationResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51707, 'TEST FAILED: SESSION_GENERATION invalid group returned wrong result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @missingGroup)
        THROW 51708, 'TEST FAILED: SESSION_GENERATION invalid group wrote sessions.', 1;
    PRINT 'TEST_PASS:SESSION_GENERATION_INVALID';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @group)
    THROW 51709, 'TEST FAILED: SESSION_GENERATION leaked group.', 1;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE grupo = @group)
    THROW 51710, 'TEST FAILED: SESSION_GENERATION leaked sessions.', 1;
IF @@TRANCOUNT <> 0 THROW 51711, 'TEST FAILED: SESSION_GENERATION left transaction open.', 1;
PRINT 'TEST END: test_usp_generar_sesiones_grupo';
GO
