USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_facultad (HU116)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);
IF @idInstitucion IS NULL SET @idInstitucion = (SELECT TOP 1 id FROM dbo.Institucion);

DECLARE @idDecano UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);
IF @idDecano IS NULL SET @idDecano = (SELECT TOP 1 id FROM dbo.Decano);

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER = (
    SELECT TOP 1 idUsuario
    FROM dbo.uv_administrador
    WHERE estaActivoAdministrador = 1
    ORDER BY idUsuario
);

IF @idInstitucion IS NULL THROW 51500, 'TEST FAILED: Fixture uv_institucion no disponible.', 1;
IF @idDecano IS NULL THROW 51501, 'TEST FAILED: Fixture uv_decano no disponible.', 1;
IF @idUsuarioEjecutor IS NULL THROW 51506, 'TEST FAILED: Fixture administrador activo no disponible.', 1;

BEGIN TRANSACTION;
BEGIN TRY

    CREATE TABLE #facultadResultado (
        idCorrelacion           UNIQUEIDENTIFIER,
        mensajeUsuarioResultado NVARCHAR(4000),
        mensajeTecnicoResultado NVARCHAR(4000),
        estadoResultado         BIT
    );

    -- =========================================================================
    -- CASO 1: El ejecutor es obligatorio y la ausencia falla cerrada.
    -- =========================================================================
    PRINT '-> Caso 1: Validando rechazo ante ejecutor nulo...';
    DECLARE @corr1 UNIQUEIDENTIFIER = NEWID();
    DECLARE @idSinEjecutor UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSinEjecutor NVARCHAR(50) = CONCAT(N'Facultad sin ejecutor ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8));
    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = @idSinEjecutor,
        @nombre = @nombreSinEjecutor,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr1,
        @idUsuarioEjecutor = NULL;

    IF NOT EXISTS (
        SELECT 1
        FROM #facultadResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corr1
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%'
    )
        THROW 51502, 'TEST FAILED: usp_crear_facultad no rechazo ejecutor nulo con GEN_002.', 1;

    PRINT 'TEST_PASS:HU116_FACULTY_CREATE_EXECUTOR_REQUIRED';

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 2: Validación de obligatoriedad (Nombre nulo o en blanco)
    -- =========================================================================
    PRINT '-> Caso 2: Validando rechazo ante nombre en blanco...';
    DECLARE @corr2 UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = NULL,
        @nombre = N'   ',
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr2,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #facultadResultado WHERE estadoResultado = 0 AND idCorrelacion = @corr2)
        THROW 51507, 'TEST FAILED: usp_crear_facultad no rechazo nombre en blanco.', 1;

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 2: Happy Path - Inserción exitosa de nueva facultad
    -- =========================================================================
    PRINT '-> Caso 2: Validando insercion exitosa de nueva facultad...';
    DECLARE @nombreValido NVARCHAR(50) = CONCAT(N'Facultad QA ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8));
    DECLARE @idGenerado UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr3 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = @idGenerado,
        @nombre = @nombreValido,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr3,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #facultadResultado WHERE estadoResultado = 1 AND idCorrelacion = @corr3)
        THROW 51503, 'TEST FAILED: usp_crear_facultad no retorno estadoResultado = 1 para facultad valida.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Facultad WHERE id = @idGenerado AND nombre = @nombreValido AND estado = 1)
        THROW 51504, 'TEST FAILED: No se encontro el registro persistido en dbo.Facultad.', 1;

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 3: Validación de Unicidad (Nombre duplicado en mayusculas/minusculas)
    -- =========================================================================
    PRINT '-> Caso 3: Validando rechazo ante nombre duplicado...';
    DECLARE @nombreDuplicado NVARCHAR(50) = LOWER(@nombreValido);
    DECLARE @corr4 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = NULL,
        @nombre = @nombreDuplicado,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr4,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #facultadResultado WHERE estadoResultado = 0 AND idCorrelacion = @corr4)
        THROW 51505, 'TEST FAILED: usp_crear_facultad permitio duplicar nombre de facultad.', 1;

    PRINT 'TEST_PASS:HU116_FACULTY_CREATE_SUCCESS';

    DROP TABLE #facultadResultado;

    -- Revertimos la transaccion para mantener la idempotencia absoluta del test
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado exitosamente. Cero residuos en la BD.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;

IF @@TRANCOUNT <> 0
    THROW 51599, 'TEST FAILED: test_usp_crear_facultad dejo transacciones abiertas.', 1;

PRINT '==================================================';
PRINT 'TEST PASS: test_usp_crear_facultad (HU116 OK)';
PRINT '==================================================';
GO
