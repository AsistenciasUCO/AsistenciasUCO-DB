USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_guardar_plantilla_notificacion_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Operacion atomica de insercion de nueva version y activacion de plantilla.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_plantilla_notificacion_interno]
(
    @tipo                    VARCHAR(60),
    @idioma                  CHAR(2),
    @asunto                  NVARCHAR(200),
    @cuerpo                  NVARCHAR(4000),
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idCreado                UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000)   OUTPUT,
    @estadoResultado         BIT              OUTPUT
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
    SET @idCreado                = NULL;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_guardar_plantilla_notif;
            SET @savepointCreado = 1;
        END

        -- 1. Bloqueo protector de concurrencia y calculo de nueva version
        DECLARE @maxVersion INT;
        SELECT @maxVersion = MAX([version])
        FROM dbo.PlantillaNotificacion WITH (UPDLOCK, HOLDLOCK)
        WHERE tipo = @tipo AND idioma = @idioma;

        DECLARE @nuevaVersion INT = COALESCE(@maxVersion, 1) + 1;
        IF @maxVersion IS NULL
            SET @nuevaVersion = 2;

        -- 2. Desactivar version activa previa
        UPDATE dbo.PlantillaNotificacion
        SET activa = 0
        WHERE tipo = @tipo AND idioma = @idioma AND activa = 1;

        -- 3. Insertar la nueva version como activa
        SET @idCreado = NEWID();

        INSERT INTO dbo.PlantillaNotificacion (
            id,
            tipo,
            idioma,
            [version],
            asunto,
            cuerpo,
            activa,
            creadoPor,
            creadoEn
        )
        VALUES (
            @idCreado,
            @tipo,
            @idioma,
            @nuevaVersion,
            @asunto,
            @cuerpo,
            1,
            @idUsuarioEjecutor,
            SYSUTCDATETIME()
        );

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'NTF_006',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Version: ', @nuevaVersion, ' Correlacion: ', @idCorrelacionDefecto);

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_guardar_plantilla_notif;
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
        SET @idCreado = NULL;
    END CATCH
END;
GO
