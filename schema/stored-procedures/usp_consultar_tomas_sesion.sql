USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tomas_sesion (CULM-001 B.2, HU175; CONTRACT §2.8.4, §3.2.5 GET /sesiones/{id}/tomas)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 con el mensaje tecnico si la validacion
-- falla). RBAC DOCENTE + titularidad sobre la sesion (SES_001 / SEC_001 / SEC_002 / GEN_002).
-- Filas: una por toma de la sesion (uv_toma_asistencia, orden numero) con los datos de la sesion y su ventana
-- (uv_sesion_estado: ventanaAperturaUtc, ventanaCierreUtc, ventanaAbierta, estaSesionCancelada, motivoCancelacion) y
-- maximoTomas (TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION). Una sesion SIN tomas devuelve una fila con los datos de la sesion
-- y las columnas de la toma en NULL (el docente ve la ventana antes de abrir la primera toma).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tomas_sesion]
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
    DECLARE @maximoTomas          INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_sesion_exista_por_id_interno
            @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        idSesion              = se.idSesion,
        idGrupo               = se.idGrupo,
        numeroSesion          = se.numero,
        horasSesion           = se.horasSesion,
        estaSesionCancelada   = se.estaCancelada,
        motivoCancelacion     = se.motivoCancelacion,
        ventanaAperturaUtc    = se.ventanaAperturaUtc,
        ventanaCierreUtc      = se.ventanaCierreUtc,
        ventanaAbierta        = se.ventanaAbierta,
        maximoTomas           = @maximoTomas,
        totalTomasSesion      = se.totalTomas,
        idToma                = t.idToma,
        numero                = t.numero,
        idModo                = t.idModo,
        codigoModo            = t.codigoModo,
        nombreModo            = t.nombreModo,
        usaCodigoQr           = t.usaCodigoQr,
        marcaAusentesAlCerrar = t.marcaAusentesAlCerrar,
        idEstado              = t.idEstado,
        codigoEstado          = t.codigoEstado,
        nombreEstado          = t.nombreEstado,
        estaAbierta           = t.estaAbierta,
        esImplicita           = t.esImplicita,
        idDocenteApertura     = t.idDocenteApertura,
        fechaAperturaUtc      = t.fechaAperturaUtc,
        fechaCierreUtc        = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        horasToma             = t.horasToma,
        totalRegistros        = t.totalRegistros,
        totalPresentes        = t.totalPresentes,
        totalAusentes         = t.totalAusentes,
        totalExcusas          = t.totalExcusas,
        tieneQrActivo         = t.tieneQrActivo
    FROM dbo.uv_sesion_estado se
    LEFT JOIN dbo.uv_toma_asistencia t ON t.idSesion = se.idSesion
    WHERE se.idSesion = @idSesionDefecto
    ORDER BY t.numero ASC;
END;
GO
