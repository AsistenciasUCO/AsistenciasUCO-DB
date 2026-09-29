USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @grupo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 ORDER BY cuposDisponibles DESC);
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.teacher.auto.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @usuario UNIQUEIDENTIFIER;
DECLARE @docente UNIQUEIDENTIFIER;

IF @tipoId IS NULL OR @grupo IS NULL THROW 51100, 'TEST FAILED: TEACHER_AUTONOMOUS_SUCCESS fixture missing.', 1;

CREATE TABLE #teacherAutoResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRY
    INSERT INTO #teacherAutoResult
    EXEC dbo.usp_registrar_docente_en_grupo_autonomo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Docente', @segundoNombre = N'Autonomo',
        @correo = @correo, @password = N'HashBackend_QaTeacherAuto1234567890',
        @idGrupo = @grupo, @idCorrelacion = @corr;

    SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    SELECT @docente = id FROM dbo.Docente WHERE usuario = @usuario;

    IF @usuario IS NULL OR @docente IS NULL
        THROW 51102, 'TEST FAILED: TEACHER_AUTONOMOUS_SUCCESS did not persist Usuario/Docente.', 1;

    -- Validar que el usuario docente fue creado en estado Inactivo (0)
    IF (SELECT estado FROM dbo.Usuario WHERE id = @usuario) <> 0
        THROW 51105, 'TEST FAILED: TEACHER_AUTONOMOUS_SUCCESS did not set Usuario.estado to 0 (Inactivo).', 1;

    DELETE FROM dbo.Docente WHERE id = @docente AND usuario = @usuario;
    DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @usuario IS NULL SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    IF @docente IS NULL SELECT @docente = id FROM dbo.Docente WHERE usuario = @usuario;
    IF @docente IS NOT NULL DELETE FROM dbo.Docente WHERE id = @docente AND usuario = @usuario;
    IF @usuario IS NOT NULL DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
    THROW;
END CATCH;

PRINT 'TEST_PASS:TEACHER_AUTONOMOUS_SUCCESS';
GO
