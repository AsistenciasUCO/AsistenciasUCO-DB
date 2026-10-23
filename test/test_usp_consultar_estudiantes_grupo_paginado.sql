USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

PRINT 'TEST START: test_usp_consultar_estudiantes_grupo_paginado';

DECLARE @idUsuarioEjecutor UNIQUEIDENTIFIER;
SELECT TOP 1 @idUsuarioEjecutor = id FROM dbo.uv_usuario WHERE estaActivoUsuario = 1;

IF @idUsuarioEjecutor IS NULL
    THROW 51310, 'TEST FAILED: no existe usuario activo para fixture.', 1;

DECLARE @idGrupoExistente UNIQUEIDENTIFIER;
SELECT TOP 1 @idGrupoExistente = idGrupo FROM dbo.uv_estudiante_grupo;

IF @idGrupoExistente IS NULL
    SELECT TOP 1 @idGrupoExistente = id FROM dbo.uv_grupo;

IF @idGrupoExistente IS NULL
    THROW 51311, 'TEST FAILED: no existe grupo para fixture.', 1;

DECLARE @idCorrelacion UNIQUEIDENTIFIER = NEWID();

IF OBJECT_ID('tempdb..#resultadoAlumnosGrupo') IS NOT NULL DROP TABLE #resultadoAlumnosGrupo;
CREATE TABLE #resultadoAlumnosGrupo (
    idEstudianteGrupo UNIQUEIDENTIFIER,
    idEstudiante UNIQUEIDENTIFIER,
    idUsuario UNIQUEIDENTIFIER,
    tipoIdentificacionId UNIQUEIDENTIFIER,
    numeroIdentificacion NVARCHAR(50),
    primerApellido NVARCHAR(50),
    segundoApellido NVARCHAR(50),
    primerNombre NVARCHAR(50),
    segundoNombre NVARCHAR(50),
    nombreCompleto NVARCHAR(250),
    correo NVARCHAR(150),
    idEstadoEstudiante UNIQUEIDENTIFIER,
    codigoEstadoEstudiante VARCHAR(10),
    nombreEstadoEstudiante NVARCHAR(100),
    estaActivoUsuario BIT,
    totalFallas INT,
    totalJustificadas INT,
    totalAsistencias INT,
    totalRegistrosAsistencia INT,
    totalRegistros INT
);

BEGIN TRANSACTION;
BEGIN TRY
    -- ============================================================================
    -- PRUEBA 1: Ejecución exitosa (Happy Path)
    -- ============================================================================
    INSERT INTO #resultadoAlumnosGrupo
    EXEC dbo.usp_consultar_estudiantes_grupo_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @idGrupo = @idGrupoExistente,
        @numeroPagina = 1,
        @tamanoPagina = 10;

    PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_GRUPO_PAGINADO_SUCCESS';

    -- ============================================================================
    -- PRUEBA 2: Filtro por texto inexistente debe retornar 0 filas
    -- ============================================================================
    TRUNCATE TABLE #resultadoAlumnosGrupo;

    INSERT INTO #resultadoAlumnosGrupo
    EXEC dbo.usp_consultar_estudiantes_grupo_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @idGrupo = @idGrupoExistente,
        @filtroTexto = N'TextoTotalmenteInexistenteXYZ12345',
        @numeroPagina = 1,
        @tamanoPagina = 10;

    IF EXISTS (SELECT 1 FROM #resultadoAlumnosGrupo)
        THROW 51312, 'TEST FAILED: filtro por texto inexistente no debio retornar registros.', 1;

    PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_GRUPO_PAGINADO_NO_MATCH';

    DROP TABLE #resultadoAlumnosGrupo;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#resultadoAlumnosGrupo') IS NOT NULL DROP TABLE #resultadoAlumnosGrupo;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

ROLLBACK TRANSACTION;

-- ============================================================================
-- PRUEBA 3: Validación defensiva - Grupo nulo o vacío
-- ============================================================================
DECLARE @errorCapturado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_estudiantes_grupo_paginado
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @idGrupo = NULL;
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51313, 'TEST FAILED: idGrupo NULL debio lanzar error.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_GRUPO_PAGINADO_INVALID_GROUP';

-- ============================================================================
-- PRUEBA 4: Validación defensiva - Usuario ejecutor nulo
-- ============================================================================
SET @errorCapturado = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_estudiantes_grupo_paginado
        @idUsuarioEjecutor = NULL,
        @idCorrelacion = @idCorrelacion,
        @idGrupo = @idGrupoExistente;
END TRY
BEGIN CATCH
    SET @errorCapturado = 1;
END CATCH;

IF @errorCapturado = 0
    THROW 51314, 'TEST FAILED: usuario ejecutor NULL debio lanzar error.', 1;

PRINT 'TEST_PASS:USP_CONSULTAR_ESTUDIANTES_GRUPO_PAGINADO_INVALID_USER';

PRINT 'TEST END: test_usp_consultar_estudiantes_grupo_paginado';
GO
