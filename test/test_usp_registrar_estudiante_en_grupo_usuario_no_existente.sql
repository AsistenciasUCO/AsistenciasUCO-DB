USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @grupo UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0 ORDER BY cuposDisponibles DESC);
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.student.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @usuario UNIQUEIDENTIFIER;
DECLARE @estudiante UNIQUEIDENTIFIER;
DECLARE @idUsuarioEstudianteEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE estaActivoUsuario = 1);

IF @tipoId IS NULL OR @grupo IS NULL OR @idUsuarioEstudianteEjecutor IS NULL THROW 51100, 'TEST FAILED: STUDENT_SUCCESS fixture missing.', 1;

CREATE TABLE #studentResult (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

BEGIN TRY
    INSERT INTO #studentResult
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Estudiante', @segundoNombre = N'Success',
        @correo = @correo, @password = N'HashBackend_QaStudent1234567890',
        @idGrupo = @grupo, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioEstudianteEjecutor;

    DECLARE @expectedUser NVARCHAR(4000), @expectedTech NVARCHAR(4000);
    SELECT @usuario = id FROM dbo.Usuario WHERE correo = @correo;
    SELECT @estudiante = id FROM dbo.Estudiante WHERE usuario = @usuario;
    IF @usuario IS NULL OR @estudiante IS NULL
        THROW 51102, 'TEST FAILED: STUDENT_SUCCESS did not persist Usuario/Estudiante.', 1;
    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = 'GEN_004',
        @p_param1 = 'Estudiante en Grupo',
        @mensajeUsuarioResultado = @expectedUser OUTPUT,
        @mensajeTecnicoResultado = @expectedTech OUTPUT;
    IF (SELECT COUNT(*) FROM #studentResult WHERE estadoResultado = 1 AND idCorrelacion = @corr
        AND mensajeUsuarioResultado = @expectedUser
        AND mensajeTecnicoResultado = CONCAT(@expectedTech, ' Correlacion: ', @corr)) <> 1
        THROW 51101, 'TEST FAILED: STUDENT_SUCCESS wrong canonical result.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_grupo WHERE idEstudiante = @estudiante AND idGrupo = @grupo)
        THROW 51103, 'TEST FAILED: STUDENT_SUCCESS did not persist EstudianteGrupo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_estudiante_programa WHERE idEstudiante = @estudiante)
        THROW 51104, 'TEST FAILED: STUDENT_SUCCESS did not persist EstudiantePrograma.', 1;

    DECLARE @dupCorr UNIQUEIDENTIFIER = NEWID(), @dupUser NVARCHAR(4000), @dupTech NVARCHAR(4000);
    DECLARE @dupUserCount INT = (SELECT COUNT(*) FROM dbo.Usuario WHERE id = @usuario);
    DECLARE @dupStudentCount INT = (SELECT COUNT(*) FROM dbo.Estudiante WHERE id = @estudiante);
    DECLARE @dupLinkCount INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante);
    DECLARE @dupProgramCount INT = (SELECT COUNT(*) FROM dbo.EstudiantePrograma WHERE estudiante = @estudiante);
    EXEC dbo.usp_obtener_mensaje_catalogo
        @p_codigo = 'ERR_MATRICULA_DUPLICADA',
        @p_param1 = @estudiante, @p_param2 = @grupo,
        @mensajeUsuarioResultado = @dupUser OUTPUT,
        @mensajeTecnicoResultado = @dupTech OUTPUT;
    PRINT CONCAT('TEST_EXPECTED_USER:STUDENT_DUPLICATE|', @dupUser);
    PRINT CONCAT('TEST_EXPECTED_TECH:STUDENT_DUPLICATE|', @dupTech, ' Correlacion: ', @dupCorr);
    PRINT 'TEST_RESULT_BEGIN:STUDENT_DUPLICATE';
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Duplicado', @segundoApellido = N'Gate',
        @primerNombre = N'Estudiante', @segundoNombre = N'QA',
        @correo = @correo, @password = N'HashBackend_QaStudent1234567890',
        @idGrupo = @grupo, @idCorrelacion = @dupCorr, @idUsuarioEjecutor = @idUsuarioEstudianteEjecutor;
    PRINT 'TEST_RESULT_END:STUDENT_DUPLICATE';
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @usuario AND primerApellido = N'Quality')
        THROW 51105, 'TEST FAILED: STUDENT_DUPLICATE changed the existing user.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante AND grupo = @grupo) <> 1
        THROW 51106, 'TEST FAILED: STUDENT_DUPLICATE changed group membership.', 1;
    IF @dupUserCount <> (SELECT COUNT(*) FROM dbo.Usuario WHERE id = @usuario) OR
       @dupStudentCount <> (SELECT COUNT(*) FROM dbo.Estudiante WHERE id = @estudiante) OR
       @dupLinkCount <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante) OR
       @dupProgramCount <> (SELECT COUNT(*) FROM dbo.EstudiantePrograma WHERE estudiante = @estudiante)
        THROW 51117, 'TEST FAILED: STUDENT_DUPLICATE changed related row counts.', 1;
    PRINT 'TEST_STATE_PASS:STUDENT_DUPLICATE';

    DELETE FROM dbo.EstudianteGrupo WHERE estudiante = @estudiante AND grupo = @grupo;
    DELETE FROM dbo.EstudiantePrograma WHERE estudiante = @estudiante;
    DELETE FROM dbo.Estudiante WHERE id = @estudiante AND usuario = @usuario;
    DELETE FROM dbo.Usuario WHERE id = @usuario AND correo = @correo;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @usuario)
        THROW 51107, 'TEST FAILED: STUDENT_SUCCESS cleanup leaked Usuario.', 1;
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
PRINT 'TEST_PASS:STUDENT_SUCCESS';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @missingGroup UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.student.missing.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @idUsuarioEstudianteEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE estaActivoUsuario = 1);
DECLARE @usersBefore INT = (SELECT COUNT(*) FROM dbo.Usuario);
DECLARE @studentsBefore INT = (SELECT COUNT(*) FROM dbo.Estudiante);
DECLARE @linksBefore INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
DECLARE @programsBefore INT = (SELECT COUNT(*) FROM dbo.EstudiantePrograma);
IF @idUsuarioEstudianteEjecutor IS NULL THROW 51121, 'TEST FAILED: STUDENT_GROUP_NOT_FOUND executor fixture missing.', 1;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_GRUPO_NO_EXISTE',
    @p_param1 = @missingGroup, @mensajeUsuarioResultado = @userMsg OUTPUT,
    @mensajeTecnicoResultado = @techMsg OUTPUT;
PRINT CONCAT('TEST_EXPECTED_USER:STUDENT_GROUP_NOT_FOUND|', @userMsg);
PRINT CONCAT('TEST_EXPECTED_TECH:STUDENT_GROUP_NOT_FOUND|', @techMsg, ' Correlacion: ', @corr);
PRINT 'TEST_RESULT_BEGIN:STUDENT_GROUP_NOT_FOUND';
EXEC dbo.usp_registrar_estudiante_en_grupo
    @numeroIdentificacion = @numero,
    @primerApellido = N'Quality', @segundoApellido = N'Gate',
    @primerNombre = N'Estudiante', @segundoNombre = N'Missing',
    @correo = @correo, @password = N'HashBackend_QaStudent1234567890',
    @idGrupo = @missingGroup, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioEstudianteEjecutor;
PRINT 'TEST_RESULT_END:STUDENT_GROUP_NOT_FOUND';
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
    THROW 51108, 'TEST FAILED: STUDENT_GROUP_NOT_FOUND left a partial Usuario.', 1;
IF EXISTS (SELECT 1 FROM dbo.Estudiante e JOIN dbo.Usuario u ON u.id = e.usuario WHERE u.numeroIdentificacion = @numero)
    THROW 51109, 'TEST FAILED: STUDENT_GROUP_NOT_FOUND left a partial Estudiante.', 1;
IF @usersBefore <> (SELECT COUNT(*) FROM dbo.Usuario) OR
   @studentsBefore <> (SELECT COUNT(*) FROM dbo.Estudiante) OR
   @linksBefore <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo) OR
   @programsBefore <> (SELECT COUNT(*) FROM dbo.EstudiantePrograma)
    THROW 51118, 'TEST FAILED: STUDENT_GROUP_NOT_FOUND changed related row counts.', 1;
PRINT 'TEST_STATE_PASS:STUDENT_GROUP_NOT_FOUND';
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @baseGroup UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0);
DECLARE @institution UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT idAsignatura FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT idDocente FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @period UNIQUEIDENTIFIER = NEWID(), @closedGroup UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.student.closed.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @idUsuarioEstudianteEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE estaActivoUsuario = 1);
IF @baseGroup IS NULL OR @institution IS NULL OR @idUsuarioEstudianteEjecutor IS NULL THROW 51110, 'TEST FAILED: STUDENT_GROUP_DISABLED fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio)
    VALUES (@period, @institution, N'Periodo QA Cerrado', 200000 + ABS(CHECKSUM(NEWID()) % 100000), '2000-01-01', '2000-01-31', 2000);
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@closedGroup, @assignment, @period, 200000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Cerrado', 10, 0, 0, 0, @teacher);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_GRUPO_NO_HABILITADO',
        @p_param1 = @closedGroup, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT;
    DECLARE @usersBefore INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @studentsBefore INT = (SELECT COUNT(*) FROM dbo.Estudiante);
    DECLARE @linksBefore INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    DECLARE @programsBefore INT = (SELECT COUNT(*) FROM dbo.EstudiantePrograma);
    PRINT CONCAT('TEST_EXPECTED_USER:STUDENT_GROUP_DISABLED|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:STUDENT_GROUP_DISABLED|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:STUDENT_GROUP_DISABLED';
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Estudiante', @segundoNombre = N'Closed',
        @correo = @correo, @password = N'HashBackend_QaStudent1234567890',
        @idGrupo = @closedGroup, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioEstudianteEjecutor;
    PRINT 'TEST_RESULT_END:STUDENT_GROUP_DISABLED';
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
        THROW 51111, 'TEST FAILED: STUDENT_GROUP_DISABLED left partial Usuario.', 1;
    IF EXISTS (SELECT 1 FROM dbo.EstudianteGrupo WHERE grupo = @closedGroup)
        THROW 51112, 'TEST FAILED: STUDENT_GROUP_DISABLED left partial membership.', 1;
    IF @usersBefore <> (SELECT COUNT(*) FROM dbo.Usuario) OR
       @studentsBefore <> (SELECT COUNT(*) FROM dbo.Estudiante) OR
       @linksBefore <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo) OR
       @programsBefore <> (SELECT COUNT(*) FROM dbo.EstudiantePrograma)
        THROW 51119, 'TEST FAILED: STUDENT_GROUP_DISABLED changed related row counts.', 1;
    PRINT 'TEST_STATE_PASS:STUDENT_GROUP_DISABLED';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @baseGroup UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_grupo WHERE grupoEstaHablitado = 1 AND cuposDisponibles > 0);
DECLARE @assignment UNIQUEIDENTIFIER = (SELECT idAsignatura FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @period UNIQUEIDENTIFIER = (SELECT idPeriodoAcademico FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @teacher UNIQUEIDENTIFIER = (SELECT idDocente FROM dbo.uv_grupo WHERE id = @baseGroup);
DECLARE @existingStudent UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Estudiante);
DECLARE @activeState UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_estado_estudiante_grupo WHERE codigo = 'A');
DECLARE @fullGroup UNIQUEIDENTIFIER = NEWID(), @corr UNIQUEIDENTIFIER = NEWID();
DECLARE @correo NVARCHAR(255) = CONCAT(N'qa.student.full.', REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), N'@test.local');
DECLARE @numero INT = 1000000000 + ABS(CHECKSUM(NEWID()) % 500000000);
DECLARE @userMsg NVARCHAR(4000), @techMsg NVARCHAR(4000);
DECLARE @idUsuarioEstudianteEjecutor UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_docente_identidad WHERE estaActivoUsuario = 1);
IF @baseGroup IS NULL OR @existingStudent IS NULL OR @activeState IS NULL OR @idUsuarioEstudianteEjecutor IS NULL
    THROW 51113, 'TEST FAILED: STUDENT_CAPACITY_EXCEEDED fixture missing.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    INSERT dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes,
        cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia,
        cantidadEstudiantesCancelaronAutomaticamente, docente)
    VALUES (@fullGroup, @assignment, @period, 300000 + ABS(CHECKSUM(NEWID()) % 100000),
        N'Grupo QA Sin Cupo', 1, 0, 0, 0, @teacher);
    INSERT dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    VALUES (NEWID(), @activeState, @existingStudent, @fullGroup);
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'ERR_CUPO_SUPERADO',
        @p_param1 = @fullGroup, @mensajeUsuarioResultado = @userMsg OUTPUT,
        @mensajeTecnicoResultado = @techMsg OUTPUT;
    DECLARE @usersBefore INT = (SELECT COUNT(*) FROM dbo.Usuario);
    DECLARE @studentsBefore INT = (SELECT COUNT(*) FROM dbo.Estudiante);
    DECLARE @linksBefore INT = (SELECT COUNT(*) FROM dbo.EstudianteGrupo);
    DECLARE @programsBefore INT = (SELECT COUNT(*) FROM dbo.EstudiantePrograma);
    PRINT CONCAT('TEST_EXPECTED_USER:STUDENT_CAPACITY_EXCEEDED|', @userMsg);
    PRINT CONCAT('TEST_EXPECTED_TECH:STUDENT_CAPACITY_EXCEEDED|', @techMsg, ' Correlacion: ', @corr);
    PRINT 'TEST_RESULT_BEGIN:STUDENT_CAPACITY_EXCEEDED';
    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = @numero,
        @primerApellido = N'Quality', @segundoApellido = N'Gate',
        @primerNombre = N'Estudiante', @segundoNombre = N'Full',
        @correo = @correo, @password = N'HashBackend_QaStudent1234567890',
        @idGrupo = @fullGroup, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioEstudianteEjecutor;
    PRINT 'TEST_RESULT_END:STUDENT_CAPACITY_EXCEEDED';
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correo)
        THROW 51114, 'TEST FAILED: STUDENT_CAPACITY_EXCEEDED left partial Usuario.', 1;
    IF (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE grupo = @fullGroup) <> 1
        THROW 51115, 'TEST FAILED: STUDENT_CAPACITY_EXCEEDED changed group membership.', 1;
    IF @usersBefore <> (SELECT COUNT(*) FROM dbo.Usuario) OR
       @studentsBefore <> (SELECT COUNT(*) FROM dbo.Estudiante) OR
       @linksBefore <> (SELECT COUNT(*) FROM dbo.EstudianteGrupo) OR
       @programsBefore <> (SELECT COUNT(*) FROM dbo.EstudiantePrograma)
        THROW 51120, 'TEST FAILED: STUDENT_CAPACITY_EXCEEDED changed related row counts.', 1;
    PRINT 'TEST_STATE_PASS:STUDENT_CAPACITY_EXCEEDED';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 51116, 'TEST FAILED: student test left an open transaction.', 1;
PRINT 'TEST END: test_usp_registrar_estudiante_en_grupo';
GO
