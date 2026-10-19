USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_revision_docente  (LB-004D, R2)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (filas de datos + totalRegistros), paginado en servidor.
-- Los parametros invalidos se propagan con THROW (como usp_consultar_grupos_paginado).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Otro docente => 0 filas. Une tablas base; no usa
-- SESSION_CONTEXT ni uv_auth_*.
--
-- Semantica temporal: fechaSolicitud es DATE de calendario (semantica v1, no es un instante).
-- fechaHoraInicioSesionUtc es el DATETIME2(7) de dbo.Sesion y procedenciaTemporalSesion indica si
-- es UTC verificable (UTC_V2/UTC_GENERADOR/UTC_OWNER) o INDETERMINADA (NULL, historica): el
-- consumidor decide segun esa procedencia (contrato UTC v2).
-- Datos personales minimos: nombre del estudiante, sin correo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_revision_docente]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginacion protegida (minimo 1, maximo 100)
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

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesionUtc      = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        totalRegistros                = COUNT(*) OVER()
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    LEFT  JOIN dbo.ArchivoSoporte arc     ON arc.solicitudRevisionAsistencia = sra.id
                                         AND arc.estado = 'ATTACHED'
    WHERE doc.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY sra.fecha DESC, sra.nombre ASC, sra.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
