USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_solicitud_ingreso_grupo  (HU053/HU054/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Destinatarios de los avisos de una solicitud de ingreso: el ESTUDIANTE solicitante y el DOCENTE titular del grupo,
-- con el contexto del grupo. Solo los ve el propio estudiante o el docente titular (otro ejecutor => 0 filas).
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER
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

    ;WITH contexto AS (
        SELECT g.id AS idGrupo, g.codigo AS codigoGrupo, g.nombre AS nombreGrupo, asg.nombre AS nombreAsignatura,
               e.usuario AS usuarioEstudiante, d.usuario AS usuarioDocente
        FROM dbo.SolicitudIngresoGrupo s
        INNER JOIN dbo.Estudiante e   ON e.id = s.estudiante
        INNER JOIN dbo.Grupo g        ON g.id = s.grupo
        INNER JOIN dbo.Docente d      ON d.id = g.docente
        INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura
        WHERE s.id = @idSolicitud AND @idUsuarioDefecto IN (e.usuario, d.usuario)
    ),
    destinatarios AS (
        SELECT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
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
        codigoGrupo      = dst.codigoGrupo,
        nombreGrupo      = dst.nombreGrupo,
        nombreAsignatura = dst.nombreAsignatura
    FROM destinatarios dst
    INNER JOIN dbo.Usuario u ON u.id = dst.idUsuario
    ORDER BY dst.orden;
END;
GO
