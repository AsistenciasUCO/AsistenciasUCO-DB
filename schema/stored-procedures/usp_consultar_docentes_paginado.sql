USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_docentes_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, filtrado y paginación determinística de docentes institucionales
--   consumiendo las vistas base uv_docente_identidad, uv_usuario y uv_docente.
--   Permite filtrar opcionalmente por tipo/número de documento, nombres/correo,
--   facultad, programa y estado activo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_docentes_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idTipoIdentificacion    UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion    NVARCHAR(50)     = NULL,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @idFacultad              UNIQUEIDENTIFIER = NULL,
    @idPrograma              UNIQUEIDENTIFIER = NULL,
    @estaActivo              BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroDocNormalizado NVARCHAR(50) = IIF(TRIM(@numeroIdentificacion) IS NULL OR TRIM(@numeroIdentificacion) = '', NULL, TRIM(@numeroIdentificacion));
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroTipoId UNIQUEIDENTIFIER = @idTipoIdentificacion;
    DECLARE @filtroFacId UNIQUEIDENTIFIER = @idFacultad;
    DECLARE @filtroProgId UNIQUEIDENTIFIER = @idPrograma;
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

        -- Paso 3: Consulta optimizada de docentes sobre vistas base
        SELECT
            d.id                    AS id,
            u.id                    AS idUsuario,
            u.idTipoIdentificacion  AS tipoIdentificacionId,
            u.numeroIdentificacion  AS numeroIdentificacion,
            u.primerApellido        AS primerApellido,
            u.segundoApellido       AS segundoApellido,
            u.primerNombre          AS primerNombre,
            u.segundoNombre         AS segundoNombre,
            u.nombreCompleto        AS nombreCompleto,
            u.correo                AS correo,
            u.estaActivoUsuario     AS estaActivoUsuario,
            COUNT(1) OVER()         AS totalRegistros
        FROM dbo.uv_docente_identidad d
        INNER JOIN dbo.uv_usuario u ON d.idUsuario = u.id
        WHERE
            (@filtroTipoId IS NULL OR u.idTipoIdentificacion = @filtroTipoId)
            AND (@filtroDocNormalizado IS NULL OR u.numeroIdentificacion = @filtroDocNormalizado)
            AND (@filtroActivo IS NULL OR u.estaActivoUsuario = @filtroActivo)
            AND (
                @filtroTextoNormalizado IS NULL
                OR u.nombreCompleto LIKE @filtroTextoNormalizado
                OR u.correo LIKE @filtroTextoNormalizado
            )
            AND (
                @filtroFacId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_docente vd 
                    WHERE vd.id = d.id 
                      AND vd.idFacultad = @filtroFacId
                )
            )
            AND (
                @filtroProgId IS NULL
                OR EXISTS (
                    SELECT 1 
                    FROM dbo.uv_docente vd 
                    WHERE vd.id = d.id 
                      AND vd.idPrograma = @filtroProgId
                )
            )
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, d.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
