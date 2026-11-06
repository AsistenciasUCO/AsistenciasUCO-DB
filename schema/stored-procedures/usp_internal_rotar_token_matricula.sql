USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): nucleo interno de la rotacion de token/PIN de la ventana ACTIVA de un grupo.
-- Lo invocan las fachadas usp_rotar_token_matricula_grupo (manual, con ejecutor) y usp_rotar_token_matricula_automatico
-- (job, sin ejecutor). NO se concede EXECUTE al rol de runtime. CONTRACT A2.
--   * @idUsuarioManual NO NULL: regeneracion del docente: RBAC DOCENTE + titularidad (SEC_002); rota siempre.
--   * @idUsuarioManual NULL: rotacion automatica: solo rota si ya vencio ROTACION_SEGUNDOS (o @forzar = 1); si no, exito
--     sin cambios (idempotente entre instancias del job).
--   * Ventana vencida: la marca EXPIRADA (se persiste) y rechaza con MQR_001, sin token nuevo.
--   * PIN nuevo repetido en el vigente o anterior de otra ventana activa -> MQR_006 sin cambios.
-- Gestiona su propia transaccion (propia o savepoint) y devuelve el resultado por parametros OUTPUT.
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_rotar_token_matricula]
(
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idGrupo                  UNIQUEIDENTIFIER,
    @tokenHash                VARBINARY(32),
    @pin                      NCHAR(6),
    @forzar                   BIT,
    @idUsuarioManual          UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idVentana                UNIQUEIDENTIFIER OUTPUT,
    @idDocenteEmisor          UNIQUEIDENTIFIER OUTPUT,
    @fechaRotacionUtc         DATETIME2(0)     OUTPUT,
    @fechaExpiracionUtc       DATETIME2(0)     OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @codigoRechazo              VARCHAR(20) = NULL;
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @idVentana = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idGrupo IS NULL OR @tokenHash IS NULL OR @pin IS NULL OR @pin LIKE N'%[^0-9]%' OR LEN(@pin) <> 6)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idGrupo/tokenHash/pin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Regeneracion manual: RBAC DOCENTE y titularidad
        IF @estadoResultado = 1 AND @idUsuarioManual IS NOT NULL
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioManual,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1 AND NOT EXISTS (
                SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                WHERE g.id = @idGrupoDefecto AND d.usuario = @idUsuarioManual
            )
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            DECLARE @estadoActiva   NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10));
            DECLARE @estadoExpirada NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA') AS NVARCHAR(10));
            DECLARE @rotacionSegundos INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'ROTACION_SEGUNDOS');
            DECLARE @ahora DATETIME2(0) = SYSUTCDATETIME();
            DECLARE @debeRotar BIT = 0;
            DECLARE @idVentanaActual UNIQUEIDENTIFIER = NULL;

            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_hu176b_rotar;
                SET @savepointCreado = 1;
            END

            SELECT @idVentanaActual = t.id, @idDocenteEmisor = t.docenteEmisor,
                   @fechaRotacionUtc = t.fechaRotacionUtc, @fechaExpiracionUtc = t.fechaExpiracionUtc
            FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
            WHERE t.grupo = @idGrupoDefecto AND t.estado = @estadoActiva;

            IF @idVentanaActual IS NULL
                SET @codigoRechazo = 'MQR_001';
            ELSE IF @ahora >= @fechaExpiracionUtc
            BEGIN
                -- Fin de la ventana: expira (se persiste) y no se genera token nuevo
                UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoExpirada WHERE id = @idVentanaActual;
                SET @codigoRechazo = 'MQR_001';
            END
            ELSE
            BEGIN
                SET @debeRotar = IIF(@idUsuarioManual IS NOT NULL OR @forzar = 1
                                     OR @ahora >= DATEADD(SECOND, @rotacionSegundos, @fechaRotacionUtc), 1, 0);

                IF @debeRotar = 1
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
                        WHERE t.estado = @estadoActiva AND t.id <> @idVentanaActual AND (t.pin = @pin OR t.pinAnterior = @pin)
                    )
                        SET @codigoRechazo = 'MQR_006';
                    ELSE
                    BEGIN
                        UPDATE dbo.TokenMatriculaGrupo
                        SET tokenHashAnterior = tokenHash,
                            pinAnterior       = pin,
                            tokenHash         = @tokenHash,
                            pin               = @pin,
                            fechaRotacionUtc  = @ahora
                        WHERE id = @idVentanaActual;

                        SET @fechaRotacionUtc = @ahora;
                    END
                END
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
            ELSE
            BEGIN
                SET @idVentana = @idVentanaActual;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Rotacion de token de matricula',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Las ramas de rechazo solo pueden haber escrito la expiracion, que debe persistir: se confirma siempre.
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
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
            ROLLBACK TRANSACTION sp_hu176b_rotar;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idVentana = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;
    END CATCH

    -- Los datos de la ventana solo se devuelven en exito
    IF @estadoResultado = 0
        SELECT @idVentana = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;
END;
GO
