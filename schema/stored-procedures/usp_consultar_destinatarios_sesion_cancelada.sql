USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_sesion_cancelada (CULM-001 B.1, HU047; CONTRACT §2.7.3)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET sin paginacion (<= cupo del grupo).
-- Destinatarios de la notificacion SESION_CANCELADA: las matriculas activas (MATRICULA/ESTADO_INSCRITA) del grupo de
-- la sesion, solo si la sesion esta cancelada (si no, 0 filas). RBAC DOCENTE + titularidad 'SESION' dentro del SP
-- (THROW 51000 con el mensaje tecnico si falla). Mismo formato que usp_consultar_destinatarios_reclamo_asistencia: el
-- correo es de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_cancelada]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoMatriculaActiva NVARCHAR(10)    = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idSesion IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/idSesion',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'DOCENTE',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto,
            @idEntidadPadre = @idSesionDefecto,
            @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idEstudiante      = eg.idEstudiante,
        idUsuario         = ei.idUsuario,
        nombreCompleto    = CAST(ei.nombreCompleto AS NVARCHAR(400)),
        correo            = u.correo,
        nombreAsignatura  = g.nombreAsignatura,
        nombreGrupo       = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
        nombreDocente     = CAST(di.nombreCompleto AS NVARCHAR(400)),
        fechaHoraInicio   = se.fechaHoraInicio,
        fechaHoraFin      = se.fechaHoraFin,
        motivoCancelacion = se.motivoCancelacion
    FROM dbo.uv_sesion_estado se
    INNER JOIN dbo.uv_grupo g               ON g.id = se.idGrupo
    INNER JOIN dbo.uv_docente_identidad di  ON di.id = g.idDocente
    INNER JOIN dbo.uv_estudiante_grupo eg   ON eg.idGrupo = se.idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = eg.idEstudiante
    INNER JOIN dbo.uv_usuario u             ON u.id = ei.idUsuario
    WHERE se.idSesion = @idSesionDefecto
      AND se.estaCancelada = 1
    ORDER BY ei.nombreCompleto, eg.idEstudiante;
END;
GO
