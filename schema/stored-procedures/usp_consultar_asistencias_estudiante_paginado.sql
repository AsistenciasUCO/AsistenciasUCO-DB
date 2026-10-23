USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_estudiante_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Consultar el historial y auditoría de asistencia de un estudiante en un grupo
--   académico específico consumiendo uv_auth_sesion, uv_asistencia y uv_detalle_asistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_estudiante_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

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

        -- Paso 3: Validación obligatoria de idEstudiante e idGrupo
        IF @estadoResultado = 1 AND (@idEstudianteDefecto IS NULL OR @idEstudianteDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Estudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
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

        -- Paso 5: Consulta de asistencias históricas del estudiante
        SELECT
            da.id                       AS idDetalleAsistencia,
            da.codigo                   AS codigoDetalleAsistencia,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.numeroSemana             AS numeroSemana,
            se.fechaHoraInicio          AS fechaHoraInicio,
            se.fechaHoraFin             AS fechaHoraFin,
            da.asistio                  AS asistio,
            da.idRazonCausa             AS idRazonCausa,
            da.codigoRazonCausa         AS codigoRazonCausa,
            da.nombreRazonCausa         AS nombreRazonCausa,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_auth_sesion se
        INNER JOIN dbo.uv_asistencia asi ON se.id = asi.idSesion
        INNER JOIN dbo.uv_detalle_asistencia da ON asi.id = da.idAsistencia
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        WHERE eg.idEstudiante = @idEstudianteDefecto
          AND eg.idGrupo = @idGrupoDefecto
        ORDER BY se.fechaHoraInicio ASC, se.numero ASC, da.id ASC
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
