USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cancelar_sesion (CULM-001 B.1, HU047; CONTRACT §2.7.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idSesion, idGrupo, fechaCancelacionUtc,
-- totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El docente titular cancela una sesion con justificacion. Se puede cancelar una sesion futura o una sin asistencia
-- registrada (tambien pasada) ([SUPUESTO-B-10]). Con asistencia: SES_012 si la ventana [.., fin + MARGEN) no ha
-- terminado; SES_016 si ya termino (la correccion se hace por reclamo). Doble cancelacion: SES_011 (no idempotente,
-- se conserva el motivo original). Motivo recortado fuera de SESION/MOTIVO_CANCELACION_LONGITUD_MINIMA..MAXIMA: SES_013.
-- El tipo de cancelacion se resuelve por la bandera TipoCancelacionSesion.esAutomatica = 0 (sin literales).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la
-- cancelacion y la asistencia, el mismo bloqueo que toma la ventana de registro: registro y cancelacion se serializan.
-- Las ramas de rechazo no escriben: solo confirman la transaccion propia (sin ROLLBACK, compatible con INSERT ... EXEC).
-- @motivo se declara NVARCHAR(4000) (no 500) para que un motivo de mas de 500 caracteres llegue entero y se rechace con
-- SES_013 en lugar de truncarse en silencio (B1-CAN-03); la columna SesionCancelacion.motivo sigue siendo NVARCHAR(500).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cancelar_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @motivo            NVARCHAR(4000),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @motivoLimpio      NVARCHAR(MAX) = LTRIM(RTRIM(@motivo));
    DECLARE @longitudMinima    INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MINIMA');
    DECLARE @longitudMaxima    INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MAXIMA');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @codigoTipoManual  NVARCHAR(20);
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraFin      DATETIME2;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
    DECLARE @longitudMinimaTexto NVARCHAR(20);
    DECLARE @longitudMaximaTexto NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: sesion existente (SES_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: titularidad del docente sobre la sesion (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: motivo recortado dentro de los limites parametrizados (SES_013)
        IF @estadoResultado = 1
           AND (@motivoLimpio IS NULL OR @longitudMinima IS NULL OR @longitudMaxima IS NULL
                OR LEN(@motivoLimpio) < @longitudMinima OR LEN(@motivoLimpio) > @longitudMaxima)
        BEGIN
            SET @longitudMinimaTexto = CONVERT(NVARCHAR(20), @longitudMinima);
            SET @longitudMaximaTexto = CONVERT(NVARCHAR(20), @longitudMaxima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_013', @p_param1 = @longitudMinimaTexto, @p_param2 = @longitudMaximaTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: tipo manual de cancelacion por bandera de catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id, @codigoTipoManual = t.codigo
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            IF @idTipoManual IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cancelar_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @idGrupo = s.grupo, @fechaHoraFin = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';
            ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = @idSesionDefecto)
                SET @codigoRechazo = IIF(SYSUTCDATETIME() >= DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), @fechaHoraFin),
                                         'SES_016', 'SES_012');

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoLimpio, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_014', @p_param1 = @idSesionDefecto, @p_param2 = @codigoTipoManual,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera el bloqueo).
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
            ROLLBACK TRANSACTION sp_cancelar_sesion;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idSesion                = IIF(@estadoResultado = 1, @idSesionDefecto, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCancelacionUtc     = IIF(@estadoResultado = 1, @fechaCancelacion, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO
