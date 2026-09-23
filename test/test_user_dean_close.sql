USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @type UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @email NVARCHAR(255) = CONCAT(N'qa.sync.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @number INT = 1100000000 + ABS(CHECKSUM(NEWID()) % 300000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID(), @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @userMsgOut NVARCHAR(4000), @techMsgOut NVARCHAR(4000), @statusOut BIT;
DECLARE @user UNIQUEIDENTIFIER;
IF @type IS NULL THROW 51920, 'TEST FAILED: USER_SYNC fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Usuario',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @type, @numeroIdentificacion = @number,
        @primerApellido = N'Quality', @segundoApellido = N'Gate', @primerNombre = N'Usuario',
        @segundoNombre = N'Sync', @correo = @email, @password = N'HashBackend_QaSync1234567890',
        @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsgOut OUTPUT,
        @mensajeTecnicoResultado = @techMsgOut OUTPUT,
        @estadoResultado = @statusOut OUTPUT;
    IF NOT (@statusOut = 1 AND @userMsgOut = @userMsg AND @techMsgOut = CONCAT(@techMsg, ' Correlacion: ', @corr))
        THROW 51921, 'TEST FAILED: USER_SYNC_SUCCESS wrong canonical result.', 1;
    SELECT @user = id FROM dbo.uv_usuario WHERE correo = @email;
    IF @user IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_usuario_autenticacion
        WHERE idUsuario = @user AND correo = @email AND password = N'HashBackend_QaSync1234567890'
        AND estaActivoUsuario = 1)
        THROW 51922, 'TEST FAILED: USER_SYNC_SUCCESS not visible in identity/auth views.', 1;

    SET @corr = NEWID();
    DECLARE @badEmail NVARCHAR(255) = CONCAT(N'not-an-email-', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''));
    DECLARE @badNumber INT = @number + 1;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'VAL_005',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @type, @numeroIdentificacion = @badNumber,
        @primerApellido = N'Quality', @segundoApellido = N'Gate', @primerNombre = N'Usuario',
        @segundoNombre = N'Invalid', @correo = @badEmail, @password = N'HashBackend_QaSync1234567890',
        @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @userMsgOut OUTPUT,
        @mensajeTecnicoResultado = @techMsgOut OUTPUT,
        @estadoResultado = @statusOut OUTPUT;
    IF NOT (@statusOut = 0 AND @userMsgOut = @userMsg AND @techMsgOut = CONCAT(@techMsg, ' Correlacion: ', @corr))
        THROW 51923, 'TEST FAILED: USER_SYNC_INVALID wrong canonical result.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @badEmail)
        THROW 51924, 'TEST FAILED: USER_SYNC_INVALID wrote user.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @user) THROW 51925, 'TEST FAILED: USER_SYNC leaked user.', 1;
PRINT 'TEST_PASS:USER_SYNC_SUCCESS';
PRINT 'TEST_PASS:USER_SYNC_INVALID';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @faculty UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_facultad);
DECLARE @oldDean UNIQUEIDENTIFIER = (SELECT decano FROM dbo.Facultad WHERE id = @faculty);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);
DECLARE @newDean UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @email NVARCHAR(100) = CONCAT(N'qa.dean.', LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 20), N'@test.local');
DECLARE @number INT = 1500000000 + ABS(CHECKSUM(NEWID()) % 300000000);
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
IF @faculty IS NULL OR @adminUser IS NULL THROW 51930, 'TEST FAILED: DEAN_SUCCESS faculty/admin fixture missing.', 1;
CREATE TABLE #deanResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
BEGIN TRANSACTION;
BEGIN TRY
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Decano',
        @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
    INSERT INTO #deanResult
    EXEC dbo.usp_crear_decano @idDecano = @newDean, @numeroIdentificacion = @number,
        @primerNombre = N'Decano', @segundoNombre = N'QA', @primerApellido = N'Quality',
        @segundoApellido = N'Gate', @correo = @email, @idFacultad = @faculty,
        @nombreFacultad = NULL, @password = N'HashBackend_QaDean1234567890',
        @idCorrelacion = @corr, @idUsuarioEjecutor = @adminUser;
    IF (SELECT COUNT(*) FROM #deanResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @userMsg
        AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
        THROW 51931, 'TEST FAILED: DEAN_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_decano WHERE id = @newDean AND idFacultad = @faculty)
        THROW 51932, 'TEST FAILED: DEAN_SUCCESS not visible by uv_decano.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario u JOIN dbo.Decano d ON d.usuario = u.id
        JOIN dbo.Facultad f ON f.decano = d.id WHERE u.correo = @email AND d.id = @newDean AND f.id = @faculty)
        THROW 51933, 'TEST FAILED: DEAN_SUCCESS did not persist user/dean/faculty.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @email) OR EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @newDean)
    THROW 51934, 'TEST FAILED: DEAN_SUCCESS leaked fixture.', 1;
IF EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @faculty AND
    ((@oldDean IS NULL AND decano IS NOT NULL) OR (@oldDean IS NOT NULL AND decano <> @oldDean)))
    THROW 51935, 'TEST FAILED: DEAN_SUCCESS did not restore faculty.', 1;
PRINT 'TEST_PASS:DEAN_SUCCESS';
GO

SET NOCOUNT ON;
DECLARE @session UNIQUEIDENTIFIER, @group UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
SELECT TOP 1 @session = s.id, @group = s.idGrupo, @teacher = g.idDocente
FROM dbo.uv_sesion s JOIN dbo.uv_grupo g ON g.id = s.idGrupo
WHERE g.grupoEstaHablitado = 1 ORDER BY s.id;
IF @session IS NULL OR @teacher IS NULL THROW 51940, 'TEST FAILED: SESSION_CLOSE fixture missing.', 1;
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
CREATE TABLE #closeResult (idCorrelacion UNIQUEIDENTIFIER NULL, mensajeUsuarioResultado NVARCHAR(MAX),
    mensajeTecnicoResultado NVARCHAR(MAX), estadoResultado INT NOT NULL);
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SES_003', @p_param1 = @session,
    @mensajeUsuarioResultado = @userMsg OUTPUT, @mensajeTecnicoResultado = @techMsg OUTPUT;
INSERT INTO #closeResult
EXEC dbo.usp_cerrar_sesion @idSesion = @session, @idDocente = @teacher, @idCorrelacion = @corr;
IF (SELECT COUNT(*) FROM #closeResult WHERE idCorrelacion = @corr AND estadoResultado = 0
    AND mensajeUsuarioResultado = @userMsg
    AND mensajeTecnicoResultado = CONCAT(@techMsg, ' Correlacion: ', @corr)) <> 1
    THROW 51941, 'TEST FAILED: SESSION_CLOSE_NOT_SUPPORTED wrong canonical result.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.uv_sesion WHERE id = @session AND idGrupo = @group)
    THROW 51944, 'TEST FAILED: SESSION_CLOSE changed/deleted session.', 1;
PRINT 'TEST_PASS:SESSION_CLOSE_NOT_SUPPORTED';
GO
