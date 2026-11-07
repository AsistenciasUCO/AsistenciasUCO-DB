USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_rotar_token_asistencia_automatico (CULM-001 B.2, HU175; CONTRACT §2.8.3, §3.5, DEC-015)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idTokenAsistencia, idToma, idGrupo, idDocenteEmisor,
-- fechaRotacionUtc, fechaExpiracionUtc, rotado (NULL si estadoResultado = 0).
-- Rotacion AUTOMATICA del job del servidor: sin ejecutor (excepcion declarada de RBAC humano, igual que
-- usp_rotar_token_matricula_automatico; solo el rol de runtime del backend tiene EXECUTE). Con @forzar = 0 solo rota si el
-- token debe rotar; si otra instancia ya roto responde exito con rotado = 0 (multi-instancia segura).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_rotar_token_asistencia_automatico]
(
    @idToma        UNIQUEIDENTIFIER,
    @tokenHash     VARBINARY(32),
    @pin           NCHAR(6),
    @forzar        BIT = 0,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @idTokenAsistencia  UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor    UNIQUEIDENTIFIER;
    DECLARE @idGrupo            UNIQUEIDENTIFIER;
    DECLARE @fechaRotacionUtc   DATETIME2(0);
    DECLARE @fechaExpiracionUtc DATETIME2(0);
    DECLARE @rotado             BIT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_rotar_token_asistencia_auto;
            SET @savepointCreado = 1;
        END

        EXEC dbo.usp_internal_rotar_token_asistencia
            @idCorrelacion = @idCorrelacionDefecto, @idToma = @idToma, @tokenHash = @tokenHash, @pin = @pin,
            @forzar = @forzar, @idUsuarioManual = NULL,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @idTokenAsistencia = @idTokenAsistencia OUTPUT, @idDocenteEmisor = @idDocenteEmisor OUTPUT, @idGrupo = @idGrupo OUTPUT,
            @fechaRotacionUtc = @fechaRotacionUtc OUTPUT, @fechaExpiracionUtc = @fechaExpiracionUtc OUTPUT, @rotado = @rotado OUTPUT;

        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
            SET @transaccionPropia = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_rotar_token_asistencia_auto;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idTokenAsistencia       = IIF(@estadoResultado = 1, @idTokenAsistencia, NULL),
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        idDocenteEmisor         = IIF(@estadoResultado = 1, @idDocenteEmisor, NULL),
        fechaRotacionUtc        = IIF(@estadoResultado = 1, @fechaRotacionUtc, NULL),
        fechaExpiracionUtc      = IIF(@estadoResultado = 1, @fechaExpiracionUtc, NULL),
        rotado                  = IIF(@estadoResultado = 1, @rotado, NULL);
END;
GO
