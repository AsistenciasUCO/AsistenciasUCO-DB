USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- SEC-BASELINE-017: vinculo estable (emisor, sujeto) -> Usuario.id.
-- Cubre: primera vinculacion, repeticion idempotente, usuario inexistente, usuario inactivo, parametros vacios,
-- dos identidades sobre una cuenta, una identidad sobre dos cuentas, revocacion, no reutilizacion tras revocar,
-- revocacion idempotente y revocacion de un vinculo inexistente.
PRINT 'TEST START: test_sec_baseline_identidad_externa';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
IF @tipoId IS NULL THROW 51900, 'TEST FAILED: no existe fixture CC.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #vinculo (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                           estadoResultado BIT);
    CREATE TABLE #revoca (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                          estadoResultado BIT);

    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @corr UNIQUEIDENTIFIER;
    DECLARE @emisor NVARCHAR(400) = N'http://keycloak.localhost:19090/realms/security-baseline';
    DECLARE @otroEmisor NVARCHAR(400) = N'http://otro.localhost:19090/realms/otro';

    -- Fixtures: A y B activos, C inactivo
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoId, @numeroIdentificacion = 917000001,
        @primerApellido = N'Uno', @segundoApellido = N'IdExt', @primerNombre = N'QA', @segundoNombre = N'A',
        @correo = N'idext.a.qa017@test.local', @password = N'HashBackend_QaIdExt1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 51901, 'TEST FAILED: fixture usuario A.', 1;
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoId, @numeroIdentificacion = 917000002,
        @primerApellido = N'Dos', @segundoApellido = N'IdExt', @primerNombre = N'QA', @segundoNombre = N'B',
        @correo = N'idext.b.qa017@test.local', @password = N'HashBackend_QaIdExt1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 51902, 'TEST FAILED: fixture usuario B.', 1;
    SET @corr = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoId, @numeroIdentificacion = 917000003,
        @primerApellido = N'Tres', @segundoApellido = N'IdExt', @primerNombre = N'QA', @segundoNombre = N'C',
        @correo = N'idext.c.qa017@test.local', @password = N'HashBackend_QaIdExt1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 51903, 'TEST FAILED: fixture usuario C.', 1;

    DECLARE @idA UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'idext.a.qa017@test.local');
    DECLARE @idB UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'idext.b.qa017@test.local');
    DECLARE @idC UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'idext.c.qa017@test.local');
    UPDATE dbo.Usuario SET estado = 0 WHERE id = @idC;

    -- T-01 primera vinculacion valida
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idUsuario = @idA,
        @correoVinculacion = N'idext.a.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 1)
        THROW 51910, 'TEST FAILED: T-01 la primera vinculacion debia registrarse.', 1;
    IF (SELECT COUNT(*) FROM dbo.uv_identidad_externa WHERE idUsuario = @idA AND sujeto = N'sub-a' AND estaVigenteIdentidad = 1) <> 1
        THROW 51911, 'TEST FAILED: T-01 el vinculo debia quedar vigente en la vista.', 1;
    DELETE FROM #vinculo;

    -- T-02 repeticion idempotente (incluso con otro correo: el correo ya no es el identificador)
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idUsuario = @idA,
        @correoVinculacion = N'otro.correo@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 1)
        THROW 51912, 'TEST FAILED: T-02 la repeticion debia ser idempotente.', 1;
    IF (SELECT COUNT(*) FROM dbo.IdentidadExterna WHERE usuario = @idA) <> 1
        THROW 51913, 'TEST FAILED: T-02 no debia duplicarse el vinculo.', 1;
    DELETE FROM #vinculo;

    -- T-03 usuario inexistente
    DECLARE @idInexistente UNIQUEIDENTIFIER = NEWID();
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-x', @idUsuario = @idInexistente,
        @correoVinculacion = N'x@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51914, 'TEST FAILED: T-03 un usuario inexistente debia rechazarse.', 1;
    DELETE FROM #vinculo;

    -- T-04 usuario inactivo
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-c', @idUsuario = @idC,
        @correoVinculacion = N'idext.c.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51915, 'TEST FAILED: T-04 un usuario inactivo debia rechazarse.', 1;
    IF EXISTS (SELECT 1 FROM dbo.IdentidadExterna WHERE usuario = @idC)
        THROW 51916, 'TEST FAILED: T-04 no debia quedar vinculo para el usuario inactivo.', 1;
    DELETE FROM #vinculo;

    -- T-05 parametros vacios
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = N' ', @sujeto = N'sub-b', @idUsuario = @idB,
        @correoVinculacion = N'idext.b.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51917, 'TEST FAILED: T-05 un emisor vacio debia rechazarse.', 1;
    DELETE FROM #vinculo;

    -- T-06 dos identidades intentando ocupar la misma cuenta (mismo emisor)
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a-intruso', @idUsuario = @idA,
        @correoVinculacion = N'idext.a.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51918, 'TEST FAILED: T-06 una segunda identidad sobre la misma cuenta debia rechazarse.', 1;
    DELETE FROM #vinculo;

    -- T-06b otro emisor distinto SI puede vincular a la misma cuenta
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @otroEmisor, @sujeto = N'sub-a', @idUsuario = @idA,
        @correoVinculacion = N'idext.a.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 1)
        THROW 51919, 'TEST FAILED: T-06b otro emisor debia poder vincularse.', 1;
    DELETE FROM #vinculo;

    -- T-07 una identidad intentando ocupar dos cuentas
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idUsuario = @idB,
        @correoVinculacion = N'idext.b.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51920, 'TEST FAILED: T-07 una identidad ya vinculada a A no debia ocupar B.', 1;
    IF EXISTS (SELECT 1 FROM dbo.IdentidadExterna WHERE usuario = @idB)
        THROW 51921, 'TEST FAILED: T-07 B no debia quedar vinculada.', 1;
    DELETE FROM #vinculo;

    -- T-08 revocacion
    SET @corr = NEWID();
    INSERT INTO #revoca EXEC dbo.usp_revocar_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #revoca WHERE estadoResultado = 1)
        THROW 51922, 'TEST FAILED: T-08 la revocacion debia tener exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_identidad_externa WHERE emisor = @emisor AND sujeto = N'sub-a' AND estaVigenteIdentidad = 0 AND fechaRevocacion IS NOT NULL)
        THROW 51923, 'TEST FAILED: T-08 el vinculo debia quedar revocado y conservado.', 1;
    DELETE FROM #revoca;

    -- T-09 revocacion idempotente
    SET @corr = NEWID();
    INSERT INTO #revoca EXEC dbo.usp_revocar_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #revoca WHERE estadoResultado = 1)
        THROW 51924, 'TEST FAILED: T-09 revocar de nuevo debia ser idempotente.', 1;
    DELETE FROM #revoca;

    -- T-10 una identidad revocada no se reutiliza (ni en su cuenta ni en otra)
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idUsuario = @idB,
        @correoVinculacion = N'idext.b.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51925, 'TEST FAILED: T-10 una identidad revocada no debia reasignarse a B.', 1;
    DELETE FROM #vinculo;
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a', @idUsuario = @idA,
        @correoVinculacion = N'idext.a.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 0)
        THROW 51926, 'TEST FAILED: T-10 una identidad revocada no debia reactivarse sin decision explicita.', 1;
    DELETE FROM #vinculo;

    -- T-11 revocar un vinculo inexistente
    SET @corr = NEWID();
    INSERT INTO #revoca EXEC dbo.usp_revocar_identidad_externa @emisor = @emisor, @sujeto = N'no-existe', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #revoca WHERE estadoResultado = 0)
        THROW 51927, 'TEST FAILED: T-11 revocar un vinculo inexistente debia rechazarse.', 1;
    DELETE FROM #revoca;

    -- T-12 tras revocar, la cuenta A puede recibir una NUEVA identidad del mismo emisor
    SET @corr = NEWID();
    INSERT INTO #vinculo EXEC dbo.usp_vincular_identidad_externa @emisor = @emisor, @sujeto = N'sub-a-nueva', @idUsuario = @idA,
        @correoVinculacion = N'idext.a.qa017@test.local', @idCorrelacion = @corr;
    IF NOT EXISTS (SELECT 1 FROM #vinculo WHERE estadoResultado = 1)
        THROW 51928, 'TEST FAILED: T-12 tras revocar, A debia poder recibir una nueva identidad.', 1;
    DELETE FROM #vinculo;

    DROP TABLE #vinculo;
    DROP TABLE #revoca;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    DECLARE @mensajePrueba NVARCHAR(2048) = ERROR_MESSAGE();
    THROW 51999, @mensajePrueba, 1;
END CATCH

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo LIKE N'idext.%.qa017@test.local')
    THROW 51998, 'TEST FAILED: identidad externa dejo datos permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 51997, 'TEST FAILED: identidad externa dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:EXTERNAL_IDENTITY_LINK';
PRINT 'TEST_PASS:EXTERNAL_IDENTITY_CONFLICTS';
PRINT 'TEST_PASS:EXTERNAL_IDENTITY_REVOCATION';
PRINT 'TEST END: test_sec_baseline_identidad_externa';
GO
