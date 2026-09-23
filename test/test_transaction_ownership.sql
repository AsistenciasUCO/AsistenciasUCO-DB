USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_transaction_ownership';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idPrograma UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa);
DECLARE @idFacultad UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa WHERE id = @idPrograma);
DECLARE @studentUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_estudiante_identidad WHERE estaActivoUsuario = 1);
DECLARE @coordinatorUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_coordinador_identidad WHERE estaActivoUsuario = 1);
DECLARE @deanUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE estaActivoUsuario = 1);
DECLARE @adminUser UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoUsuario = 1);

IF @tipoId IS NULL THROW 51500, 'TEST FAILED: no existe fixture CC.', 1;
IF @idPrograma IS NULL THROW 51501, 'TEST FAILED: no existe fixture uv_programa.', 1;
IF @idFacultad IS NULL THROW 51502, 'TEST FAILED: programa no expone facultad.', 1;
IF @studentUser IS NULL OR @coordinatorUser IS NULL OR @deanUser IS NULL OR @adminUser IS NULL THROW 51512, 'TEST FAILED: ownership executor fixtures missing.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @beforeEst INT = @@TRANCOUNT;
    DECLARE @correoEst NVARCHAR(255) = N'ownership.estudiante@test.local';
    DECLARE @corrEst UNIQUEIDENTIFIER = NEWID();

    EXEC dbo.usp_registrar_estudiante_en_grupo
        @numeroIdentificacion = 935000001,
        @primerApellido = N'Ownership',
        @segundoApellido = N'Estudiante',
        @primerNombre = N'QA',
        @segundoNombre = N'Test',
        @correo = @correoEst,
        @password = N'HashBackend_QaOwnership1234567890',
        @idGrupo = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        @idCorrelacion = @corrEst,
        @idUsuarioEjecutor = @studentUser;

    IF @@TRANCOUNT <> @beforeEst THROW 51503, 'TEST FAILED: estudiante hizo rollback/commit total de transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correoEst) THROW 51504, 'TEST FAILED: estudiante dejo Usuario parcial tras rollback a savepoint.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
PRINT 'TEST PASS: ownership estudiante outer transaction preserved, savepoint rollback parcial.';
PRINT 'TEST_PASS:OWNERSHIP_STUDENT';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @beforeDoc INT = @@TRANCOUNT;
    DECLARE @correoDoc NVARCHAR(255) = N'ownership.docente@test.local';
    DECLARE @corrDoc UNIQUEIDENTIFIER = NEWID();

    EXEC dbo.usp_registrar_docente_en_grupo
        @numeroIdentificacion = 935000002,
        @primerApellido = N'Ownership',
        @segundoApellido = N'Docente',
        @primerNombre = N'QA',
        @segundoNombre = N'Test',
        @correo = @correoDoc,
        @password = N'HashBackend_QaOwnership1234567890',
        @idGrupo = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        @idCorrelacion = @corrDoc,
        @idUsuarioEjecutor = @coordinatorUser;

    IF @@TRANCOUNT <> @beforeDoc THROW 51505, 'TEST FAILED: docente hizo rollback/commit total de transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correoDoc) THROW 51506, 'TEST FAILED: docente dejo Usuario parcial tras rollback a savepoint.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
PRINT 'TEST PASS: ownership docente outer transaction preserved, savepoint rollback parcial.';
PRINT 'TEST_PASS:OWNERSHIP_TEACHER';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @beforeCoord INT = @@TRANCOUNT;
    DECLARE @correoCoord NVARCHAR(100) = N'ownership.coordinador@test.local';
    DECLARE @corrCoord UNIQUEIDENTIFIER = NEWID();

    EXEC dbo.usp_crear_coordinador
        @idCoordinador = NULL,
        @numeroIdentificacion = NULL,
        @primerNombre = NULL,
        @segundoNombre = N'',
        @primerApellido = NULL,
        @segundoApellido = N'',
        @correo = @correoCoord,
        @idPrograma = @idPrograma,
        @idFacultad = @idFacultad,
        @password = NULL,
        @idCorrelacion = @corrCoord,
        @idUsuarioEjecutor = @deanUser;

    IF @@TRANCOUNT <> @beforeCoord THROW 51507, 'TEST FAILED: coordinador hizo rollback/commit total de transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = @correoCoord) THROW 51508, 'TEST FAILED: coordinador dejo Usuario parcial tras fallo post-savepoint.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
PRINT 'TEST PASS: ownership coordinador fallo post-savepoint preserva transaccion externa.';
PRINT 'TEST_PASS:OWNERSHIP_COORDINATOR';

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @beforeDec INT = @@TRANCOUNT;
    DECLARE @corrDec UNIQUEIDENTIFIER = NEWID();

    EXEC dbo.usp_crear_decano
        @idDecano = NULL,
        @numeroIdentificacion = NULL,
        @primerNombre = NULL,
        @segundoNombre = N'',
        @primerApellido = NULL,
        @segundoApellido = N'',
        @correo = N'ownership.decano@test.local',
        @idFacultad = @idFacultad,
        @nombreFacultad = NULL,
        @password = NULL,
        @idCorrelacion = @corrDec,
        @idUsuarioEjecutor = @adminUser;

    IF @@TRANCOUNT <> @beforeDec THROW 51509, 'TEST FAILED: decano hizo rollback/commit total de transaccion externa.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'ownership.decano@test.local') THROW 51510, 'TEST FAILED: decano dejo Usuario parcial tras fallo post-savepoint.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;
PRINT 'TEST PASS: ownership decano outer transaction preserved, savepoint rollback parcial.';
PRINT 'TEST_PASS:OWNERSHIP_DEAN';

IF @@TRANCOUNT <> 0 THROW 51511, 'TEST FAILED: transaction ownership dejo transacciones abiertas.', 1;
PRINT 'TEST_SKIP:XACT_STATE_MINUS_ONE_RUNTIME';
PRINT 'TEST END: test_transaction_ownership';
GO
