USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_grupos_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51300, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoGrupos') IS NOT NULL DROP TABLE #resultadoGrupos;
CREATE TABLE #resultadoGrupos (
    id UNIQUEIDENTIFIER,
    codigo INT,
    nombre NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER,
    nombreAsignatura NVARCHAR(100),
    idDocente UNIQUEIDENTIFIER,
    capacidadMaximaPermitida INT,
    estudiantesActivos INT,
    cuposDisponibles INT,
    grupoEstaHablitado BIT,
    fechaInicioPeriodoAcademico DATETIME2,
    fechaFinPeriodoAcademico DATETIME2,
    totalRegistros INT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- ============================================================================
    -- PRUEBA 1: Ejecución exitosa (Happy Path) con usuario ejecutor válido
    -- ============================================================================
    INSERT INTO #resultadoGrupos
    EXEC dbo.usp_consultar_grupos_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 2: Validación de filtros y paginación
    -- ============================================================================
    TRUNCATE TABLE #resultadoGrupos;
    
    INSERT INTO #resultadoGrupos
    EXEC dbo.usp_consultar_grupos_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @filtroTexto = N'TextoInexistente99999XYZ',
        @numeroPagina = 1,
        @tamanoPagina = 5;

    IF EXISTS (SELECT 1 FROM #resultadoGrupos)
        THROW 51301, 'TEST FAILED: filtro por texto inexistente no debio retornar registros.', 1;

    PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_FILTER_AND_PAGINATION';

    DROP TABLE #resultadoGrupos;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoGrupos') IS NOT NULL DROP TABLE #resultadoGrupos;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

-- ============================================================================
-- PRUEBA 3: Validación defensiva - Usuario Ejecutor Nulo / Vacío debe fallar
-- ============================================================================
DECLARE @errorCapturado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_grupos_paginado
        @idUsuarioEjecutor = NULL,
        @idCorrelacion = '11111111-1111-1111-1111-111111111111';
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51302, 'TEST FAILED: usuario ejecutor NULL debio lanzar error VAL_001.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_INVALID_USER';

-- ============================================================================
-- PRUEBA 4: Limpieza y restauración del contexto de sesión
-- ============================================================================
DECLARE @contextoActual UNIQUEIDENTIFIER = CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'idUsuarioEjecutor'));
IF @contextoActual IS NOT NULL
    THROW 51303, 'TEST FAILED: el contexto de sesion no fue limpiado a NULL.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_CLEANUP';

IF @@TRANCOUNT <> 0 
    THROW 51304, 'TEST FAILED: transacciones quedaron abiertas.', 1;

PRINT 'TEST END: test_usp_consultar_grupos_paginado';
GO
