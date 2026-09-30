USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_sesion_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Listar la planilla de asistencia detallada por estudiante para una sesión
--   específica consumiendo uv_auth_sesion, uv_asistencia, uv_detalle_asistencia,
--   uv_estudiante_grupo, uv_estudiante_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_sesion_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @idRazonCausa            UNIQUEIDENTIFIER = NULL,
    @asistio                 BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroRazonCausaId UNIQUEIDENTIFIER = @idRazonCausa;
    DECLARE @filtroAsistio BIT = @asistio;

    -- Control de diagnóstico y contexto
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

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

        -- Paso 3: Validación obligatoria de idSesion
        IF @estadoResultado = 1 AND (@idSesionDefecto IS NULL OR @idSesionDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Sesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Establecer identidad temporal en contexto
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta optimizada de asistencia de la sesión
        SELECT
            da.id                       AS idDetalleAsistencia,
            da.codigo                   AS codigoDetalleAsistencia,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.numeroSemana             AS numeroSemana,
            eg.id                       AS idEstudianteGrupo,
            ei.id                       AS idEstudiante,
            u.id                        AS idUsuario,
            u.numeroIdentificacion      AS numeroIdentificacion,
            u.primerApellido            AS primerApellido,
            u.segundoApellido           AS segundoApellido,
            u.primerNombre              AS primerNombre,
            u.segundoNombre             AS segundoNombre,
            u.nombreCompleto            AS nombreCompleto,
            da.asistio                  AS asistio,
            da.idRazonCausa             AS idRazonCausa,
            da.codigoRazonCausa         AS codigoRazonCausa,
            da.nombreRazonCausa         AS nombreRazonCausa,
            da.fechaHoraInicio          AS fechaHoraInicio,
            da.fechaHoraFin             AS fechaHoraFin,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_auth_sesion se
        INNER JOIN dbo.uv_asistencia asi ON se.id = asi.idSesion
        INNER JOIN dbo.uv_detalle_asistencia da ON asi.id = da.idAsistencia
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        WHERE se.id = @idSesionDefecto
          AND (@filtroRazonCausaId IS NULL OR da.idRazonCausa = @filtroRazonCausaId)
          AND (@filtroAsistio IS NULL OR da.asistio = @filtroAsistio)
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, da.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar contexto previo
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;

    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
