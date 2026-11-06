USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_reclamo_asistencia (HU010 / HU037 / HU042)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor o correlacion nula).
-- Destinatarios de los avisos de reclamos de asistencia: el ESTUDIANTE y el DOCENTE titular del grupo,
-- con el contexto del grupo, asignatura y sesion.
-- Puede invocarse por @idSolicitud (resolucion de reclamo HU037) o por (@idSesion, @idEstudiante) (radicacion HU010).
-- Solo los ve el propio estudiante o el docente titular (otro ejecutor => 0 filas).
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_reclamo_asistencia]
(
    @idSolicitud       UNIQUEIDENTIFIER = NULL,
    @idSesion          UNIQUEIDENTIFIER = NULL,
    @idEstudiante      UNIQUEIDENTIFIER = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @idSolicitud IS NULL AND (@idSesion IS NULL OR @idEstudiante IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'idSolicitud o (idSesion e idEstudiante)',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH contexto AS (
        -- Caso 1: Invocado por idSolicitud (resolucion de reclamo)
        SELECT DISTINCT
            g.id AS idGrupo,
            g.codigo AS codigoGrupo,
            g.nombre AS nombreGrupo,
            asg.nombre AS nombreAsignatura,
            CONVERT(VARCHAR(10), s.fechaHoraInicio, 23) AS fechaSesion,
            e.usuario AS usuarioEstudiante,
            d.usuario AS usuarioDocente
        FROM dbo.SolicitudRevisionAsistencia sra
        INNER JOIN dbo.Asistencia ast         ON ast.id = sra.asistencia
        INNER JOIN dbo.Sesion s               ON s.id = ast.sesion
        INNER JOIN dbo.Grupo g                ON g.id = s.grupo
        INNER JOIN dbo.Asignatura asg         ON asg.id = g.asignatura
        INNER JOIN dbo.Docente d              ON d.id = g.docente
        INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = ast.estudianteGrupo
        INNER JOIN dbo.Estudiante e           ON e.id = eg.estudiante
        WHERE @idSolicitud IS NOT NULL
          AND sra.id = @idSolicitud
          AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio OR @idUsuarioDefecto IN (e.usuario, d.usuario))

        UNION ALL

        -- Caso 2: Invocado por idSesion e idEstudiante (radicacion de reclamo)
        SELECT DISTINCT
            g.id AS idGrupo,
            g.codigo AS codigoGrupo,
            g.nombre AS nombreGrupo,
            asg.nombre AS nombreAsignatura,
            CONVERT(VARCHAR(10), s.fechaHoraInicio, 23) AS fechaSesion,
            e.usuario AS usuarioEstudiante,
            d.usuario AS usuarioDocente
        FROM dbo.Sesion s
        INNER JOIN dbo.Grupo g                ON g.id = s.grupo
        INNER JOIN dbo.Asignatura asg         ON asg.id = g.asignatura
        INNER JOIN dbo.Docente d              ON d.id = g.docente
        INNER JOIN dbo.EstudianteGrupo eg     ON eg.grupo = g.id AND eg.estudiante = @idEstudiante
        INNER JOIN dbo.Estudiante e           ON e.id = eg.estudiante
        WHERE @idSolicitud IS NULL
          AND s.id = @idSesion
          AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio OR @idUsuarioDefecto IN (e.usuario, d.usuario))
    ),
    destinatarios AS (
        SELECT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura, fechaSesion FROM contexto
        UNION ALL
        SELECT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura, fechaSesion FROM contexto
    )
    SELECT
        rolDestinatario  = CAST(dst.rolDestinatario AS VARCHAR(20)),
        idUsuario        = dst.idUsuario,
        nombreCompleto   = CAST(CONCAT_WS(N' ',
                               NULLIF(TRIM(u.primerNombre), N''),
                               NULLIF(TRIM(u.segundoNombre), N''),
                               NULLIF(TRIM(u.primerApellido), N''),
                               NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo           = u.correo,
        idGrupo          = dst.idGrupo,
        nombreGrupo      = CAST(CONCAT(N'G', FORMAT(dst.codigoGrupo, '00'), N' de ', dst.nombreAsignatura) AS NVARCHAR(300)),
        fechaSesion      = dst.fechaSesion,
        codigoGrupo      = dst.codigoGrupo,
        nombreAsignatura = dst.nombreAsignatura
    FROM destinatarios dst
    INNER JOIN dbo.Usuario u ON u.id = dst.idUsuario
    ORDER BY dst.orden;
END;
GO
