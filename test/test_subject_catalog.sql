USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @plan UNIQUEIDENTIFIER = (SELECT TOP 1 idPlanEstudio FROM dbo.uv_semestre_plan_estudio);
DECLARE @semester INT = (SELECT TOP 1 numero FROM dbo.uv_semestre);
DECLARE @coordinatorUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
DECLARE @subject UNIQUEIDENTIFIER = NEWID();
DECLARE @code NVARCHAR(50) = CONCAT(N'QA', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10));
DECLARE @reactiveCode NVARCHAR(50) = CONCAT(N'QR', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 10));
DECLARE @messageCode NVARCHAR(50) = CONCAT(N'QA_', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 12));
DECLARE @corr UNIQUEIDENTIFIER, @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @reactiveId UNIQUEIDENTIFIER, @missingSubject UNIQUEIDENTIFIER = NEWID();
DECLARE @reactiveRequestedId UNIQUEIDENTIFIER = NEWID();
IF @plan IS NULL OR @semester IS NULL OR @coordinatorUser IS NULL THROW 51970, 'TEST FAILED: SUBJECT fixture missing.', 1;
CREATE TABLE #subjectResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
BEGIN TRANSACTION;
BEGIN TRY
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Asignatura',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #subjectResult
    EXEC dbo.usp_crear_asignatura @idAsignatura = @subject, @codigo = @code,
        @nombre = N'QA Materia', @creditos = 4, @idPlanEstudio = @plan,
        @semestreNumero = @semester, @nombreArea = NULL, @nombreComponente = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @coordinatorUser;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51971, 'TEST FAILED: SUBJECT_CREATE wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @subject AND codigo = @code AND credito = 4)
        THROW 51972, 'TEST FAILED: SUBJECT_CREATE not visible.', 1;

    TRUNCATE TABLE #subjectResult;
    SET @corr = NEWID();
    INSERT INTO #subjectResult
    EXEC dbo.usp_actualizar_asignatura @idAsignatura = @subject, @codigo = NULL,
        @nombre = N'QA Materia Editada', @creditos = 5, @idPlanEstudio = @plan,
        @semestreNumero = @semester, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1
        THROW 51973, 'TEST FAILED: SUBJECT_UPDATE wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @subject
        AND nombre = N'QA Materia Editada' AND credito = 5)
        THROW 51974, 'TEST FAILED: SUBJECT_UPDATE did not persist fields.', 1;

    TRUNCATE TABLE #subjectResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'EstadoAsignatura',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #subjectResult
    EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @subject, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51975, 'TEST FAILED: SUBJECT_TOGGLE wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @subject AND estaActivaAsignatura = 0)
        THROW 51976, 'TEST FAILED: SUBJECT_TOGGLE did not deactivate.', 1;
    SET @corr = NEWID();
    TRUNCATE TABLE #subjectResult;
    INSERT INTO #subjectResult
    EXEC dbo.usp_toggle_estado_asignatura @idAsignatura = @subject, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1) <> 1 OR
        NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @subject AND estaActivaAsignatura = 1)
        THROW 51977, 'TEST FAILED: SUBJECT_TOGGLE did not restore state.', 1;

    TRUNCATE TABLE #subjectResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Asignatura',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #subjectResult
    EXEC dbo.usp_crear_asignatura @idAsignatura = @reactiveRequestedId, @codigo = @reactiveCode,
        @nombre = N'QA Reactiva', @creditos = 3, @idPlanEstudio = @plan,
        @semestreNumero = @semester, @nombreArea = NULL, @nombreComponente = NULL,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @coordinatorUser;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51978, 'TEST FAILED: SUBJECT_UPSERT_CREATE wrong canonical result.', 1;
    SELECT @reactiveId = id FROM dbo.uv_asignatura WHERE codigo = @reactiveCode;
    IF @reactiveId IS NULL THROW 51979, 'TEST FAILED: SUBJECT_UPSERT_CREATE not visible.', 1;
    TRUNCATE TABLE #subjectResult;
    SET @corr = NEWID();
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Asignatura',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #subjectResult
    EXEC dbo.usp_actualizar_asignatura @idAsignatura = @reactiveId, @codigo = @reactiveCode,
        @nombre = N'QA Reactiva Editada', @creditos = 6, @idPlanEstudio = @plan,
        @semestreNumero = @semester, @nombreArea = NULL, @nombreComponente = NULL, @idCorrelacion = @corr;
    IF (SELECT COUNT(*) FROM #subjectResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg) <> 1 OR
        NOT EXISTS (SELECT 1 FROM dbo.uv_asignatura WHERE id = @reactiveId AND credito = 6 AND nombre = N'QA REACTIVA EDITADA')
        THROW 51980, 'TEST FAILED: SUBJECT_UPSERT_UPDATE wrong result/persistence.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeUsuario WHERE codigo = @messageCode)
        INSERT INTO dbo.CatalogoMensajeUsuario (codigo, tipoMensaje, severidad, contenido) VALUES (@messageCode, N'SUCCESS', N'BAJO', N'QA catalog message');
    IF NOT EXISTS (SELECT 1 FROM dbo.CatalogoMensajeTecnico WHERE codigo = @messageCode)
        INSERT INTO dbo.CatalogoMensajeTecnico (codigo, tipoMensaje, severidad, contenido) VALUES (@messageCode, N'SUCCESS', N'BAJO', N'QA catalog message');
    IF (SELECT COUNT(*) FROM dbo.uv_mensaje_usuario WHERE codigo = @messageCode AND contenido = N'QA catalog message') <> 1 OR
       (SELECT COUNT(*) FROM dbo.uv_mensaje_tecnico WHERE codigo = @messageCode AND contenido = N'QA catalog message') <> 1
        THROW 51981, 'TEST FAILED: CATALOG_INSERT is not idempotent.', 1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @messageCode,
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    IF @userMsg <> N'QA catalog message' OR @techMsg <> N'QA catalog message'
        THROW 51982, 'TEST FAILED: CATALOG_GET returned wrong content.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Asignatura WHERE id IN (@subject, @reactiveId)) OR
   EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario WHERE codigo = @messageCode)
    THROW 51983, 'TEST FAILED: SUBJECT/CATALOG leaked fixtures.', 1;
IF @@TRANCOUNT <> 0 THROW 51984, 'TEST FAILED: SUBJECT/CATALOG left transaction open.', 1;
PRINT 'TEST_PASS:SUBJECT_CREATE';
PRINT 'TEST_PASS:SUBJECT_UPDATE';
PRINT 'TEST_PASS:SUBJECT_TOGGLE';
PRINT 'TEST_PASS:SUBJECT_UPSERT_CREATE';
PRINT 'TEST_PASS:SUBJECT_UPSERT_UPDATE';
PRINT 'TEST_PASS:CATALOG_INSERT';
PRINT 'TEST_PASS:CATALOG_GET';
GO
