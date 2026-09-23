USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @group UNIQUEIDENTIFIER, @student UNIQUEIDENTIFIER, @enrollment UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
SELECT TOP 1 @group = eg.idGrupo, @student = eg.idEstudiante, @enrollment = eg.id, @teacher = g.idDocente
FROM dbo.uv_estudiante_grupo eg JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
WHERE eg.codigoEstadoEstudiante = 'A' AND g.grupoEstaHablitado = 1
ORDER BY eg.id;
DECLARE @reason UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.RazonCausa WHERE codigo IN ('SJC', 'F'));
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE id = @student);
DECLARE @teacherUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE id = @teacher);
DECLARE @session UNIQUEIDENTIFIER = NEWID(), @attendance UNIQUEIDENTIFIER = NEWID(), @detail UNIQUEIDENTIFIER = NEWID();
DECLARE @sessionCode NVARCHAR(50) = LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
DECLARE @number INT = 1 + (SELECT ISNULL(MAX(numero), 0) FROM dbo.Sesion WHERE grupo = @group);
DECLARE @detailCode INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @request UNIQUEIDENTIFIER;
IF @group IS NULL OR @student IS NULL OR @teacher IS NULL OR @studentUser IS NULL OR @teacherUser IS NULL OR @reason IS NULL
    THROW 51950, 'TEST FAILED: REVIEW fixture missing.', 1;
CREATE TABLE #reviewResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin)
    VALUES (@session, N'QA Revision', @number, @sessionCode, 1, @group,
        DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));
    INSERT dbo.Asistencia (id, estudianteGrupo, sesion) VALUES (@attendance, @enrollment, @session);
    INSERT dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
    VALUES (@detail, @detailCode, @attendance, 0, @reason, DATEADD(HOUR, 1, GETDATE()), DATEADD(HOUR, 2, GETDATE()));

    DECLARE @missingStudent UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'EST_001', @p_param1 = @missingStudent,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #reviewResult
    EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @missingStudent,
        @idSesion = @session, @categoria = N'ASISTENCIA', @justificacion = N'QA',
        @soporteNombre = NULL, @soporteUrl = NULL, @idCorrelacion = @corr,
        @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #reviewResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51951, 'TEST FAILED: REVIEW_FILE_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE asistencia = @attendance)
        THROW 51952, 'TEST FAILED: REVIEW_FILE_INVALID wrote request.', 1;

    TRUNCATE TABLE #reviewResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'SolicitudRevisionAsistencia',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #reviewResult
    EXEC dbo.usp_radicar_solicitud_revision_asistencia @idEstudiante = @student,
        @idSesion = @session, @categoria = N'ASISTENCIA', @justificacion = N'Clase QA',
        @soporteNombre = N'evidencia.pdf', @soporteUrl = N'https://example.invalid/qa',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @studentUser;
    IF (SELECT COUNT(*) FROM #reviewResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51953, 'TEST FAILED: REVIEW_FILE_SUCCESS wrong canonical result.', 1;
    SELECT @request = id FROM dbo.uv_solicitud_revision_asistencia
    WHERE idAsistencia = @attendance AND justificacionSolicitud = N'Clase QA';
    IF @request IS NULL
        THROW 51954, 'TEST FAILED: REVIEW_FILE_SUCCESS not visible in public view.', 1;

    TRUNCATE TABLE #reviewResult;
    SET @corr = NEWID();
    DECLARE @otherTeacher UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_007', @p_param1 = 'DocenteAmbitoRevision',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #reviewResult
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @request,
        @idDocente = @otherTeacher, @accion = N'APROBADA', @respuestaDocente = N'No autorizado',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #reviewResult WHERE idCorrelacion = @corr AND estadoResultado = 0
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51955, 'TEST FAILED: REVIEW_RESOLVE_NON_OWNER wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @request AND justificacionRespuesta = N'No autorizado')
        THROW 51956, 'TEST FAILED: REVIEW_RESOLVE_NON_OWNER changed request.', 1;

    TRUNCATE TABLE #reviewResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'SolicitudRevisionAsistencia',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #reviewResult
    EXEC dbo.usp_resolver_solicitud_revision_asistencia @idSolicitud = @request,
        @idDocente = @teacher, @accion = N'APROBADA', @respuestaDocente = N'Aprobada por QA',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @teacherUser;
    IF (SELECT COUNT(*) FROM #reviewResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51957, 'TEST FAILED: REVIEW_RESOLVE_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_solicitud_revision_asistencia
        WHERE id = @request AND justificacionRespuesta = N'Aprobada por QA')
        THROW 51958, 'TEST FAILED: REVIEW_RESOLVE_SUCCESS response not visible.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_detalle_asistencia
        WHERE id = @detail AND idAsistencia = @attendance AND asistio = 1)
        THROW 51959, 'TEST FAILED: REVIEW_RESOLVE_SUCCESS did not approve attendance.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @session) OR
    EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia WHERE id = @request) OR
    EXISTS (SELECT 1 FROM dbo.Asistencia WHERE id = @attendance)
    THROW 51960, 'TEST FAILED: REVIEW leaked fixture.', 1;
IF @@TRANCOUNT <> 0 THROW 51961, 'TEST FAILED: REVIEW left transaction open.', 1;
PRINT 'TEST_PASS:REVIEW_FILE_INVALID';
PRINT 'TEST_PASS:REVIEW_FILE_SUCCESS';
PRINT 'TEST_PASS:REVIEW_RESOLVE_NON_OWNER';
PRINT 'TEST_PASS:REVIEW_RESOLVE_SUCCESS';
GO
