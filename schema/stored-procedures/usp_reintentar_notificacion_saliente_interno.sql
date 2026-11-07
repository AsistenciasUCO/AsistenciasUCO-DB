USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_reintentar_notificacion_saliente_interno]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Operacion atomica de transicion de estado a PENDIENTE para reintento manual.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_reintentar_notificacion_saliente_interno]
(
    @idNotificacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT            OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado         = 1;

    BEGIN TRY
        -- 1. Validar existencia
        IF NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente WHERE id = @idNotificacion)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_reintentar_notif_saliente;
            SET @savepointCreado = 1;
        END

        -- 2. Validar estado actual con bloqueo protector (UPDLOCK, HOLDLOCK)
        DECLARE @codigoEstado VARCHAR(30);
        SELECT @codigoEstado = e.codigo
        FROM dbo.NotificacionSaliente n WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
        WHERE n.id = @idNotificacion;

        IF @codigoEstado NOT IN ('FALLIDA_DEFINITIVA', 'FALLIDA_REINTENTABLE')
        BEGIN
            IF @savepointCreado = 1 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
            ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_008',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Estado actual: ', @codigoEstado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            RETURN;
        END

        -- 3. Resetear parametros y pasar a PENDIENTE
        DECLARE @idEstadoPendiente UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'PENDIENTE');

        UPDATE dbo.NotificacionSaliente
        SET idEstado         = @idEstadoPendiente,
            intentos         = 0,
            proximoIntentoEn = SYSUTCDATETIME(),
            reservadoHasta   = NULL,
            reservadoPor     = NULL,
            codigoError      = NULL,
            detalleError     = NULL
        WHERE id = @idNotificacion;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_007',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' IdNotificacion: ', @idNotificacion, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_reintentar_notif_saliente;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
