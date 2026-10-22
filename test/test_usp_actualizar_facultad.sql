USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_actualizar_facultad (HU110 + HU117)';
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

IF @idInstitucion IS NULL THROW 52000, 'TEST FAILED: Fixture uv_institucion no disponible.', 1;
IF @idEjecutor IS NULL THROW 52001, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idNoAdmin IS NULL THROW 52002, 'TEST FAILED: Fixture usuario no administrador no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- Fixtures transaccionales: 3 decanos nuevos y 2 facultades (F1 inactiva-capaz, F2 activa con otro decano).
    CREATE TABLE #usuariosLibres (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER);
    INSERT INTO #usuariosLibres (id)
    SELECT TOP 3 u.id FROM dbo.Usuario u
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Decano d WHERE d.usuario = u.id)
    ORDER BY u.id;
    IF (SELECT COUNT(*) FROM #usuariosLibres) < 3 THROW 52003, 'TEST FAILED: faltan usuarios libres para fixtures de decano.', 1;

    DECLARE @dec1 UNIQUEIDENTIFIER = NEWID(), @dec2 UNIQUEIDENTIFIER = NEWID(), @dec3 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec1, id FROM #usuariosLibres WHERE n = 1;
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec2, id FROM #usuariosLibres WHERE n = 2;
    INSERT INTO dbo.Decano (id, usuario) SELECT @dec3, id FROM #usuariosLibres WHERE n = 3;

    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8);
    DECLARE @nomF1 NVARCHAR(50) = CONCAT(N'QA Fac Uno ', @sufijo);
    DECLARE @nomF2 NVARCHAR(50) = CONCAT(N'QA Fac Dos ', @sufijo);
    DECLARE @f1 UNIQUEIDENTIFIER = NEWID(), @f2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f1, @nomF1, @idInstitucion, @dec1, 1);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES (@f2, @nomF2, @idInstitucion, @dec2, 1);

    DECLARE @c UNIQUEIDENTIFIER;
    DECLARE @inexistente UNIQUEIDENTIFIER = NEWID();
    DECLARE @nuevoNombre NVARCHAR(50) = CONCAT(N'QA Renombrada ', @sufijo);

    -- DB-01: renombrar con nombre valido
    PRINT '-> DB-01: renombrar facultad';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nuevoNombre, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52010, 'TEST FAILED DB-01: no retorno exito al renombrar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_facultad WHERE id = @f1 AND nombreFacultad = @nuevoNombre)
        THROW 52011, 'TEST FAILED DB-01: el nombre no se persistio.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND decano = @dec1)
        THROW 52012, 'TEST FAILED DB-01: el decano cambio sin solicitarlo.', 1;
    PRINT 'TEST_PASS:HU110_FACULTY_RENAME';
    TRUNCATE TABLE #r;

    -- DB-02: reasignar a decano libre
    PRINT '-> DB-02: reasignar decano libre';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = NULL, @idDecano = @dec3, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52020, 'TEST FAILED DB-02: no retorno exito al reasignar decano libre.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND decano = @dec3 AND nombre = @nuevoNombre)
        THROW 52021, 'TEST FAILED DB-02: decano no persistido o nombre alterado.', 1;
    PRINT 'TEST_PASS:HU117_FACULTY_REASSIGN_DEAN';
    TRUNCATE TABLE #r;

    -- DB-03: renombrar y reasignar en una llamada
    PRINT '-> DB-03: renombrar y reasignar a la vez';
    DECLARE @nombre3 NVARCHAR(50) = CONCAT(N'QA Ambos ', @sufijo);
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nombre3, @idDecano = @dec1, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52030, 'TEST FAILED DB-03: no retorno exito con ambos campos.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND decano = @dec1 AND nombre = @nombre3)
        THROW 52031, 'TEST FAILED DB-03: no se persistieron ambos campos.', 1;
    TRUNCATE TABLE #r;

    -- DB-04: nombre duplicado (otra facultad, distinto caso)
    PRINT '-> DB-04: nombre duplicado';
    DECLARE @dup NVARCHAR(50) = LOWER(@nomF2);
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @dup, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_003|%')
        THROW 52040, 'TEST FAILED DB-04: permitio nombre duplicado o no uso GEN_003.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND nombre = @nombre3)
        THROW 52041, 'TEST FAILED DB-04: modifico la facultad pese al rechazo.', 1;
    TRUNCATE TABLE #r;

    -- DB-05: conservar el propio nombre no choca consigo misma
    PRINT '-> DB-05: mismo nombre propio';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nombre3, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52050, 'TEST FAILED DB-05: rechazo el propio nombre de la facultad.', 1;
    TRUNCATE TABLE #r;

    -- DB-06: longitud invalida (2 y 51)
    PRINT '-> DB-06: longitud de nombre invalida';
    DECLARE @corto NVARCHAR(50) = N'ab';
    DECLARE @largo NVARCHAR(100) = REPLICATE(N'x', 51);
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @corto, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52060, 'TEST FAILED DB-06: acepto nombre de 2 caracteres.', 1;
    TRUNCATE TABLE #r;
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @largo, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52061, 'TEST FAILED DB-06: acepto nombre de 51 caracteres.', 1;
    TRUNCATE TABLE #r;

    -- DB-07: ni nombre ni decano
    PRINT '-> DB-07: sin campos a modificar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = NULL, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52070, 'TEST FAILED DB-07: acepto una actualizacion sin campos.', 1;
    TRUNCATE TABLE #r;

    -- DB-08: facultad inexistente
    PRINT '-> DB-08: facultad inexistente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @inexistente, @nombre = @nuevoNombre, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_001|%')
        THROW 52080, 'TEST FAILED DB-08: no rechazo facultad inexistente con FAC_001.', 1;
    TRUNCATE TABLE #r;

    -- DB-09: decano inexistente, decano anterior intacto
    PRINT '-> DB-09: decano inexistente';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = NULL, @idDecano = @inexistente, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=DEC_001|%')
        THROW 52090, 'TEST FAILED DB-09: no rechazo decano inexistente con DEC_001.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND decano = @dec1)
        THROW 52091, 'TEST FAILED DB-09: el decano anterior no quedo intacto.', 1;
    TRUNCATE TABLE #r;

    -- DB-10: decano titular de otra facultad activa
    PRINT '-> DB-10: decano ya titular de otra facultad activa';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = NULL, @idDecano = @dec2, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=FAC_002|%')
        THROW 52100, 'TEST FAILED DB-10: permitio decano titular de otra facultad activa o no uso FAC_002.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @f1 AND decano = @dec1)
        THROW 52101, 'TEST FAILED DB-10: modifico el decano pese al rechazo.', 1;
    TRUNCATE TABLE #r;

    -- DB-10b: mismo decano actual no cuenta como conflicto
    PRINT '-> DB-10b: reasignar al mismo decano actual';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = NULL, @idDecano = @dec1, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52102, 'TEST FAILED DB-10b: rechazo reasignar al decano que ya es titular de esta facultad.', 1;
    TRUNCATE TABLE #r;

    -- DB-11: ejecutor sin perfil ADMINISTRADOR
    PRINT '-> DB-11: RBAC';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nuevoNombre, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52110, 'TEST FAILED DB-11: permitio ejecutor sin perfil ADMINISTRADOR.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> DB-11b: ejecutor nulo';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nuevoNombre, @idDecano = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND idCorrelacion = @c AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52111, 'TEST FAILED DB-11b: permitio ejecutor nulo.', 1;
    TRUNCATE TABLE #r;

    -- DB-12: correlacion obligatoria (falla cerrada, igual que usp_crear_facultad)
    PRINT '-> DB-12: correlacion nula';
    INSERT INTO #r EXEC dbo.usp_actualizar_facultad @id = @f1, @nombre = @nuevoNombre, @idDecano = NULL, @idCorrelacion = NULL, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52120, 'TEST FAILED DB-12: no rechazo correlacion nula con CORR_001.', 1;
    TRUNCATE TABLE #r;

    -- DB-19: una falla dentro del interno no deja transacciones abiertas
    PRINT '-> DB-19: sin transacciones huerfanas';
    IF @@TRANCOUNT <> 1 THROW 52190, 'TEST FAILED DB-19: el SP altero el nivel de transaccion del llamador.', 1;

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
    THROW 52199, 'TEST FAILED: test_usp_actualizar_facultad dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_actualizar_facultad (HU110 + HU117 OK)';
PRINT '==================================================';
GO
