USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_docentes_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51320, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoDocentes') IS NOT NULL DROP TABLE #resultadoDocentes;
CREATE TABLE #resultadoDocentes (
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
    INSERT INTO #resultadoDocentes
    EXEC dbo.usp_consultar_docentes_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_DOCENTES_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 2: Búsqueda por documento específico de docente existente
    -- ============================================================================
    DECLARE @docDocente NVARCHAR(50);
    SELECT TOP 1 @docDocente = numeroIdentificacion FROM dbo.uv_docente_identidad;

    IF @docDocente IS NOT NULL
    BEGIN
        TRUNCATE TABLE #resultadoDocentes;

        INSERT INTO #resultadoDocentes
        EXEC dbo.usp_consultar_docentes_paginado
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @numeroIdentificacion = @docDocente,
            @numeroPagina = 1,
            @tamanoPagina = 10;

        IF NOT EXISTS (SELECT 1 FROM #resultadoDocentes WHERE numeroIdentificacion = @docDocente)
            THROW 51321, 'TEST FAILED: la búsqueda por documento existente no devolvió el docente.', 1;

        PRINT 'TEST_PASS:USP_CONSULTAR_DOCENTES_PAGINADO_BY_DOCUMENT';
    END;

    -- ============================================================================
    -- PRUEBA 3: Filtro por texto inexistente debe retornar 0 filas
    -- ============================================================================
    TRUNCATE TABLE #resultadoDocentes;

    INSERT INTO #resultadoDocentes
    EXEC dbo.usp_consultar_docentes_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @filtroTexto = N'TextoTotalmenteInexistenteXYZ12345',
        @numeroPagina = 1,
        @tamanoPagina = 10;

    IF EXISTS (SELECT 1 FROM #resultadoDocentes)
        THROW 51322, 'TEST FAILED: filtro por texto inexistente no debio retornar docentes.', 1;

    PRINT 'TEST_PASS:USP_CONSULTAR_DOCENTES_PAGINADO_NO_MATCH';

    -- ============================================================================
    -- PRUEBA 4: Consulta individual por ID (usp_consultar_docente_por_id)
    -- ============================================================================
    DECLARE @idDocenteExistente UNIQUEIDENTIFIER;
    SELECT TOP 1 @idDocenteExistente = id FROM dbo.uv_docente_identidad;

    IF @idDocenteExistente IS NOT NULL
    BEGIN
        IF OBJECT_ID('tempdb..#resultadoDocenteIndividual') IS NOT NULL DROP TABLE #resultadoDocenteIndividual;
        CREATE TABLE #resultadoDocenteIndividual (
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

        INSERT INTO #resultadoDocenteIndividual
        EXEC dbo.usp_consultar_docente_por_id
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @idDocente = @idDocenteExistente;

        IF NOT EXISTS (SELECT 1 FROM #resultadoDocenteIndividual WHERE id = @idDocenteExistente)
            THROW 51323, 'TEST FAILED: usp_consultar_docente_por_id no retorno el docente esperado.', 1;

        PRINT 'TEST_PASS:USP_CONSULTAR_DOCENTE_POR_ID_SUCCESS';
        DROP TABLE #resultadoDocenteIndividual;
    END;

    DROP TABLE #resultadoDocentes;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoDocentes') IS NOT NULL DROP TABLE #resultadoDocentes;
    IF OBJECT_ID('tempdb..#resultadoDocenteIndividual') IS NOT NULL DROP TABLE #resultadoDocenteIndividual;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

-- ============================================================================
-- PRUEBA 5: Validación defensiva - Usuario ejecutor nulo
-- ============================================================================
DECLARE @errorCapturado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_docentes_paginado
        @idUsuarioEjecutor = NULL,
        @idCorrelacion = '11111111-1111-1111-1111-111111111111';
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51324, 'TEST FAILED: usuario ejecutor NULL debio lanzar error.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_DOCENTES_PAGINADO_INVALID_USER';

PRINT 'TEST END: test_usp_consultar_docentes_paginado';
GO
