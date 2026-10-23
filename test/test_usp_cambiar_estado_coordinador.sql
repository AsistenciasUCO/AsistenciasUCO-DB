USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU122: usp_cambiar_estado_coordinador (CONTRACT HU121-HU122 §2.5, congelado 2026-10-22).
-- Cubre T-122-01..05, T-122-07, T-122-08 y la parte DB de CA-05/CA-06.
-- T-122-06 (persona con dos roles) queda pendiente de WI-B/IAM-001 (ufn_usuario_tiene_roles_activos).
PRINT 'TEST START: test_usp_cambiar_estado_coordinador';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idProgramaF1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa WHERE estaActivoPrograma = 1);
DECLARE @idFacultadF1 UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa WHERE id = @idProgramaF1);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @idDecanoF1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);
DECLARE @idUsuarioD1 UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE id = @idDecanoF1);
DECLARE @idTipoPrograma UNIQUEIDENTIFIER = (SELECT TOP 1 tipoDePrograma FROM dbo.Programa WHERE id = @idProgramaF1);
DECLARE @idC1 UNIQUEIDENTIFIER = (SELECT TOP 1 idCoordinador FROM dbo.uv_programa WHERE id = @idProgramaF1);

IF @tipoId IS NULL THROW 51500, 'TEST FAILED: no existe fixture CC.', 1;
IF @idProgramaF1 IS NULL THROW 51501, 'TEST FAILED: no existe un programa activo fixture.', 1;
IF @idFacultadF1 IS NULL THROW 51502, 'TEST FAILED: el programa fixture no expone facultad.', 1;
IF @idUsuarioD1 IS NULL THROW 51503, 'TEST FAILED: no existe el usuario del decano fixture.', 1;
IF @idC1 IS NULL THROW 51504, 'TEST FAILED: el programa fixture no tiene coordinador (C1).', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #crea (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    CREATE TABLE #estado (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                          estadoResultado BIT, idUsuario UNIQUEIDENTIFIER, personaSinRolesActivos BIT);

    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;

    -- Fixture F2 con su decano D2 (rol de otra facultad)
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoId, @numeroIdentificacion = 915000001,
        @primerApellido = N'Decano', @segundoApellido = N'Dos', @primerNombre = N'QA', @segundoNombre = N'F2',
        @correo = N'decano.f2.qa122@test.local', @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 51505, 'TEST FAILED: no se pudo crear el usuario del decano F2.', 1;
    DECLARE @idUsuarioD2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'decano.f2.qa122@test.local');
    DECLARE @idDecanoF2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idFacultadF2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@idDecanoF2, @idUsuarioD2);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@idFacultadF2, N'Facultad QA F2 HU122', @idInstitucion, @idDecanoF2, 1);

    -- Coordinadores: C2 (F1 sin programa), C3 (F2 sin programa), C4 (F1 con programa inactivo)
    DECLARE @idC2 UNIQUEIDENTIFIER = NEWID(), @idC3 UNIQUEIDENTIFIER = NEWID(), @idC4 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idC2, @numeroIdentificacion = 915000002,
        @primerNombre = N'Coord', @segundoNombre = N'Dos', @primerApellido = N'QA', @segundoApellido = N'F1',
        @correo = N'coord.c2.qa122@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF1,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idC3, @numeroIdentificacion = 915000003,
        @primerNombre = N'Coord', @segundoNombre = N'Tres', @primerApellido = N'QA', @segundoApellido = N'F2',
        @correo = N'coord.c3.qa122@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF2,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD2;
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idC4, @numeroIdentificacion = 915000004,
        @primerNombre = N'Coord', @segundoNombre = N'Cuatro', @primerApellido = N'QA', @segundoApellido = N'F1',
        @correo = N'coord.c4.qa122@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF1,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF (SELECT COUNT(*) FROM #crea WHERE estadoResultado = 1) <> 3 THROW 51506, 'TEST FAILED: fixture de coordinadores no se creo.', 1;
    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado)
    VALUES (NEWID(), @idFacultadF1, @idTipoPrograma, N'Programa Inactivo QA HU122', @idC4, 0);

    DECLARE @msgNoExiste NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'Coordinador', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_001');
    DECLARE @msgProgramaActivo NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'COO_001');
    DECLARE @msgSinEjecutor NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'idUsuarioEjecutor', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_002');
    DECLARE @idUsuarioC2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_coordinador WHERE id = @idC2);

    -- T-122-01: desactivar un coordinador sin programa (CA-03)
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC2, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 1 AND idUsuario = @idUsuarioC2 AND personaSinRolesActivos = 1)
        THROW 51510, 'TEST FAILED T-122-01: desactivar C2 no retorno exito con idUsuario y personaSinRolesActivos=1.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC2 AND estado = 0)
        THROW 51511, 'TEST FAILED T-122-01: Coordinador.estado no paso a 0.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND estaActivoCoordinador = 0)
        THROW 51512, 'TEST FAILED T-122-01: uv_coordinador sigue mostrando activo a C2.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @idUsuarioC2 AND estado = 0)
        THROW 51513, 'TEST FAILED T-122-01: Usuario.estado no paso a 0 al quedar sin roles activos.', 1;

    -- T-122-05: idempotencia (desactivar otra vez)
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC2, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 1)
        THROW 51514, 'TEST FAILED T-122-05: desactivar un coordinador ya inactivo no fue idempotente.', 1;

    -- T-122-04: reactivar (CA-04)
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC2, @estaActivo = 1, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 1 AND idUsuario = @idUsuarioC2)
        THROW 51515, 'TEST FAILED T-122-04: reactivar C2 no retorno exito.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC2 AND estado = 1)
        OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @idUsuarioC2 AND estado = 1)
        OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND estaActivoCoordinador = 1)
        THROW 51516, 'TEST FAILED T-122-04: la reactivacion no restauro rol, usuario y vista.', 1;

    -- T-122-02 / CA-05 / D3: desactivar un coordinador con programa activo
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC1, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgProgramaActivo)
        THROW 51517, 'TEST FAILED T-122-02: desactivar con programa activo no retorno COO_001.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC1 AND estado = 1)
        THROW 51518, 'TEST FAILED T-122-02: el rechazo COO_001 modifico el estado de C1.', 1;
    IF @@TRANCOUNT <> 1 THROW 51519, 'TEST FAILED T-122-02/T-121-11: el rechazo rompio la transaccion externa del llamador.', 1;

    -- T-122-03 / D3: con programa inactivo si se puede desactivar
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC4, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 1)
        THROW 51520, 'TEST FAILED T-122-03: desactivar con programa inactivo no retorno exito.', 1;

    -- T-122-07 / CA-06: coordinador de otra facultad (no revela su existencia)
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC3, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgNoExiste)
        THROW 51521, 'TEST FAILED T-122-07: coordinador de otra facultad no retorno GEN_001.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC3 AND estado = 1)
        THROW 51522, 'TEST FAILED T-122-07: se modifico un coordinador de otra facultad.', 1;

    -- T-122-07b: el decano F1 no puede usar @idFacultad de F2 (titularidad)
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC3, @estaActivo = 0, @idFacultad = @idFacultadF2,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 0)
        OR NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC3 AND estado = 1)
        THROW 51523, 'TEST FAILED T-122-07b: titularidad sobre la facultad ajena no fue rechazada.', 1;

    -- T-122-08: RBAC (ejecutor con perfil COORDINADOR) y ejecutor NULL
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC2, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioC2;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 0)
        OR NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idC2 AND estado = 1)
        THROW 51524, 'TEST FAILED T-122-08: un ejecutor COORDINADOR no fue rechazado por RBAC.', 1;
    DELETE FROM #estado;
    INSERT INTO #estado EXEC dbo.usp_cambiar_estado_coordinador @idCoordinador = @idC2, @estaActivo = 0, @idFacultad = @idFacultadF1,
        @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #estado WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgSinEjecutor)
        THROW 51525, 'TEST FAILED T-122-08: ejecutor NULL no retorno GEN_002.', 1;

    DROP TABLE #crea;
    DROP TABLE #estado;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo LIKE N'%.qa122@test.local')
    THROW 51526, 'TEST FAILED: cambiar estado de coordinador dejo datos permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 51527, 'TEST FAILED: cambiar estado de coordinador dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:COORDINATOR_STATE_TOGGLE';
PRINT 'TEST_PASS:COORDINATOR_STATE_ACTIVE_PROGRAM_BLOCK';
PRINT 'TEST_PASS:COORDINATOR_STATE_SCOPE';
PRINT 'TEST_PASS:COORDINATOR_STATE_RBAC';
PRINT 'TEST END: test_usp_cambiar_estado_coordinador';
GO
