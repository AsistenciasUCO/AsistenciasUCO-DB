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
-- DB-GP-001C: SESSION_CONTEXT es estado de la conexion fisica. El SP captura el
-- contexto previo, aplica el contexto temporal y SIEMPRE restaura el previo
-- (tambien ante excepcion). Nunca deja NULL si antes existia un valor.
-- ============================================================================
DECLARE @adminUser UNIQUEIDENTIFIER, @otroUsuario UNIQUEIDENTIFIER;
SELECT TOP 1 @adminUser = a.usuario
FROM dbo.Administrador a INNER JOIN dbo.Usuario u ON u.id = a.usuario
WHERE u.estado = 1 ORDER BY a.id;
SELECT TOP 1 @otroUsuario = d.usuario
FROM dbo.Docente d INNER JOIN dbo.Usuario u ON u.id = d.usuario
WHERE u.estado = 1 ORDER BY d.id;
DECLARE @contextoPrevioA UNIQUEIDENTIFIER = 'A11CE000-0000-4000-8000-00000000000A'; -- TEST_ONLY: usuario sin rol
DECLARE @corrRestore UNIQUEIDENTIFIER = NEWID();

IF @adminUser IS NULL OR @otroUsuario IS NULL
    THROW 51305, 'TEST FAILED: fixture Administrador/Docente activo ausente para pruebas de restauracion de contexto.', 1;

IF OBJECT_ID('tempdb..#resultadoRestore') IS NOT NULL DROP TABLE #resultadoRestore;
CREATE TABLE #resultadoRestore (
    id UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
    idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT, cuposDisponibles INT,
    grupoEstaHablitado BIT, fechaInicioPeriodoAcademico DATETIME2, fechaFinPeriodoAcademico DATETIME2, totalRegistros INT
);

-- ============================================================================
-- PRUEBA 4 (Caso A): contexto previo NULL => despues sigue NULL
-- ============================================================================
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @adminUser, @idCorrelacion = @corrRestore;
IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
    THROW 51303, 'TEST FAILED: contexto previo NULL no fue restaurado a NULL.', 1;
PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_CLEANUP';

-- ============================================================================
-- PRUEBA 5 (Caso B): previo = Usuario A, SP con Usuario B => durante la consulta B, despues A
-- ============================================================================
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @adminUser;
DECLARE @gruposVisiblesAdmin INT = (SELECT COUNT(*) FROM dbo.uv_auth_grupo);
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @contextoPrevioA;
IF @gruposVisiblesAdmin = 0
    THROW 51306, 'TEST FAILED: fixture sin grupos visibles para el Administrador.', 1;

TRUNCATE TABLE #resultadoRestore;
INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @adminUser, @idCorrelacion = @corrRestore;
IF NOT EXISTS (SELECT 1 FROM #resultadoRestore WHERE totalRegistros = @gruposVisiblesAdmin)
    THROW 51307, 'TEST FAILED: durante la consulta no se aplico el contexto del usuario ejecutor (B).', 1;
IF ISNULL(TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER), '00000000-0000-0000-0000-000000000000') <> @contextoPrevioA
    THROW 51308, 'TEST FAILED: el contexto previo (A) no fue restaurado tras la consulta.', 1;
PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_PREVIOUS_VALUE_RESTORED';

-- ============================================================================
-- PRUEBA 6 (Caso C): el SP falla dentro del TRY => contexto previo restaurado antes del THROW
-- La falla se inyecta con un ALTER VIEW transaccional (revertido con ROLLBACK).
-- ============================================================================
DECLARE @defBase NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.uv_auth_grupo'));
DECLARE @defFalla NVARCHAR(MAX) = REPLACE(@defBase, N'ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL',
    N'ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL AND CONVERT(INT, N''boom-'' + g.nombre) = 1');
IF @defFalla = @defBase
    THROW 51309, 'TEST FAILED: no se pudo inyectar la falla de prueba en uv_auth_grupo.', 1;

DECLARE @spFallo BIT = 0;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @contextoPrevioA;
BEGIN TRANSACTION;
BEGIN TRY
    EXEC sys.sp_executesql @defFalla;
    TRUNCATE TABLE #resultadoRestore;
    INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @adminUser, @idCorrelacion = @corrRestore;
END TRY
BEGIN CATCH
    SET @spFallo = 1;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

IF @spFallo = 0
    THROW 51310, 'TEST FAILED: la falla inyectada no llego al SP (prueba no concluyente).', 1;
IF ISNULL(TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER), '00000000-0000-0000-0000-000000000000') <> @contextoPrevioA
    THROW 51311, 'TEST FAILED: el contexto previo no fue restaurado tras la excepcion del SP.', 1;
IF OBJECT_DEFINITION(OBJECT_ID('dbo.uv_auth_grupo')) <> @defBase
    THROW 51312, 'TEST FAILED: la vista uv_auth_grupo no volvio a su definicion original.', 1;
PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_RESTORED_ON_EXCEPTION';

-- ============================================================================
-- PRUEBA 7 (Caso D): sin fuga de contexto entre ejecuciones sucesivas
-- ============================================================================
DECLARE @fugas INT = 0;
EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @adminUser, @idCorrelacion = @corrRestore;
IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL SET @fugas += 1;

INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @otroUsuario, @idCorrelacion = @corrRestore;
IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL SET @fugas += 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @contextoPrevioA;
INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @adminUser, @idCorrelacion = @corrRestore;
IF ISNULL(TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER), '00000000-0000-0000-0000-000000000000') <> @contextoPrevioA SET @fugas += 1;
INSERT #resultadoRestore EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @otroUsuario, @idCorrelacion = @corrRestore;
IF ISNULL(TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER), '00000000-0000-0000-0000-000000000000') <> @contextoPrevioA SET @fugas += 1;

-- Un usuario invalido falla antes de tocar el contexto: A permanece.
BEGIN TRY
    EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = NULL, @idCorrelacion = @corrRestore;
END TRY
BEGIN CATCH
    SET @fugas += 0;
END CATCH;
IF ISNULL(TRY_CAST(SESSION_CONTEXT(N'idUsuarioEjecutor') AS UNIQUEIDENTIFIER), '00000000-0000-0000-0000-000000000000') <> @contextoPrevioA SET @fugas += 1;

EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = NULL;
DROP TABLE #resultadoRestore;
IF @fugas <> 0
    THROW 51313, 'TEST FAILED: hubo fuga de contexto entre ejecuciones sucesivas.', 1;
PRINT 'TEST_PASS:USP_CONSULTAR_GRUPOS_PAGINADO_NO_CONTEXT_LEAK';

IF @@TRANCOUNT <> 0 
    THROW 51304, 'TEST FAILED: transacciones quedaron abiertas.', 1;

PRINT 'TEST END: test_usp_consultar_grupos_paginado';
GO
