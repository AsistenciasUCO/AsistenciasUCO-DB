USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT '==================================================';
PRINT 'TEST START: test_usp_crear_facultad (HU116)';
PRINT '==================================================';

DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1);

DECLARE @idDecano UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER = (
    SELECT TOP 1 idUsuario
    FROM dbo.uv_administrador
    WHERE estaActivoAdministrador = 1
    ORDER BY idUsuario
);
DECLARE @idUsuarioNoAdministrador UNIQUEIDENTIFIER = (
    SELECT TOP 1 up.idUsuario
    FROM dbo.uv_usuario_perfil up
    WHERE up.estado = 1
      AND up.codigoPerfil <> 'AD'
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.uv_usuario_perfil adminProfile
          WHERE adminProfile.idUsuario = up.idUsuario
            AND adminProfile.codigoPerfil = 'AD'
            AND adminProfile.estado = 1
      )
    ORDER BY up.idUsuario
);

IF @idInstitucion IS NULL THROW 51500, 'TEST FAILED: Fixture uv_institucion no disponible.', 1;
IF @idDecano IS NULL THROW 51501, 'TEST FAILED: Fixture uv_decano no disponible.', 1;
IF @idUsuarioEjecutor IS NULL THROW 51506, 'TEST FAILED: Fixture administrador activo no disponible.', 1;
IF @idUsuarioNoAdministrador IS NULL THROW 51508, 'TEST FAILED: Fixture usuario activo no administrador no disponible.', 1;

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
    -- CASO 2: Un ejecutor sin perfil ADMINISTRADOR debe fallar cerrado.
    -- =========================================================================
    PRINT '-> Validando rechazo ante ejecutor sin perfil ADMINISTRADOR...';
    DECLARE @corrRbac UNIQUEIDENTIFIER = NEWID();
    DECLARE @idSinRbac UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSinRbac NVARCHAR(50) = CONCAT(N'Facultad sin rol AD ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8));
    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = @idSinRbac,
        @nombre = @nombreSinRbac,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corrRbac,
        @idUsuarioEjecutor = @idUsuarioNoAdministrador;

    IF NOT EXISTS (
        SELECT 1
        FROM #facultadResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corrRbac
          AND mensajeTecnicoResultado LIKE N'DBCODE=SEC_001|%'
    )
        THROW 51509, 'TEST FAILED: usp_crear_facultad permitio ejecutor sin perfil ADMINISTRADOR.', 1;

    PRINT 'TEST_PASS:HU116_FACULTY_CREATE_EXECUTOR_RBAC';

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 3: Validación de obligatoriedad (Nombre nulo o en blanco)
    -- =========================================================================
    PRINT '-> Caso 3: Validando rechazo ante nombre en blanco...';
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
    -- CASO 4: El decano es obligatorio.
    -- =========================================================================
    PRINT '-> Validando rechazo ante decano nulo...';
    DECLARE @corrDecano UNIQUEIDENTIFIER = NEWID();
    DECLARE @idSinDecano UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSinDecano NVARCHAR(50) = CONCAT(N'Facultad sin decano ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8));
    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = @idSinDecano,
        @nombre = @nombreSinDecano,
        @idInstitucion = @idInstitucion,
        @idDecano = NULL,
        @idCorrelacion = @corrDecano,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (
        SELECT 1
        FROM #facultadResultado
        WHERE estadoResultado = 0
          AND idCorrelacion = @corrDecano
          AND mensajeTecnicoResultado LIKE N'DBCODE=GEN_002|%'
    )
        THROW 51510, 'TEST FAILED: usp_crear_facultad permitio decano nulo.', 1;

    PRINT 'TEST_PASS:HU116_FACULTY_CREATE_DEAN_REQUIRED';

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 5: Happy Path - Inserción exitosa de nueva facultad
    -- =========================================================================
    PRINT '-> Caso 5: Validando insercion exitosa de nueva facultad...';
    DECLARE @nombreValido NVARCHAR(50) = CONCAT(N'Facultad QA ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8));
    DECLARE @idGenerado UNIQUEIDENTIFIER = NEWID();
    DECLARE @corr4 UNIQUEIDENTIFIER = NEWID();

    -- INSERT EXEC exige exactamente las cuatro columnas canónicas compatibles con JPA.
    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = @idGenerado,
        @nombre = @nombreValido,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr4,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #facultadResultado WHERE estadoResultado = 1 AND idCorrelacion = @corr4)
        THROW 51503, 'TEST FAILED: usp_crear_facultad no retorno estadoResultado = 1 para facultad valida.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.uv_facultad
        WHERE id = @idGenerado
          AND nombreFacultad = @nombreValido
          AND estaActivaFacultad = 1
    )
        THROW 51504, 'TEST FAILED: No se encontro el registro persistido en dbo.Facultad.', 1;

    TRUNCATE TABLE #facultadResultado;

    -- =========================================================================
    -- CASO 6: Validación de Unicidad (Nombre duplicado en mayusculas/minusculas)
    -- =========================================================================
    PRINT '-> Caso 6: Validando rechazo ante nombre duplicado...';
    DECLARE @nombreDuplicado NVARCHAR(50) = LOWER(@nombreValido);
    DECLARE @corr5 UNIQUEIDENTIFIER = NEWID();

    INSERT INTO #facultadResultado
    EXEC dbo.usp_crear_facultad
        @id = NULL,
        @nombre = @nombreDuplicado,
        @idInstitucion = @idInstitucion,
        @idDecano = @idDecano,
        @idCorrelacion = @corr5,
        @idUsuarioEjecutor = @idUsuarioEjecutor;

    IF NOT EXISTS (SELECT 1 FROM #facultadResultado WHERE estadoResultado = 0 AND idCorrelacion = @corr5)
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
