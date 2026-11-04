USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_guardar_tipo_identificacion_interno (HU153, 2026-11-04)
--
-- Nucleo de escritura del catalogo de tipos de documento: con @idTipoIdentificacion NULL inserta (codigo y nombre ya
-- validados por la fachada); con id solo actualiza el NOMBRE (el codigo es inmutable: decision de John, sin estado).
-- Transaccion propia si no hay una abierta; si la hay, savepoint (REC4 #4: sin XACT_ABORT para no condenar la
-- transaccion del llamador). Expone el triplete OUTPUT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_guardar_tipo_identificacion_interno]
(
    @idTipoIdentificacion    UNIQUEIDENTIFIER,
    @codigo                  NVARCHAR(5),
    @nombre                  NVARCHAR(50),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Transaccion propia o savepoint
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sv_guardar_tipo_identificacion;
            SET @savepointCreado = 1;
        END

        -- PASO 2: Alta o cambio de nombre
        IF @idTipoIdentificacion IS NULL
        BEGIN
            INSERT INTO dbo.TipoIdentificacion (id, tipoIdentificacion, nombre)
            VALUES (NEWID(), @codigo, @nombre);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = N'Tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
        ELSE
        BEGIN
            UPDATE dbo.TipoIdentificacion SET nombre = @nombre WHERE id = @idTipoIdentificacion;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005',
                @p_param1 = N'Tipo de documento',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        END
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));

        IF @transaccionPropia = 1
        BEGIN
            COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sv_guardar_tipo_identificacion;
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
