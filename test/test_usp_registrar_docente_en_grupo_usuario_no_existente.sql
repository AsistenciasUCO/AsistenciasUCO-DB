USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @grupo UNIQUEIDENTIFIER, @originalTeacher UNIQUEIDENTIFIER;
SELECT TOP 1 @grupo = id, @originalTeacher = idDocente
FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 ORDER BY cuposDisponibles DESC;
DECLARE @idUsuarioCoordinadorEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
IF @tipoId IS NULL OR @grupo IS NULL OR @originalTeacher IS NULL OR @idUsuarioCoordinadorEjecutor IS NULL
    THROW 51610, 'TEST FAILED: TEACHER_SUCCESS fixture missing.', 1;

DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.teacher.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1500000000 + ABS(CHECKSUM(NEWID()) % 400000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @usuario UNIQUEIDENTIFIER, @teacher UNIQUEIDENTIFIER;
CREATE TABLE #teacherResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRY
    INSERT INTO #teacherResult
    EXEC dbo.usp_registrar_docente_en_grupo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Docente', @segundoNombre = N'Success',
        @correo = @correo, @password = N'HashBackend_QaTeacher1234567890',
        @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioCoordinadorEjecutor;

    DECLARE @expectedUser NVARCHAR(4000), @expectedTech NVARCHAR(4000);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_005', @p_param1 = 'Docente en Grupo',
        @mensajeUsuarioResultado = @expectedUser OUTPUT, @mensajeTecnicoResultado = @expectedTech OUTPUT;
    IF (SELECT COUNT(*) FROM #teacherResult WHERE idCorrelacion = @corr AND estadoResultado = 1
        AND mensajeUsuarioResultado = @expectedUser
        AND mensajeTecnicoResultado = CONCAT(@expectedTech, ' Correlacion: ', @corr)) <> 1
        THROW 51611, 'TEST FAILED: TEACHER_SUCCESS wrong canonical result.', 1;

    SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    SELECT @teacher = id FROM dbo.Docente WHERE usuario = @usuario;
    IF @usuario IS NULL OR @teacher IS NULL
        THROW 51612, 'TEST FAILED: TEACHER_SUCCESS did not persist Usuario/Docente.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_grupo WHERE id = @grupo AND idDocente = @teacher)
        THROW 51613, 'TEST FAILED: TEACHER_SUCCESS did not assign Docente to Grupo.', 1;

    UPDATE dbo.Grupo SET docente = @originalTeacher WHERE id = @grupo AND docente = @teacher;
    DELETE FROM dbo.Docente WHERE id = @teacher AND usuario = @usuario;
    DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @usuario)
        THROW 51614, 'TEST FAILED: TEACHER_SUCCESS cleanup leaked Usuario.', 1;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @usuario IS NULL SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    IF @teacher IS NULL SELECT @teacher = id FROM dbo.Docente WHERE usuario = @usuario;
    IF @teacher IS NOT NULL BEGIN
        UPDATE dbo.Grupo SET docente = @originalTeacher WHERE id = @grupo AND docente = @teacher;
        DELETE FROM dbo.Docente WHERE id = @teacher AND usuario = @usuario;
    END
    IF @usuario IS NOT NULL DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
    THROW;
END CATCH;
PRINT 'TEST_PASS:TEACHER_SUCCESS';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @missingGroup UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.teacher.missing.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1500000000 + ABS(CHECKSUM(NEWID()) % 400000000);
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @idUsuarioCoordinadorEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
DECLARE @usersBefore INT = (SELECT COUNT(*) FROM dbo.Usuario);
DECLARE @teachersBefore INT = (SELECT COUNT(*) FROM dbo.Docente);
DECLARE @groupsBefore INT = (SELECT COUNT(*) FROM dbo.Grupo);
IF @idUsuarioCoordinadorEjecutor IS NULL THROW 51620, 'TEST FAILED: TEACHER_GROUP_NOT_FOUND fixture missing coordinator.', 1;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_GRUPO_NO_EXISTE',
    @p_param1 = @missingGroup, @mensajeUsuarioResultado = @userMsg OUTPUT,
    @mensajeTecnicoResultado = @techMsg OUTPUT;
PRINT CONCAT('TEST_EXPECTED_USER:TEACHER_GROUP_NOT_FOUND|', @userMsg);
PRINT CONCAT('TEST_EXPECTED_TECH:TEACHER_GROUP_NOT_FOUND|', @techMsg, ' Correlacion: ', @corr);
PRINT 'TEST_RESULT_BEGIN:TEACHER_GROUP_NOT_FOUND';
EXEC dbo.usp_registrar_docente_en_grupo
    @numeroIdentificacion = @numero,
    @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Docente', @segundoNombre = N'Missing',
    @correo = @correo, @password = N'HashBackend_QaTeacher1234567890',
    @idGrupo = @missingGroup, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioCoordinadorEjecutor;
PRINT 'TEST_RESULT_END:TEACHER_GROUP_NOT_FOUND';
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
    THROW 51615, 'TEST FAILED: TEACHER_GROUP_NOT_FOUND left partial Usuario.', 1;
IF EXISTS (SELECT 1 FROM dbo.Docente d JOIN dbo.Usuario u ON u.id = d.usuario WHERE u.numeroIdentificacion = @numero)
    THROW 51616, 'TEST FAILED: TEACHER_GROUP_NOT_FOUND left partial Docente.', 1;
IF EXISTS (SELECT 1 FROM dbo.Grupo WHERE id = @missingGroup)
    THROW 51617, 'TEST FAILED: TEACHER_GROUP_NOT_FOUND changed a group.', 1;
IF @usersBefore <> (SELECT COUNT(*) FROM dbo.Usuario) OR
   @teachersBefore <> (SELECT COUNT(*) FROM dbo.Docente) OR
   @groupsBefore <> (SELECT COUNT(*) FROM dbo.Grupo)
    THROW 51619, 'TEST FAILED: TEACHER_GROUP_NOT_FOUND changed related row counts.', 1;
PRINT 'TEST_STATE_PASS:TEACHER_GROUP_NOT_FOUND';
IF @@TRANCOUNT <> 0 THROW 51618, 'TEST FAILED: teacher tests left transaction open.', 1;
PRINT 'TEST END: test_usp_registrar_docente_en_grupo';
GO
