USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_estudiantes_grupo_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Listar de forma paginada y filtrada los estudiantes matriculados en un grupo
--   académico específico, incluyendo su estado de matrícula e indicadores acumulados
--   de inasistencia. Consume uv_estudiante_grupo, uv_estudiante_identidad, uv_usuario,
--   uv_asistencia y uv_detalle_asistencia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_estudiantes_grupo_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @filtroTexto             NVARCHAR(100)    = NULL,
    @idEstadoEstudiante      UNIQUEIDENTIFIER = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones y normalizaciones previas obligatorias (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Normalización de paginación
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroTextoNormalizado NVARCHAR(102) = IIF(TRIM(@filtroTexto) IS NULL OR TRIM(@filtroTexto) = '', NULL, CONCAT('%', TRIM(@filtroTexto), '%'));
    DECLARE @filtroEstadoId UNIQUEIDENTIFIER = @idEstadoEstudiante;

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

        -- Paso 3: Validación obligatoria de idGrupo
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

        -- Paso 4: Consulta optimizada de alumnos del grupo con cálculo acumulado de inasistencias
        ;WITH ResumenInasistencias AS (
            SELECT
                a.idEstudianteGrupo,
                totalFallas = COUNT(CASE WHEN da.asistio = 0 AND da.codigoRazonCausa = 'SJC' THEN 1 END),
                totalJustificadas = COUNT(CASE WHEN da.codigoRazonCausa = 'EX' THEN 1 END),
                totalAsistencias = COUNT(CASE WHEN da.asistio = 1 THEN 1 END),
                totalRegistrosAsistencia = COUNT(da.id)
            FROM dbo.uv_asistencia a
            INNER JOIN dbo.uv_detalle_asistencia da ON a.id = da.idAsistencia
            GROUP BY a.idEstudianteGrupo
        )
        SELECT
            eg.id                               AS idEstudianteGrupo,
            eg.idEstudiante                     AS idEstudiante,
            u.id                                AS idUsuario,
            u.idTipoIdentificacion              AS tipoIdentificacionId,
            u.numeroIdentificacion              AS numeroIdentificacion,
            u.primerApellido                    AS primerApellido,
            u.segundoApellido                   AS segundoApellido,
            u.primerNombre                      AS primerNombre,
            u.segundoNombre                     AS segundoNombre,
            u.nombreCompleto                    AS nombreCompleto,
            u.correo                            AS correo,
            eg.idEstadoEstudiante               AS idEstadoEstudiante,
            eg.codigoEstadoEstudiante           AS codigoEstadoEstudiante,
            eg.nombreEstadoEstudiante           AS nombreEstadoEstudiante,
            u.estaActivoUsuario                 AS estaActivoUsuario,
            IIF(ri.totalFallas IS NULL, 0, ri.totalFallas)                     AS totalFallas,
            IIF(ri.totalJustificadas IS NULL, 0, ri.totalJustificadas)         AS totalJustificadas,
            IIF(ri.totalAsistencias IS NULL, 0, ri.totalAsistencias)           AS totalAsistencias,
            IIF(ri.totalRegistrosAsistencia IS NULL, 0, ri.totalRegistrosAsistencia) AS totalRegistrosAsistencia,
            COUNT(1) OVER()                     AS totalRegistros
        FROM dbo.uv_estudiante_grupo eg
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        LEFT JOIN ResumenInasistencias ri ON eg.id = ri.idEstudianteGrupo
        WHERE eg.idGrupo = @idGrupoDefecto
          AND (@filtroEstadoId IS NULL OR eg.idEstadoEstudiante = @filtroEstadoId)
          AND (
              @filtroTextoNormalizado IS NULL
              OR u.numeroIdentificacion LIKE @filtroTextoNormalizado
              OR u.nombreCompleto LIKE @filtroTextoNormalizado
              OR u.correo LIKE @filtroTextoNormalizado
          )
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, eg.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO
