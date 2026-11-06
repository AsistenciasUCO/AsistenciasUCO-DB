USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: validacion PUBLICA (sin ejecutor) de un token o PIN de matricula. La credencial es el hash del token o el PIN
-- de una ventana ACTIVA y vigente. Devuelve los datos MINIMOS del curso (sin datos de estudiantes).
--   * Exactamente uno de @tokenHash / @pin (si no: MQR_007).
--   * Token o PIN inexistente, cerrado, vencido o rotado fuera de tolerancia: MQR_001, el MISMO error en todos los casos
--     (anti-enumeracion). La ventana vencida se marca EXPIRADA de forma perezosa (persistida antes de responder el error).
-- Los rechazos se propagan con THROW 51000 y mensaje "DBCODE=<codigo>|..." (como usp_consultar_reenvio_verificacion_correo).
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_token_matricula_publico]
(
    @tokenHash     VARBINARY(32) = NULL,
    @pin           NCHAR(6)      = NULL,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana       UNIQUEIDENTIFIER;
    DECLARE @idGrupo         UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo   VARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_validar;
            SET @savepointCreado = 1;
        END

        EXEC dbo.usp_internal_resolver_token_matricula
            @tokenHash = @tokenHash, @pin = @pin,
            @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
            @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT;

        -- La unica escritura posible es la expiracion perezosa, que debe persistir aun cuando se rechace.
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END

        IF @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_hu176b_validar;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idGrupo            = v.grupo,
        nombreAsignatura   = v.nombreAsignatura,
        nombreGrupo        = v.nombreGrupo,
        nombreDocente      = v.nombreDocente,
        fechaExpiracionUtc = v.fechaExpiracionUtc,
        cupoDisponible     = v.cupoDisponible
    FROM dbo.uv_token_matricula_grupo v
    WHERE v.id = @idVentana;
END;
GO
