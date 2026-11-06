USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_activar_version_plantilla_notificacion_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Operacion atomica de activacion de una version existente de plantilla.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_activar_version_plantilla_notificacion_interno]
(
    @tipo                    VARCHAR(60),
    @idioma                  CHAR(2),
    @version                 INT,
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
        -- 1. Verificar si la version existe para el tipo e idioma
        IF NOT EXISTS (
            SELECT 1 
            FROM dbo.PlantillaNotificacion 
            WHERE tipo = @tipo AND idioma = @idioma AND [version] = @version
        )
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'NTF_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Version no encontrada: ', @version, ' Tipo: ', @tipo, ' Correlacion: ', @idCorrelacionDefecto);
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
            SAVE TRANSACTION sp_activar_version_plantilla;
            SET @savepointCreado = 1;
        END

        -- 2. Bloqueo protector de concurrencia
        -- Se asigna a una variable: un SELECT suelto emitiria un result set extra antes de la tupla canonica.
        DECLARE @bloqueoTomado INT;
        SELECT @bloqueoTomado = 1
        FROM dbo.PlantillaNotificacion WITH (UPDLOCK, HOLDLOCK)
        WHERE tipo = @tipo AND idioma = @idioma;

        -- 3. Desactivar version activa previa
        UPDATE dbo.PlantillaNotificacion
        SET activa = 0
        WHERE tipo = @tipo AND idioma = @idioma AND activa = 1 AND [version] <> @version;

        -- 4. Activar la version solicitada
        UPDATE dbo.PlantillaNotificacion
        SET activa = 1
        WHERE tipo = @tipo AND idioma = @idioma AND [version] = @version;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_006',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Activada version: ', @version, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_activar_version_plantilla;
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
