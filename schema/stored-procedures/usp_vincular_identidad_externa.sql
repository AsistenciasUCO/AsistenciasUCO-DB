USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SEC-BASELINE-017: registra el vinculo estable (emisor, sujeto) -> Usuario.id.
-- Reglas (todas atomicas bajo UPDLOCK/HOLDLOCK; los indices unicos son la ultima barrera ante carreras):
--   * El usuario debe existir y estar activo.
--   * Repetir el mismo vinculo vigente es idempotente (exito sin crear otra fila).
--   * Una identidad externa que ya ocupa otra cuenta, o que fue revocada, se rechaza (GEN_003).
--   * Una cuenta con otra identidad vigente del mismo emisor se rechaza (GEN_003).
-- El correo recibido solo se guarda como evidencia de la vinculacion inicial; no se usa para resolver el vinculo.
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_identidad_externa]
(
    @emisor             NVARCHAR(400),
    @sujeto             NVARCHAR(256),
    @idUsuario          UNIQUEIDENTIFIER,
    @correoVinculacion  NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @yaVinculada             BIT = 0; -- idempotencia interna; el resultado publico es solo el canonico
    DECLARE @usuarioVinculado        UNIQUEIDENTIFIER = NULL;
    DECLARE @estadoVinculo           BIT = NULL;
    DECLARE @conflicto               BIT = 0;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @mutacionRealizada          BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion y parametros presentes
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@emisor IS NULL OR LTRIM(RTRIM(@emisor)) = N'')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'emisor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@sujeto IS NULL OR LTRIM(RTRIM(@sujeto)) = N'')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'sujeto',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idUsuario IS NULL OR @correoVinculacion IS NULL OR LTRIM(RTRIM(@correoVinculacion)) = N'')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuario/correoVinculacion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- PASO 2: transaccion (propia o savepoint si el llamador ya tiene una)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;

            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_vincular_identidad_externa;
                SET @savepointCreado = 1;
            END

            -- PASO 3: el usuario existe y esta activo (GEN_001 en ambos casos, sin revelar cual)
            IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE id = @idUsuario AND estado = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'Usuario',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
                SET @estadoResultado = 0;
            END

            -- PASO 4: la identidad externa ya registrada?
            IF @estadoResultado = 1
            BEGIN
                SELECT TOP 1 @usuarioVinculado = usuario, @estadoVinculo = estado
                FROM dbo.IdentidadExterna WITH (UPDLOCK, HOLDLOCK)
                WHERE emisor = @emisor AND sujeto = @sujeto;

                IF @usuarioVinculado IS NOT NULL
                BEGIN
                    IF @usuarioVinculado = @idUsuario AND @estadoVinculo = 1
                        SET @yaVinculada = 1;
                    ELSE
                        SET @conflicto = 1;
                END
            END

            -- PASO 5: la cuenta ya tiene otra identidad vigente del mismo emisor?
            IF @estadoResultado = 1 AND @conflicto = 0 AND @yaVinculada = 0
               AND EXISTS (SELECT 1 FROM dbo.IdentidadExterna WITH (UPDLOCK, HOLDLOCK)
                           WHERE usuario = @idUsuario AND emisor = @emisor AND estado = 1)
                SET @conflicto = 1;

            IF @conflicto = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_003', @p_param1 = 'IdentidadExterna', @p_param2 = 'emisor/sujeto/usuario',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
                SET @estadoResultado = 0;
            END

            -- PASO 6: registro
            IF @estadoResultado = 1 AND @yaVinculada = 0
            BEGIN
                INSERT INTO dbo.IdentidadExterna (usuario, emisor, sujeto, correoVinculacion, idCorrelacion)
                VALUES (@idUsuario, @emisor, @sujeto, @correoVinculacion, @idCorrelacion);
                SET @mutacionRealizada = 1;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'IdentidadExterna',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            END
        END

        -- PASO 7: cierre de la transaccion respetando el ownership
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1 OR @mutacionRealizada = 0
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                ROLLBACK TRANSACTION usp_vincular_identidad_externa;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        DECLARE @numeroError INT = ERROR_NUMBER();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_vincular_identidad_externa;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        -- Carrera perdida contra los indices unicos: es un conflicto de identidad, no un fallo tecnico.
        IF @numeroError IN (2601, 2627)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003', @p_param1 = 'IdentidadExterna', @p_param2 = 'emisor/sujeto/usuario',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
        END
        ELSE
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SYS_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacion);
        END
        SET @estadoResultado = 0;
    END CATCH

    -- Resultado unificado
    SELECT
        idCorrelacion           = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
