USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_area (HU151/HU152)';
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
    DECLARE @c UNIQUEIDENTIFIER;
    DECLARE @sufijo NVARCHAR(8) = SUBSTRING(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 1, 8);
    DECLARE @cod NVARCHAR(3) = SUBSTRING(@sufijo, 1, 3);
    DECLARE @nom NVARCHAR(50) = CONCAT(N'QA Area ', @sufijo);
    DECLARE @codPad NVARCHAR(5) = CONCAT(N' ', LOWER(@cod), N' ');
    DECLARE @nomMalo NVARCHAR(50) = CONCAT(N'QA Malo ', @sufijo), @nomOtro NVARCHAR(50) = CONCAT(N'QA Otro ', @sufijo);
    DECLARE @nomUpper NVARCHAR(50) = UPPER(@nom), @nomRbac NVARCHAR(50) = CONCAT(N'QA Rbac ', @sufijo), @nomNulo NVARCHAR(50) = CONCAT(N'QA Nulo ', @sufijo);

    -- DB-01/02: alta valida; el codigo en minuscula y con espacios se normaliza
    PRINT '-> DB-01/02: alta y normalizacion';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = @codPad, @nombre = @nom, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52710, 'TEST FAILED DB-01: no retorno exito al crear.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_area WHERE codigo = UPPER(@cod) AND nombre = @nom AND estaActivaArea = 1)
        THROW 52711, 'TEST FAILED DB-01/02: no persistio activo con codigo normalizado.', 1;
    TRUNCATE TABLE #r;

    -- DB-03: codigo invalido (corto, largo, simbolos, nulo, vacio)
    PRINT '-> DB-03: codigo invalido';
    DECLARE @malos TABLE (v NVARCHAR(20));
    INSERT INTO @malos VALUES (N'AB'), (N'ABCD'), (N'A#C'), (NULL), (N'');
    DECLARE @v NVARCHAR(20);
    DECLARE cur CURSOR LOCAL FOR SELECT v FROM @malos;
    OPEN cur;
    FETCH NEXT FROM cur INTO @v;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @c = NEWID();
        INSERT INTO #r EXEC dbo.usp_crear_area @codigo = @v, @nombre = @nomMalo, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
        IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
            THROW 52712, 'TEST FAILED DB-03: acepto un codigo invalido.', 1;
        TRUNCATE TABLE #r;
        FETCH NEXT FROM cur INTO @v;
    END
    CLOSE cur;
    DEALLOCATE cur;

    -- DB-04: nombre invalido
    PRINT '-> DB-04: nombre invalido';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ1', @nombre = N'ab', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52713, 'TEST FAILED DB-04: acepto nombre de 2 caracteres.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ1', @nombre = N'012345678901234567890123456789012345678901234567890', @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52714, 'TEST FAILED DB-04: acepto nombre de 51 caracteres.', 1;
    TRUNCATE TABLE #r;

    -- DB-05: codigo duplicado
    PRINT '-> DB-05: codigo duplicado';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = @cod, @nombre = @nomOtro, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ARE_002|%')
        THROW 52715, 'TEST FAILED DB-05: acepto codigo duplicado.', 1;
    TRUNCATE TABLE #r;

    -- DB-06: nombre duplicado con otra capitalizacion
    PRINT '-> DB-06: nombre duplicado';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ2', @nombre = @nomUpper, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=ARE_002|%')
        THROW 52716, 'TEST FAILED DB-06: acepto nombre duplicado.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_area WHERE codigo = N'ZZ2')
        THROW 52717, 'TEST FAILED DB-06: persistio pese al rechazo.', 1;
    TRUNCATE TABLE #r;

    -- DB-16: RBAC
    PRINT '-> DB-16: RBAC';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ3', @nombre = @nomRbac, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52718, 'TEST FAILED DB-16: permitio ejecutor sin perfil ADMINISTRADOR.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_area WHERE codigo = N'ZZ3')
        THROW 52719, 'TEST FAILED DB-16: persistio pese al rechazo RBAC.', 1;
    TRUNCATE TABLE #r;

    -- DB-17: ejecutor y correlacion nulos
    PRINT '-> DB-17: ejecutor y correlacion nulos';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ4', @nombre = @nomNulo, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52720, 'TEST FAILED DB-17: acepto ejecutor nulo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_area @codigo = N'ZZ4', @nombre = @nomNulo, @idCorrelacion = NULL, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52721, 'TEST FAILED DB-17: no rechazo correlacion nula con CORR_001.', 1;
    TRUNCATE TABLE #r;

    -- DB-18: el SP no altera el nivel de transaccion del llamador
    IF @@TRANCOUNT <> 1 THROW 52722, 'TEST FAILED DB-18: el SP altero el nivel de transaccion del llamador.', 1;

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
    THROW 52799, 'TEST FAILED: test_usp_crear_area dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_crear_area (HU151/HU152 OK)';
PRINT '==================================================';
GO
