USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_ingreso_estudiante  (HU053/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- "Mis solicitudes de ingreso": SOLO las del estudiante autenticado (Estudiante.usuario = ejecutor), la mas reciente
-- primero, con grupo, asignatura, docente, estado y motivo de rechazo. Paginacion acotada (1..100).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_estudiante]
(
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

    SELECT
        idSolicitud        = s.id,
        idGrupo            = g.id,
        codigoGrupo        = g.codigo,
        nombreGrupo        = g.nombre,
        idAsignatura       = asg.id,
        nombreAsignatura   = asg.nombre,
        nombreDocente      = CAST(CONCAT_WS(N' ',
                                 NULLIF(TRIM(ud.primerNombre), N''),
                                 NULLIF(TRIM(ud.primerApellido), N''),
                                 NULLIF(TRIM(ud.segundoApellido), N'')) AS NVARCHAR(400)),
        codigoEstado       = CAST(est.codigo AS CHAR(1)),
        nombreEstado       = est.nombre,
        fechaSolicitudUtc  = s.fechaSolicitudUtc,
        fechaResolucionUtc = s.fechaResolucionUtc,
        motivoRechazo      = s.motivoRechazo,
        totalRegistros     = COUNT(*) OVER()
    FROM dbo.SolicitudIngresoGrupo s
    INNER JOIN dbo.Estudiante estu ON estu.id = s.estudiante
    INNER JOIN dbo.Estado est      ON est.id = s.estado
    INNER JOIN dbo.Grupo g         ON g.id = s.grupo
    INNER JOIN dbo.Asignatura asg  ON asg.id = g.asignatura
    INNER JOIN dbo.Docente d       ON d.id = g.docente
    INNER JOIN dbo.Usuario ud      ON ud.id = d.usuario
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY s.fechaSolicitudUtc DESC, s.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
