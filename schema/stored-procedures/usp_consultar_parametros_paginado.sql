USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_parametros_paginado (CULM-001 D.3, HU168, F-ADM-012; CONTRACT v2 §4.2)
--
-- Parametros activos legibles y agrupados para el administrador: etiqueta, descripcion, valor, unidad, rango, valores
-- permitidos, ultimo cambio y si son editables. @soloEditables = 1 (defecto) excluye los tecnicos y los de grupos protegidos;
-- 0 los incluye de solo lectura. Filtros: @grupo exacto y @texto (contiene, sobre grupo, clave, etiqueta y descripcion).
-- Orden: categoriaVisual, orden, clave. Pagina y tamano validados con PAGINACION/TAMANO_MAXIMO (PAG_001).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas. Las fallas de validacion
-- se propagan con THROW (VAL_001 / SEC_001 / PAG_001 / PRM_012). Solo perfil ADMINISTRADOR. [SUPUESTO-D-16]: con mas de una
-- Institucion activa falla con PRM_012 y sin filas (los parametros no tienen institucion).
-- SESSION_CONTEXT: lo fija el interno de validacion; se captura el previo y SIEMPRE se restaura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_parametros_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @grupo              VARCHAR(100)  = NULL,
    @texto              NVARCHAR(200) = NULL,
    @soloEditables      BIT           = 1
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @grupoFiltro             VARCHAR(100) = NULLIF(TRIM(@grupo), '');
    DECLARE @textoFiltro             NVARCHAR(200) = NULLIF(TRIM(@texto), '');
    DECLARE @soloEditablesFiltro     BIT = ISNULL(@soloEditables, 1);
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil ADMINISTRADOR y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: [SUPUESTO-D-16] una sola Institucion activa (PRM_012)
        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 3: Consulta y retorno de resultados
        SELECT
            v.id,
            v.grupo,
            v.clave,
            valor = CONVERT(NVARCHAR(4000), v.valor),
            valorDefecto = CONVERT(NVARCHAR(4000), v.valorDefecto),
            v.tipoDato,
            v.esEditable,
            v.valorMinimo,
            v.valorMaximo,
            v.valoresPermitidos,
            v.etiqueta,
            v.descripcion,
            v.unidad,
            v.categoriaVisual,
            v.orden,
            v.fechaModificacion,
            v.fechaUltimoCambioUtc,
            v.nombreUltimoActor,
            v.esGrupoProtegido,
            totalRegistros = COUNT(*) OVER()
        FROM dbo.uv_parametro_edicion v
        WHERE
            (@soloEditablesFiltro = 0 OR v.esEditable = 1)
            AND (@grupoFiltro IS NULL OR v.grupo = @grupoFiltro)
            AND (@textoFiltro IS NULL
                 OR CHARINDEX(@textoFiltro, v.grupo) > 0
                 OR CHARINDEX(@textoFiltro, v.clave) > 0
                 OR CHARINDEX(@textoFiltro, v.etiqueta) > 0
                 OR CHARINDEX(@textoFiltro, v.descripcion) > 0)
        ORDER BY v.categoriaVisual ASC, v.orden ASC, v.clave ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
