USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_ingreso_grupo_docente  (HU053/HU054/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Bandeja de solicitudes de ingreso de UN grupo para su DOCENTE TITULAR (otro ejecutor => 0 filas), en orden de
-- llegada (fechaSolicitudUtc). posicionEspera numera las solicitudes EN ESPERA por llegada (informativo: el docente
-- puede aceptar a cualquiera). capacidadGrupo/cuposDisponibles = capacidad - matriculas activas.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_grupo_docente]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH grupoTitular AS (
        SELECT g.id, g.cantidadEstudiantes AS capacidad,
               (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                WHERE eg.grupo = g.id AND ee.codigo = 'A') AS activos
        FROM dbo.Grupo g
        INNER JOIN dbo.Docente d ON d.id = g.docente
        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto
    ),
    solicitudes AS (
        SELECT s.id, s.estudiante, s.fechaSolicitudUtc, s.fechaResolucionUtc, s.motivoRechazo,
               est.codigo AS codigoEstado, est.nombre AS nombreEstado, gt.capacidad, gt.activos,
               posicionEspera = CASE WHEN est.codigo = 'E'
                                     THEN ROW_NUMBER() OVER (PARTITION BY CASE WHEN est.codigo = 'E' THEN 1 ELSE 0 END
                                                             ORDER BY s.fechaSolicitudUtc, s.id) END
        FROM dbo.SolicitudIngresoGrupo s
        INNER JOIN grupoTitular gt ON gt.id = s.grupo
        INNER JOIN dbo.Estado est ON est.id = s.estado
    )
    SELECT
        idSolicitud          = sol.id,
        idEstudiante         = estu.id,
        nombreEstudiante     = CAST(CONCAT_WS(N' ',
                                   NULLIF(TRIM(u.primerNombre), N''),
                                   NULLIF(TRIM(u.segundoNombre), N''),
                                   NULLIF(TRIM(u.primerApellido), N''),
                                   NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        numeroIdentificacion = u.numeroIdentificacion,
        codigoEstado         = CAST(sol.codigoEstado AS CHAR(1)),
        nombreEstado         = sol.nombreEstado,
        fechaSolicitudUtc    = sol.fechaSolicitudUtc,
        fechaResolucionUtc   = sol.fechaResolucionUtc,
        motivoRechazo        = sol.motivoRechazo,
        posicionEspera       = CAST(sol.posicionEspera AS INT),
        capacidadGrupo       = sol.capacidad,
        cuposDisponibles     = IIF(sol.capacidad - sol.activos < 0, 0, sol.capacidad - sol.activos),
        totalRegistros       = COUNT(*) OVER()
    FROM solicitudes sol
    INNER JOIN dbo.Estudiante estu ON estu.id = sol.estudiante
    INNER JOIN dbo.Usuario u       ON u.id = estu.usuario
    WHERE (@estadoFiltro IS NULL OR sol.codigoEstado = @estadoFiltro)
    ORDER BY sol.fechaSolicitudUtc ASC, sol.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
