USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_asistencia_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Bandeja institucional de solicitudes de justificación y revisión de asistencia
--   consumiendo uv_solicitud_revision_asistencia, uv_asistencia, uv_sesion,
--   uv_estudiante_grupo, uv_estudiante_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_asistencia_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER = NULL,
    @idEstudiante            UNIQUEIDENTIFIER = NULL,
    @idEstado                UNIQUEIDENTIFIER = NULL,
    @fechaDesde              DATE             = NULL,
    @fechaHasta              DATE             = NULL,
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
    DECLARE @filtroGrupoId UNIQUEIDENTIFIER = @idGrupo;
    DECLARE @filtroEstudianteId UNIQUEIDENTIFIER = @idEstudiante;
    DECLARE @filtroEstadoId UNIQUEIDENTIFIER = @idEstado;
    DECLARE @filtroFechaDesde DATE = @fechaDesde;
    DECLARE @filtroFechaHasta DATE = @fechaHasta;

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

        -- Paso 3: Consulta sobre vistas base sin manipulación de SESSION_CONTEXT
        SELECT
            sr.id                       AS idSolicitud,
            sr.nombre                   AS radicadoSolicitud,
            sr.fecha                    AS fechaRadicacion,
            sr.idEstado                 AS idEstado,
            sr.nombreEstado             AS nombreEstado,
            sr.justificacionSolicitud   AS justificacionSolicitud,
            sr.justificacionRespuesta   AS justificacionRespuesta,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.idGrupo                  AS idGrupo,
            eg.id                       AS idEstudianteGrupo,
            ei.id                       AS idEstudiante,
            u.id                        AS idUsuario,
            u.numeroIdentificacion      AS numeroIdentificacion,
            u.nombreCompleto            AS nombreCompletoEstudiante,
            u.correo                    AS correoEstudiante,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_solicitud_revision_asistencia sr
        INNER JOIN dbo.uv_asistencia asi ON sr.idAsistencia = asi.id
        INNER JOIN dbo.uv_sesion se ON asi.idSesion = se.id
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        WHERE (@filtroGrupoId IS NULL OR se.idGrupo = @filtroGrupoId)
          AND (@filtroEstudianteId IS NULL OR ei.id = @filtroEstudianteId)
          AND (@filtroEstadoId IS NULL OR sr.idEstado = @filtroEstadoId)
          AND (@filtroFechaDesde IS NULL OR sr.fecha >= @filtroFechaDesde)
          AND (@filtroFechaHasta IS NULL OR sr.fecha <= @filtroFechaHasta)
        ORDER BY sr.fecha DESC, sr.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
