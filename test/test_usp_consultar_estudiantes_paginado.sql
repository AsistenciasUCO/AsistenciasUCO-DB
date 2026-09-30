USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_estudiantes_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51300, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoEstudiantes') IS NOT NULL DROP TABLE #resultadoEstudiantes;
CREATE TABLE #resultadoEstudiantes (
    id UNIQUEIDENTIFIER,
    idUsuario UNIQUEIDENTIFIER,
    tipoIdentificacionId UNIQUEIDENTIFIER,
    numeroIdentificacion NVARCHAR(50),
    primerApellido NVARCHAR(50),
    segundoApellido NVARCHAR(50),
    primerNombre NVARCHAR(50),
    segundoNombre NVARCHAR(50),
    nombreCompleto NVARCHAR(250),
    correo NVARCHAR(150),
    estaActivoUsuario BIT,
    totalRegistros INT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- ============================================================================
    -- PRUEBA 1: Ejecución exitosa (Happy Path) sin filtros - Paginación básica
    -- ============================================================================
    INSERT INTO #resultadoEstudiantes
    EXEC dbo.usp_consultar_estudiantes_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 2: Búsqueda por documento específico existente
    -- ============================================================================
    DECLARE @docExistente NVARCHAR(50);
    SELECT TOP 1 @docExistente = numeroIdentificacion FROM dbo.uv_estudiante_identidad;

    IF @docExistente IS NOT NULL
    BEGIN
        TRUNCATE TABLE #resultadoEstudiantes;

        INSERT INTO #resultadoEstudiantes
        EXEC dbo.usp_consultar_estudiantes_paginado
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @numeroIdentificacion = @docExistente,
            @numeroPagina = 1,
            @tamanoPagina = 10;

        IF NOT EXISTS (SELECT 1 FROM #resultadoEstudiantes WHERE numeroIdentificacion = @docExistente)
            THROW 51301, 'TEST FAILED: la búsqueda por documento existente no devolvió el registro esperado.', 1;

        PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_PAGINADO_BY_DOCUMENT';
    END;

    -- ============================================================================
    -- PRUEBA 3: Filtro por texto inexistente debe retornar 0 filas
    -- ============================================================================
    TRUNCATE TABLE #resultadoEstudiantes;

    INSERT INTO #resultadoEstudiantes
    EXEC dbo.usp_consultar_estudiantes_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @filtroTexto = N'TextoTotalmenteInexistenteXYZ12345',
        @numeroPagina = 1,
        @tamanoPagina = 10;

    IF EXISTS (SELECT 1 FROM #resultadoEstudiantes)
        THROW 51302, 'TEST FAILED: filtro por texto inexistente no debio retornar registros.', 1;

    PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_PAGINADO_NO_MATCH';

    -- ============================================================================
    -- PRUEBA 4: Consulta individual por ID (usp_consultar_estudiante_por_id)
    -- ============================================================================
    DECLARE @idEstudianteExistente UNIQUEIDENTIFIER;
    SELECT TOP 1 @idEstudianteExistente = id FROM dbo.uv_estudiante_identidad;

    IF @idEstudianteExistente IS NOT NULL
    BEGIN
        IF OBJECT_ID('tempdb..#resultadoEstudianteIndividual') IS NOT NULL DROP TABLE #resultadoEstudianteIndividual;
        CREATE TABLE #resultadoEstudianteIndividual (
            id UNIQUEIDENTIFIER,
            idUsuario UNIQUEIDENTIFIER,
            tipoIdentificacionId UNIQUEIDENTIFIER,
            numeroIdentificacion NVARCHAR(50),
            primerApellido NVARCHAR(50),
            segundoApellido NVARCHAR(50),
            primerNombre NVARCHAR(50),
            segundoNombre NVARCHAR(50),
            nombreCompleto NVARCHAR(250),
            correo NVARCHAR(150),
            estaActivoUsuario BIT
        );

        INSERT INTO #resultadoEstudianteIndividual
        EXEC dbo.usp_consultar_estudiante_por_id
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @idEstudiante = @idEstudianteExistente;

        IF NOT EXISTS (SELECT 1 FROM #resultadoEstudianteIndividual WHERE id = @idEstudianteExistente)
            THROW 51303, 'TEST FAILED: usp_consultar_estudiante_por_id no retorno el estudiante esperado.', 1;

        PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTE_POR_ID_SUCCESS';
        DROP TABLE #resultadoEstudianteIndividual;
    END;

    DROP TABLE #resultadoEstudiantes;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoEstudiantes') IS NOT NULL DROP TABLE #resultadoEstudiantes;
    IF OBJECT_ID('tempdb..#resultadoEstudianteIndividual') IS NOT NULL DROP TABLE #resultadoEstudianteIndividual;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

-- ============================================================================
-- PRUEBA 5: Validación defensiva - Usuario ejecutor nulo o inválido
-- ============================================================================
DECLARE @errorCapturado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_estudiantes_paginado
        @idUsuarioEjecutor = NULL,
        @idCorrelacion = '11111111-1111-1111-1111-111111111111';
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51304, 'TEST FAILED: usuario ejecutor NULL debio lanzar error.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_PAGINADO_INVALID_USER';

-- ============================================================================
-- PRUEBA 6: Validación defensiva - Correlación nula o vacía
-- ============================================================================
SET @errorCapturado = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_estudiantes_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = NULL;
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51305, 'TEST FAILED: correlacion NULL debio lanzar error.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_PAGINADO_INVALID_CORR';

PRINT 'TEST END: test_usp_consultar_estudiantes_paginado';
GO
