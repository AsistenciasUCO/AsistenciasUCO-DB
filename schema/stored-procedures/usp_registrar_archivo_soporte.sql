USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_archivo_soporte  (LB-004D, W1)
--
-- Registra en estado DRAFT la metadata de un soporte ya almacenado por el backend. El propietario
-- es SIEMPRE @idUsuarioEjecutor (no existe parametro de propietario). El fileId lo genera el
-- backend; la DB no lo genera ni conoce bucket, objectKey ni URL.
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Idempotente por @idArchivoSoporte: mismo propietario y misma metadata => exito sin escribir;
-- otro propietario o metadata distinta => ARC_002 generico (no revela de quien es).
-- Concurrencia: lectura con UPDLOCK + HOLDLOCK (bloqueo de rango sobre la PK) serializa altas del
-- mismo id; si aun asi se viola la PK, el CATCH reevalua la idempotencia fuera de la transaccion.
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_archivo_soporte]
(
    @idArchivoSoporte   UNIQUEIDENTIFIER,
    @nombreOriginal     NVARCHAR(250),
    @tipoContenido      VARCHAR(50),
    @tamanioBytes       BIGINT,
    @checksumSha256     CHAR(64),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idArchivoDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idArchivoSoporte, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(250)    = TRIM(@nombreOriginal);
    DECLARE @tipoDefecto              VARCHAR(50)      = TRIM(@tipoContenido);
    DECLARE @tamanioMaximo            BIGINT           = TRY_CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'TAMANIO_MAXIMO_BYTES') AS BIGINT);

    DECLARE @propietarioExistente UNIQUEIDENTIFIER;
    DECLARE @metadataCoincide     BIT;
    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: El ejecutor debe ser un estudiante institucional
        IF @estadoResultado = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Metadata valida (tipo permitido, 0 < tamano <= maximo, checksum SHA-256 hex minuscula)
        IF @estadoResultado = 1
           AND (   @idArchivoSoporte IS NULL OR @idArchivoDefecto = @guidVacio
                OR @nombreDefecto IS NULL OR @nombreDefecto = ''
                OR @tipoDefecto IS NULL OR @tipoDefecto NOT IN ('application/pdf', 'image/png', 'image/jpeg')
                OR @tamanioBytes IS NULL OR @tamanioBytes <= 0
                OR @tamanioMaximo IS NULL OR @tamanioBytes > @tamanioMaximo
                OR @checksumSha256 IS NULL OR LEN(@checksumSha256) <> 64
                OR @checksumSha256 LIKE '%[^0-9a-f]%' COLLATE Latin1_General_BIN)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Transaccion propia (o savepoint si el llamador ya tiene una) y alta idempotente
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
                SAVE TRANSACTION usp_registrar_archivo_soporte;
                SET @savepointCreado = 1;
            END

            SELECT @propietarioExistente = a.usuarioPropietario,
                   @metadataCoincide = IIF(a.nombreOriginal = @nombreDefecto
                                           AND a.tipoContenido = @tipoDefecto
                                           AND a.tamanioBytes = @tamanioBytes
                                           AND a.checksumSha256 = @checksumSha256, 1, 0)
            FROM dbo.ArchivoSoporte a WITH (UPDLOCK, HOLDLOCK)
            WHERE a.id = @idArchivoDefecto;

            IF @propietarioExistente IS NULL
            BEGIN
                INSERT INTO dbo.ArchivoSoporte (
                    id, usuarioPropietario, solicitudRevisionAsistencia, nombreOriginal, tipoContenido,
                    tamanioBytes, checksumSha256, estado, fechaRegistroUtc, fechaAdjuncionUtc,
                    fechaCambioEstadoUtc, idCorrelacionRegistro, idCorrelacionAdjuncion
                )
                VALUES (
                    @idArchivoDefecto, @idUsuarioEjecutorDefecto, NULL, @nombreDefecto, @tipoDefecto,
                    @tamanioBytes, @checksumSha256, 'DRAFT', SYSUTCDATETIME(), NULL,
                    SYSUTCDATETIME(), @idCorrelacionDefecto, NULL
                );
            END
            ELSE IF @propietarioExistente <> @idUsuarioEjecutorDefecto OR @metadataCoincide = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ARC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- else: reintento identico => exito idempotente sin escritura

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'ArchivoSoporte',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

        -- PASO 7: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        -- Con savepoint (transaccion del llamador) un rechazo no escribio nada: no hay nada que revertir.
    END TRY
    BEGIN CATCH
        DECLARE @numeroError INT = ERROR_NUMBER();
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_registrar_archivo_soporte;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        -- Carrera perdida contra otro alta del mismo id (PK/unique): reevaluar idempotencia, sin SYS_001
        SET @propietarioExistente = NULL;
        IF @numeroError IN (2601, 2627) AND @transaccionPropia = 1
        BEGIN
            SELECT @propietarioExistente = a.usuarioPropietario
            FROM dbo.ArchivoSoporte a
            WHERE a.id = @idArchivoDefecto
              AND a.usuarioPropietario = @idUsuarioEjecutorDefecto
              AND a.nombreOriginal = @nombreDefecto
              AND a.tipoContenido = @tipoDefecto
              AND a.tamanioBytes = @tamanioBytes
              AND a.checksumSha256 = @checksumSha256;
        END

        IF @propietarioExistente IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'ArchivoSoporte',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
        END
        ELSE
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SYS_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
