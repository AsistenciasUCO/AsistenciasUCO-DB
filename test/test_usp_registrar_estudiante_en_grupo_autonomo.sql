USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @grupo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0 ORDER BY cuposDisponibles DESC);
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.student.auto.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @usuario UNIQUEIDENTIFIER;
DECLARE @estudiante UNIQUEIDENTIFIER;

IF @tipoId IS NULL OR @grupo IS NULL THROW 51100, 'TEST FAILED: STUDENT_AUTONOMOUS_SUCCESS fixture missing.', 1;

CREATE TABLE #studentAutoResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRY
    INSERT INTO #studentAutoResult
    EXEC dbo.usp_registrar_estudiante_en_grupo_autonomo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Estudiante', @segundoNombre = N'Autonomo',
        @correo = @correo, @password = N'HashBackend_QaStudentAuto1234567890',
        @idGrupo = @grupo, @idCorrelacion = @corr;

    SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    SELECT @estudiante = id FROM dbo.Estudiante WHERE usuario = @usuario;

    IF @usuario IS NULL OR @estudiante IS NULL
        THROW 51102, 'TEST FAILED: STUDENT_AUTONOMOUS_SUCCESS did not persist Usuario/Estudiante.', 1;

    -- Validar que el usuario fue creado en estado Inactivo (0)
    IF (SELECT estado FROM dbo.Usuario WHERE id = @usuario) <> 0
        THROW 51105, 'TEST FAILED: STUDENT_AUTONOMOUS_SUCCESS did not set Usuario.estado to 0 (Inactivo).', 1;

    -- Validar que la pre-matrícula fue creada en estado Inactivo ('I')
    IF NOT EXISTS (
        SELECT 1 FROM dbo.EstudianteGrupo eg
        INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eg.estado = eeg.id
        WHERE eg.estudiante = @estudiante AND eg.grupo = @grupo AND eeg.codigo = 'I'
    )
        THROW 51103, 'TEST FAILED: STUDENT_AUTONOMOUS_SUCCESS did not set EstudianteGrupo estado to Inactivo (I).', 1;

    DELETE FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante AND grupo = @grupo;
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @estudiante;
    DELETE FROM dbo.Estudiante WHERE id = @estudiante AND usuario = @usuario;
    DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    IF @usuario IS NULL SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    IF @estudiante IS NULL SELECT @estudiante = id FROM dbo.Estudiante WHERE usuario = @usuario;
    IF @estudiante IS NOT NULL BEGIN
        DELETE FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante AND grupo = @grupo;
        DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @estudiante;
        DELETE FROM dbo.Estudiante WHERE id = @estudiante AND usuario = @usuario;
    END
    IF @usuario IS NOT NULL DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
    THROW;
END CATCH;

PRINT 'TEST_PASS:STUDENT_AUTONOMOUS_SUCCESS';
GO
