USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_grupos_paginado
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION        no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--   NOT_BACKEND_CONSUMED             ningun backend/API la consume
--   NOT_PART_OF_LB002_JPA_PILOT      el piloto JPA usa las vistas base congeladas, no uv_auth_*
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros). NO es un
-- MUTATION_COMMAND_RESULTSET: el resultset canonico de 4 columnas
-- (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
-- aplica solo a los SP de comando/mutacion del Golden Path, por eso este SP queda
-- excluido de esa regla en test/test_contract_closure.sql. Las fallas se propagan
-- con THROW (VAL_001 para usuario ejecutor invalido).
--
-- SESSION_CONTEXT es estado de la conexion fisica: este SP captura el contexto
-- previo, aplica el del usuario ejecutor solo durante la consulta y SIEMPRE
-- restaura el previo (en exito y ante excepcion).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_grupos_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @idAsignatura       UNIQUEIDENTIFIER = NULL,
    @filtroTexto        NVARCHAR(100)    = NULL,
    @numeroPagina       INT              = 1,
    @tamanoPagina       INT              = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1. Normalizacion de parametros con funciones de catalogo (sin valores quemados ni ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalizacion de paginacion protegida (minimo 1, maximo 100)
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Normalizacion de filtro de texto
    DECLARE @filtroNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));

    -- 2. Variables de diagnostico y validacion
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    -- Contexto de sesion previo de la conexion (valor original, sin conversion), para restaurarlo.
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        -- 3. Validacion obligatoria de identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- 4. Validacion obligatoria de usuario ejecutor (no nulo y no GUID vacio)
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

        -- 5. Establecer identidad temporal en el contexto de sesion para la vista securizada uv_auth_grupo
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        -- 6. Consulta optimizada y deterministica a la vista securizada
        SELECT
            g.id,
            g.codigo,
            g.nombre,
            g.idAsignatura,
            g.nombreAsignatura,
            g.idDocente,
            g.capacidadMaximaPermitida,
            g.estudiantesActivos,
            g.cuposDisponibles,
            g.grupoEstaHablitado,
            g.fechaInicioPeriodoAcademico,
            g.fechaFinPeriodoAcademico,
            COUNT(*) OVER() AS totalRegistros
        FROM dbo.uv_auth_grupo g
        WHERE
            (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
            AND (@idAsignatura IS NULL OR g.idAsignatura = @idAsignatura)
            AND (
                @filtroNormalizado IS NULL
                OR g.nombre LIKE @filtroNormalizado
                OR g.codigo LIKE @filtroNormalizado
                OR g.nombreAsignatura LIKE @filtroNormalizado
            )
        ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- 7. Restaurar el contexto previo de la conexion (no forzar NULL)
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;

    END TRY
    BEGIN CATCH
        -- Restaurar el contexto previo ante cualquier excepcion, antes de propagar el error
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
