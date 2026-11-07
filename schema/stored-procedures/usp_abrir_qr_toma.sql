USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_abrir_qr_toma (CULM-001 B.2, HU175; CONTRACT §2.8.3, DEC-015)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idTokenAsistencia, idToma, idSesion, idGrupo,
-- fechaRotacionUtc, fechaExpiracionUtc, rotacionSegundos (NULL si estadoResultado = 0).
--
-- El docente titular emite el token/PIN de una toma QR ABIERTA dentro de la ventana con tolerancia. El backend genera el
-- token (32 bytes) y el PIN (6 digitos) y envia solo el SHA-256 del token. Modo no QR: AQR_003; toma cerrada: AQR_005;
-- PIN igual a un PIN activo o a un PIN anterior vigente (o hash repetido): AQR_006 sin escritura (el backend reintenta).
-- Cierra el token activo previo de la toma (re-proyeccion) e inserta el nuevo: emision = rotacion = ahora, expiracion =
-- fin de la sesion + ASISTENCIA/MARGEN_RETARDO_MINUTOS. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito AQR_012.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_qr_toma]
(
    @idToma            UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32),
    @pin               NCHAR(6),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos  INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos      INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @rotacionSegundos   INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS');
    DECLARE @toleranciaSegundos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS');
    DECLARE @idSesion           UNIQUEIDENTIFIER;
    DECLARE @idGrupo            UNIQUEIDENTIFIER;
    DECLARE @usaCodigoQr        BIT;
    DECLARE @tomaAbierta        BIT;
    DECLARE @idDocente          UNIQUEIDENTIFIER;
    DECLARE @idToken            UNIQUEIDENTIFIER;
    DECLARE @ahora              DATETIME2(0);
    DECLARE @expiracion         DATETIME2(0);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @rotacionSegundos = IIF(@rotacionSegundos IS NULL OR @rotacionSegundos < 1, 60, @rotacionSegundos);
    SET @toleranciaSegundos = IIF(@toleranciaSegundos IS NULL OR @toleranciaSegundos < 0, 0, @toleranciaSegundos);
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo, @usaCodigoQr = m.usaCodigoQr
            FROM dbo.TomaAsistencia t
            INNER JOIN dbo.Sesion s ON s.id = t.sesion
            INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo
            WHERE t.id = @idTomaDefecto;

            IF @idSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_001', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesion, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Hash SHA-256 de 32 bytes y PIN de 6 digitos (los genera el backend)
        IF @estadoResultado = 1
           AND (@tokenHash IS NULL OR DATALENGTH(@tokenHash) <> 32 OR @pin IS NULL OR LEN(@pin) <> 6 OR @pin LIKE N'%[^0-9]%')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'tokenHash/pin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @usaCodigoQr = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_003', @p_param1 = @idTomaDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @idDocente = d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioEjecutorDefecto;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_abrir_qr_toma;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SELECT @tomaAbierta = IIF(t.fechaCierreUtc IS NULL, 1, 0)
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.id = @idTomaDefecto;

                IF @tomaAbierta = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_005', @p_param1 = @idTomaDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                SET @ahora = SYSUTCDATETIME();
                IF EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
                           WHERE tk.fechaCierreUtc IS NULL
                             AND (tk.pin = @pin
                                  OR (tk.pinAnterior = @pin AND @ahora < tk.fechaExpiracionUtc
                                      AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc))))
                   OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
                              WHERE tk.tokenHash = @tokenHash OR tk.tokenHashAnterior = @tokenHash)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_006', @p_param1 = @pin,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                SELECT @expiracion = CAST(DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), s.fechaHoraFin) AS DATETIME2(0))
                FROM dbo.Sesion s WHERE s.id = @idSesion;
                IF @expiracion <= @ahora SET @expiracion = DATEADD(SECOND, 1, @ahora);

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @ahora WHERE toma = @idTomaDefecto AND fechaCierreUtc IS NULL;

                SET @idToken = NEWID();
                INSERT INTO dbo.TokenAsistenciaToma (id, toma, docenteEmisor, tokenHash, pin, tokenHashAnterior, pinAnterior,
                                                     fechaEmisionUtc, fechaRotacionUtc, fechaExpiracionUtc, fechaCierreUtc, idCorrelacionEmision)
                VALUES (@idToken, @idTomaDefecto, @idDocente, @tokenHash, @pin, NULL, NULL, @ahora, @ahora, @expiracion, NULL, @idCorrelacionDefecto);

                SET @p1 = CONVERT(NVARCHAR(36), @idToken);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_012', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
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
            ROLLBACK TRANSACTION sp_abrir_qr_toma;

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
        idTokenAsistencia       = IIF(@estadoResultado = 1, @idToken, NULL),
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaRotacionUtc        = IIF(@estadoResultado = 1, @ahora, NULL),
        fechaExpiracionUtc      = IIF(@estadoResultado = 1, @expiracion, NULL),
        rotacionSegundos        = IIF(@estadoResultado = 1, @rotacionSegundos, NULL);
END;
GO
