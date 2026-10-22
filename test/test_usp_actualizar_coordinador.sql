USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU121: usp_actualizar_coordinador (CONTRACT HU121-HU122 §2.4, congelado 2026-10-22).
-- Cubre T-121-01..04, T-121-06..08 y T-121-11 (la transaccion externa sobrevive al rechazo).
-- T-121-10 (atomicidad con falla inyectada) se cubre en IT de backend: el SP no expone un punto de inyeccion.
PRINT 'TEST START: test_usp_actualizar_coordinador';

DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idProgramaF1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa WHERE estaActivoPrograma = 1);
DECLARE @idFacultadF1 UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa WHERE id = @idProgramaF1);
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion);
DECLARE @idDecanoF1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);
DECLARE @idUsuarioD1 UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE id = @idDecanoF1);

IF @tipoId IS NULL THROW 51600, 'TEST FAILED: no existe fixture CC.', 1;
IF @idFacultadF1 IS NULL THROW 51601, 'TEST FAILED: no existe facultad fixture F1.', 1;
IF @idUsuarioD1 IS NULL THROW 51602, 'TEST FAILED: no existe el usuario del decano fixture.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #crea (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    CREATE TABLE #act (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000),
                       estadoResultado BIT, idUsuario UNIQUEIDENTIFIER);

    DECLARE @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT;
    DECLARE @corr UNIQUEIDENTIFIER = NEWID();

    -- Fixture F2 con su decano D2
    EXEC dbo.usp_sincronizar_usuario_interno @idTipoIdIdentificacion = @tipoId, @numeroIdentificacion = 916000001,
        @primerApellido = N'Decano', @segundoApellido = N'Dos', @primerNombre = N'QA', @segundoNombre = N'F2',
        @correo = N'decano.f2.qa121@test.local', @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 1 THROW 51603, 'TEST FAILED: no se pudo crear el usuario del decano F2.', 1;
    DECLARE @idUsuarioD2 UNIQUEIDENTIFIER = (SELECT id FROM dbo.uv_usuario WHERE correo = N'decano.f2.qa121@test.local');
    DECLARE @idDecanoF2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idFacultadF2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) VALUES (@idDecanoF2, @idUsuarioD2);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@idFacultadF2, N'Facultad QA F2 HU121', @idInstitucion, @idDecanoF2, 1);

    -- C2 (F1) y C3 (F2), ambos sin programa
    DECLARE @idC2 UNIQUEIDENTIFIER = NEWID(), @idC3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idC2, @numeroIdentificacion = 916000002,
        @primerNombre = N'Coord', @segundoNombre = N'Dos', @primerApellido = N'QA', @segundoApellido = N'F1',
        @correo = N'coord.c2.qa121@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF1,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idC3, @numeroIdentificacion = 916000003,
        @primerNombre = N'Coord', @segundoNombre = N'Tres', @primerApellido = N'QA', @segundoApellido = N'F2',
        @correo = N'coord.c3.qa121@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF2,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD2;
    IF (SELECT COUNT(*) FROM #crea WHERE estadoResultado = 1) <> 2 THROW 51604, 'TEST FAILED: fixture de coordinadores no se creo.', 1;

    DECLARE @idUsuarioC2 UNIQUEIDENTIFIER = (SELECT idUsuario FROM dbo.uv_coordinador WHERE id = @idC2);
    DECLARE @numeroC2 INT = (SELECT numeroIdentificacion FROM dbo.uv_coordinador WHERE id = @idC2);
    DECLARE @msgActualizado NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'Coordinador', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_005');
    DECLARE @msgNoExiste NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'Coordinador', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_001');
    DECLARE @msgCorreoUsado NVARCHAR(4000) = (SELECT contenido FROM dbo.uv_mensaje_usuario WHERE codigo = 'VAL_006');
    DECLARE @msgSinEjecutor NVARCHAR(4000) = (SELECT dbo.ufn_reemplazar_plantilla_mensaje(contenido, N'idUsuarioEjecutor', NULL, NULL) FROM dbo.uv_mensaje_usuario WHERE codigo = 'GEN_002');

    -- T-121-01: edicion feliz (CA-01). El documento no cambia.
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Gomez', @segundoApellido = NULL,
        @correo = N'coord.c2.nuevo.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 1 AND idUsuario = @idUsuarioC2 AND mensajeUsuarioResultado = @msgActualizado)
        THROW 51610, 'TEST FAILED T-121-01: la edicion no retorno GEN_005 con idUsuario.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerNombre = N'Ana' AND segundoNombre = N'Maria'
                   AND primerApellido = N'Gomez' AND correo = N'coord.c2.nuevo.qa121@test.local' AND numeroIdentificacion = @numeroC2)
        THROW 51611, 'TEST FAILED T-121-01: uv_coordinador no refleja los datos nuevos o cambio el documento.', 1;

    -- T-121-03: el correo propio no cuenta como duplicado
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Ana', @segundoNombre = N'Maria', @primerApellido = N'Perez', @segundoApellido = NULL,
        @correo = N'coord.c2.nuevo.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 1)
        OR NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerApellido = N'Perez')
        THROW 51612, 'TEST FAILED T-121-03: reenviar el correo propio fue rechazado.', 1;

    -- T-121-02: correo de otro usuario (CA-02) y T-121-11: la transaccion externa sigue viva
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Cambio', @segundoNombre = NULL, @primerApellido = N'Rechazado', @segundoApellido = NULL,
        @correo = N'coord.c3.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgCorreoUsado)
        THROW 51613, 'TEST FAILED T-121-02: correo duplicado no retorno VAL_006.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerNombre = N'Cambio')
        THROW 51614, 'TEST FAILED T-121-02: el rechazo por correo duplicado modifico datos.', 1;
    IF @@TRANCOUNT <> 1 THROW 51615, 'TEST FAILED T-121-11: el rechazo rompio la transaccion externa del llamador.', 1;

    -- T-121-04: coordinador de otra facultad (no revela su existencia)
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC3,
        @primerNombre = N'Intruso', @segundoNombre = NULL, @primerApellido = N'F1', @segundoApellido = NULL,
        @correo = N'coord.c3.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgNoExiste)
        OR EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC3 AND primerNombre = N'Intruso')
        THROW 51616, 'TEST FAILED T-121-04: editar un coordinador de otra facultad no retorno GEN_001 o lo modifico.', 1;

    -- T-121-04b: titularidad sobre la facultad ajena
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC3,
        @primerNombre = N'Intruso', @segundoNombre = NULL, @primerApellido = N'F2', @segundoApellido = NULL,
        @correo = N'coord.c3.qa121@test.local', @idFacultad = @idFacultadF2, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC3 AND primerNombre = N'Intruso')
        THROW 51617, 'TEST FAILED T-121-04b: la titularidad sobre la facultad ajena no fue rechazada.', 1;

    -- T-121-06: RBAC (ejecutor con perfil COORDINADOR)
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Rbac', @segundoNombre = NULL, @primerApellido = N'Rechazado', @segundoApellido = NULL,
        @correo = N'coord.c2.nuevo.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioC2;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerNombre = N'Rbac')
        THROW 51618, 'TEST FAILED T-121-06: un ejecutor COORDINADOR no fue rechazado por RBAC.', 1;

    -- T-121-07: ejecutor NULL (sin GUID por defecto)
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Nulo', @segundoNombre = NULL, @primerApellido = N'Ejecutor', @segundoApellido = NULL,
        @correo = N'coord.c2.nuevo.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0 AND mensajeUsuarioResultado = @msgSinEjecutor)
        THROW 51619, 'TEST FAILED T-121-07: ejecutor NULL no retorno GEN_002.', 1;

    -- T-121-08: validacion de forma (nombre en blanco, correo sin formato)
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'   ', @segundoNombre = NULL, @primerApellido = N'Forma', @segundoApellido = NULL,
        @correo = N'coord.c2.nuevo.qa121@test.local', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerApellido = N'Forma')
        THROW 51620, 'TEST FAILED T-121-08: un nombre en blanco no fue rechazado.', 1;
    DELETE FROM #act;
    INSERT INTO #act EXEC dbo.usp_actualizar_coordinador @idCoordinador = @idC2,
        @primerNombre = N'Forma', @segundoNombre = NULL, @primerApellido = N'Correo', @segundoApellido = NULL,
        @correo = N'esto-no-es-un-correo', @idFacultad = @idFacultadF1, @idCorrelacion = @corr, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #act WHERE estadoResultado = 0)
        OR EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idC2 AND primerApellido = N'Correo')
        THROW 51621, 'TEST FAILED T-121-08: un correo sin formato no fue rechazado.', 1;

    DROP TABLE #crea;
    DROP TABLE #act;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo LIKE N'%.qa121@test.local')
    THROW 51622, 'TEST FAILED: actualizar coordinador dejo datos permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 51623, 'TEST FAILED: actualizar coordinador dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:COORDINATOR_UPDATE_SUCCESS';
PRINT 'TEST_PASS:COORDINATOR_UPDATE_EMAIL_CONFLICT';
PRINT 'TEST_PASS:COORDINATOR_UPDATE_SCOPE';
PRINT 'TEST_PASS:COORDINATOR_UPDATE_RBAC_AND_VALIDATION';
PRINT 'TEST END: test_usp_actualizar_coordinador';
GO
