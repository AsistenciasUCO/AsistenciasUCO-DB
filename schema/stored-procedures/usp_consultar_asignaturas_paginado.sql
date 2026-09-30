USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asignaturas_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda y catálogo paginado de asignaturas curriculares consumiendo uv_asignatura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asignaturas_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @codigo                  NVARCHAR(50)     = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroCodigo NVARCHAR(50) = IIF(TRIM(@codigo) IS NULL OR TRIM(@codigo) = '', NULL, TRIM(@codigo));
    DECLARE @filtroActivo BIT = @estaActivo;

    -- Control de diagnóstico
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 3: Consulta optimizada de asignaturas
        SELECT
            a.id,
            a.codigo,
            a.nombre,
            a.credito,
            a.idArea,
            a.nombreArea,
            a.idComponente,
            a.nombreComponente,
            a.inp,
            a.nombrePrograma,
            a.codigoSemestre,
            a.estaActivaAsignatura,
            COUNT(1) OVER() AS totalRegistros
        FROM dbo.uv_asignatura a
        WHERE (@filtroActivo IS NULL OR a.estaActivaAsignatura = @filtroActivo)
          AND (@filtroCodigo IS NULL OR a.codigo = @filtroCodigo)
          AND (
              @filtroTextoNormalizado IS NULL
              OR a.nombre LIKE @filtroTextoNormalizado
              OR a.nombrePrograma LIKE @filtroTextoNormalizado
          )
        ORDER BY a.nombre ASC, a.codigo ASC, a.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
