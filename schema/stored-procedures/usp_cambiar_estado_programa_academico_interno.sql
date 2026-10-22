USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_cambiar_estado_programa_academico_interno]
-- Historia de Usuario: HU078
-- Ambito: cambio atomico del estado: rechaza desactivar con grupos habilitados en el periodo vigente (D4) y activar con la facultad inactiva.
-- La transaccion vive aqui (SET XACT_ABORT ON, transaccion propia o savepoint si el llamador ya tiene una).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_programa_academico_interno]
(
    @idPrograma              UNIQUEIDENTIFIER,
    @estaActivo              BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @msgP1 NVARCHAR(500), @msgP2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cambiar_estado_programa;
                SET @savepointCreado = 1;
            END

            IF @estadoResultado = 1 AND (@estaActivo = 0 AND EXISTS (SELECT 1 FROM dbo.uv_grupo_programa gp WHERE gp.idPrograma = @idPrograma AND gp.grupoEstaHablitado = 1))
            BEGIN
                SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idPrograma) AS NVARCHAR(500));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_007',
                    @p_param1 = @msgP1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1 AND (@estaActivo = 1 AND EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idPrograma AND p.estaActivoPrograma = 0 AND NOT EXISTS (SELECT 1 FROM dbo.uv_facultad f WHERE f.id = p.idFacultad AND f.estaActivaFacultad = 1)))
            BEGIN
                SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idPrograma) AS NVARCHAR(500));
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_008',
                    @p_param1 = @msgP1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                UPDATE dbo.Programa
                SET estado = @estaActivo
                WHERE id = @idPrograma;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005',
                    @p_param1 = 'Estado Programa Academico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Una validacion de negocio fallida no escribio nada: se libera la transaccion propia.
            IF @estadoResultado = 0 AND @transaccionPropia = 1 AND @@TRANCOUNT > 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END

            IF @estadoResultado = 1 AND @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_cambiar_estado_programa;
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
