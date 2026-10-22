USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_cambiar_estado_tipo_programa (HU154)';
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
IF @idEjecutor IS NULL THROW 52601, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idNoAdmin IS NULL THROW 52602, 'TEST FAILED: Fixture usuario no administrador no disponible.', 1;

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
    DECLARE @id1 UNIQUEIDENTIFIER = NEWID(), @idFantasma UNIQUEIDENTIFIER = NEWID();
    DECLARE @nomEstado NVARCHAR(50) = CONCAT(N'QA Estado ', @sufijo), @codEstado NVARCHAR(3) = SUBSTRING(@sufijo, 1, 3);
    INSERT INTO dbo.TipoPrograma (id, nombre, estado, codigo) VALUES (@id1, @nomEstado, 1, @codEstado);

    PRINT '-> DB-12: inactivar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52650, 'TEST FAILED DB-12: no retorno exito al inactivar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @id1 AND estaActivoTipoPrograma = 0)
        THROW 52651, 'TEST FAILED DB-12: estado no persistido.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> DB-14: idempotencia';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52652, 'TEST FAILED DB-14: repetir el estado no es idempotente.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> DB-13: activar';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND idCorrelacion = @c)
        THROW 52653, 'TEST FAILED DB-13: no retorno exito al activar.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @id1 AND estaActivoTipoPrograma = 1)
        THROW 52654, 'TEST FAILED DB-13: estado activo no persistido.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> DB-15: inexistente y estado nulo';
    SET @c = NEWID();
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @idFantasma, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=TPR_001|%')
        THROW 52655, 'TEST FAILED DB-15: no rechazo inexistente con TPR_001.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52656, 'TEST FAILED DB-15: acepto estado nulo.', 1;
    TRUNCATE TABLE #r;

    PRINT '-> DB-16/17: RBAC, ejecutor y correlacion nulos';
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @idNoAdmin;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%')
        THROW 52657, 'TEST FAILED DB-16: permitio ejecutor sin perfil ADMINISTRADOR.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_programa WHERE id = @id1 AND estaActivoTipoPrograma = 1)
        THROW 52658, 'TEST FAILED DB-16: cambio el estado pese al rechazo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%')
        THROW 52659, 'TEST FAILED DB-17: acepto ejecutor nulo.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_cambiar_estado_tipo_programa @id = @id1, @estaActivo = 0, @idCorrelacion = NULL, @idUsuarioEjecutor = @idEjecutor;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=CORR_001|%')
        THROW 52660, 'TEST FAILED DB-17: no rechazo correlacion nula.', 1;
    TRUNCATE TABLE #r;

    -- DB-18: no altera el nivel de transaccion del llamador
    IF @@TRANCOUNT <> 1 THROW 52661, 'TEST FAILED DB-18: el SP altero el nivel de transaccion del llamador.', 1;

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
    THROW 52699, 'TEST FAILED: test_usp_cambiar_estado_tipo_programa dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_cambiar_estado_tipo_programa (HU154 OK)';
PRINT '==================================================';
GO
