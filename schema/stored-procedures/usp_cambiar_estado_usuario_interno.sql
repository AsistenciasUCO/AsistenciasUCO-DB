USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121/HU122 (habilitador compartido con IAM-001): cambia Usuario.estado. Idempotente: si ya tiene el estado
-- destino no modifica nada y responde exito. Sin transaccion propia (corre dentro de la fachada publica).
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @estaActivo              BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

    BEGIN TRY
        IF @idUsuario IS NULL OR @estaActivo IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE id = @idUsuario)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = 'Usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END
        ELSE
        BEGIN
            UPDATE dbo.Usuario SET estado = @estaActivo WHERE id = @idUsuario AND estado <> @estaActivo;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacion);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
