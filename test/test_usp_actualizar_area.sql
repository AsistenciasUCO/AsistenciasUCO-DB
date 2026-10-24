USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_actualizar_area (HU151/HU152)';
PRINT '==================================================';

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
IF @idEjecutor IS NULL THROW 52701, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idNoAdmin IS NULL THROW 52702, 'TEST FAILED: Fixture usuario no administrador no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #r (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );
    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 1, 8);

    DECLARE @id1 UNIQUEIDENTIFIER = NEWID(), @id2 UNIQUEIDENTIFIER = NEWID();
    DECLARE @cod1 NVARCHAR(3) = SUBSTRING(@sufijo, 1, 3);
    DECLARE @cod2 NVARCHAR(3) = SUBSTRING(@sufijo, 4, 3);
    DECLARE @nom2 NVARCHAR(50) = CONCAT(N'QA Dos ', @sufijo);
    DECLARE @nom2Upper NVARCHAR(50) = UPPER(@nom2), @idFantasma UNIQUEIDENTIFIER = NEWID();
    DECLARE @nom1 NVARCHAR(50) = CONCAT(N'QA Uno ', @sufijo);
    INSERT INTO dbo.Area (id, nombre, estado, codigo) VALUES (@id1, @nom1, 1, @cod1);
    INSERT INTO dbo.Area (id, nombre, estado, codigo) VALUES (@id2, @nom2, 1, @cod2);

    -- DB-07: renombrar; el codigo no cambia
    PRINT '-> DB-07: renombrar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id1, @nombre = N'  QA Renombrado  ', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52730, 'TEST FAILED DB-07: no retorno exito al renombrar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @id1 AND nombre = N'QA Renombrado' AND codigo = @cod1)
        THROW 52731, 'TEST FAILED DB-07: nombre no actualizado o codigo alterado.', 1;
    TRUNCATE TABLE #r;

    -- DB-08: mismo nombre propio (otra capitalizacion)
    PRINT '-> DB-08: mismo nombre propio';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id1, @nombre = N'qa renombrado', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52732, 'TEST FAILED DB-08: conflicto de unicidad contra si mismo.', 1;
    TRUNCATE TABLE #r;

    -- DB-09: nombre de otro registro
    PRINT '-> DB-09: nombre de otro registro';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id1, @nombre = @nom2Upper, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_003|%')
        THROW 52733, 'TEST FAILED DB-09: acepto nombre duplicado.', 1;
    TRUNCATE TABLE #r;

    -- DB-10: nombre invalido o nulo
    PRINT '-> DB-10: nombre invalido';
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id1, @nombre = N'ab', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52734, 'TEST FAILED DB-10: acepto nombre corto.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id1, @nombre = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52735, 'TEST FAILED DB-10: acepto nombre nulo.', 1;
    TRUNCATE TABLE #r;

    -- DB-11: inexistente
    PRINT '-> DB-11: inexistente';
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @idFantasma, @nombre = N'QA Fantasma', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ARE_001|%')
        THROW 52736, 'TEST FAILED DB-11: no rechazo tipo inexistente con ARE_001.', 1;
    TRUNCATE TABLE #r;

    -- DB-16/17: RBAC y correlacion nula
    PRINT '-> DB-16/17: RBAC y correlacion';
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id2, @nombre = N'QA Intruso', @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52737, 'TEST FAILED DB-16: permitio ejecutor sin perfil ADMINISTRADOR.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE id = @id2 AND nombre = @nom2)
        THROW 52738, 'TEST FAILED DB-16: modifico pese al rechazo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_area @id = @id2, @nombre = N'QA Corr', @idCorrelacion = NULL, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52739, 'TEST FAILED DB-17: no rechazo correlacion nula.', 1;
    TRUNCATE TABLE #r;

    -- DB-18: no altera el nivel de transaccion del llamador
    IF @@TRANCOUNT <> 1 THROW 52740, 'TEST FAILED DB-18: el SP altero el nivel de transaccion del llamador.', 1;

    DROP TABLE #r;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 52799, 'TEST FAILED: test_usp_actualizar_area dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_actualizar_area (HU151/HU152 OK)';
PRINT '==================================================';
GO
