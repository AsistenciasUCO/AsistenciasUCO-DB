USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_cambiar_estado_facultad (HU111)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
DECLARE @idEjecutor UNIQUEIDENTIFIER = (
    SELECT TOP 1 idUsuario FROM dbo.uv_administrador WHERE estaActivoAdministrador = 1 ORDER BY idUsuario
);
DECLARE @idNoAdmin UNIQUEIDENTIFIER = (
    SELECT TOP 1 up.idUsuario
    FROM dbo.uv_usuario_perfil up
    WHERE up.estado = 1
      AND up.codigoPerfil <> 'AD'
      AND NOT EXISTS (
          SELECT 1 FROM dbo.uv_usuario_perfil a
          WHERE a.idUsuario = up.idUsuario AND a.codigoPerfil = 'AD' AND a.estado = 1
      )
    ORDER BY up.idUsuario
);

IF @idInstitucion IS NULL THROW 52500, 'TEST FAILED: Fixture uv_institucion no disponible.', 1;
IF @idEjecutor IS NULL THROW 52501, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idNoAdmin IS NULL THROW 52502, 'TEST FAILED: Fixture usuario no administrador no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    CREATE TABLE #usuariosLibres (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    INSERT INTO #usuariosLibres (id)
    SELECT TOP 2 u.id FROM dbo.Usuario u
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = u.id)
    ORDER BY u.id;
    IF (SELECT COUNT(*) FROM #usuariosLibres) < 2 THROW 52503, 'TEST FAILED: faltan usuarios libres para fixtures de decano.', 1;

    DECLARE @dec1 UNIQUEIDENTIFIER = NEWID(), @dec2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec1, id FROM #usuariosLibres WHERE n = 1;
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec2, id FROM #usuariosLibres WHERE n = 2;

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @f1 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f1, CONCAT(N'QA Estado Uno ', @sufijo), @idInstitucion, @dec1, 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f2, CONCAT(N'QA Estado Dos ', @sufijo), @idInstitucion, @dec2, 1);

    DECLARE @c UNIQUEIDENTIFIER;
    DECLARE @inexistente UNIQUEIDENTIFIER = NEWID();

    -- DB-13: inactivar facultad activa
    PRINT '-> DB-13: inactivar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f1, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52510, 'TEST FAILED DB-13: no retorno exito al inactivar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @f1 AND estaActivaFacultad = 0)
        THROW 52511, 'TEST FAILED DB-13: el estado no se persistio.', 1;
    PRINT 'TEST_PASS:HU111_FACULTY_DEACTIVATE';
    TRUNCATE TABLE #r;

    -- DB-20: la vista de decano refleja la inactivacion
    PRINT '-> DB-20: uv_decano refleja facultad inactiva';
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_decano WHERE id = @dec1 AND estaActivoDecano = 0)
        THROW 52512, 'TEST FAILED DB-20: uv_decano no marco inactivo al decano de una facultad inactiva.', 1;

    -- DB-15: idempotencia (repetir el mismo estado)
    PRINT '-> DB-15: idempotencia';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f1, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52513, 'TEST FAILED DB-15: repetir el mismo estado no es idempotente.', 1;
    TRUNCATE TABLE #r;

    -- DB-14: activar facultad inactiva
    PRINT '-> DB-14: activar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f1, @estaActiva = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52514, 'TEST FAILED DB-14: no retorno exito al activar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @f1 AND estaActivaFacultad = 1)
        THROW 52515, 'TEST FAILED DB-14: el estado activo no se persistio.', 1;
    PRINT 'TEST_PASS:HU111_FACULTY_ACTIVATE';
    TRUNCATE TABLE #r;

    -- DB-16: facultad inexistente
    PRINT '-> DB-16: facultad inexistente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @inexistente, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
        THROW 52516, 'TEST FAILED DB-16: no rechazo facultad inexistente con FAC_001.', 1;
    TRUNCATE TABLE #r;

    -- Estado deseado obligatorio
    PRINT '-> Estado deseado nulo';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f1, @estaActiva = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52517, 'TEST FAILED: acepto estado deseado nulo.', 1;
    TRUNCATE TABLE #r;

    -- DB-17: reactivar con decano que ya es titular de otra facultad activa
    PRINT '-> DB-17: reactivar con decano en conflicto';
    UPDATE dbo.Facultad SET estado = 0 WHERE id = @f1;
    UPDATE dbo.Facultad SET decano = @dec2 WHERE id = @f1;   -- fixture directo: ambas apuntan al mismo decano; F2 activa
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f1, @estaActiva = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_002|%')
        THROW 52518, 'TEST FAILED DB-17: reactivo una facultad cuyo decano ya titulariza otra activa.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND estado = 0)
        THROW 52519, 'TEST FAILED DB-17: cambio el estado pese al rechazo.', 1;
    TRUNCATE TABLE #r;

    -- DB-18: RBAC
    PRINT '-> DB-18: RBAC';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f2, @estaActiva = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52520, 'TEST FAILED DB-18: permitio ejecutor sin perfil ADMINISTRADOR.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f2 AND estado = 1)
        THROW 52521, 'TEST FAILED DB-18: cambio el estado pese al rechazo RBAC.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> Correlacion nula';
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_facultad @id = @f2, @estaActiva = 0, @idCorrelacion = NULL, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52522, 'TEST FAILED: no rechazo correlacion nula con CORR_001.', 1;
    TRUNCATE TABLE #r;

    -- DB-19: el SP no altera el nivel de transaccion del llamador
    IF @@TRANCOUNT <> 1 THROW 52523, 'TEST FAILED DB-19: el SP altero el nivel de transaccion del llamador.', 1;

    DROP TABLE #r;
    DROP TABLE #usuariosLibres;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 52599, 'TEST FAILED: test_usp_cambiar_estado_facultad dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_cambiar_estado_facultad (HU111 OK)';
PRINT '==================================================';
GO
