USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_abrir_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, DEC-014, [SUPUESTO-B-07])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, numero, codigoModo, usaCodigoQr,
-- fechaAperturaUtc, ventanaCierreUtc, totalTomasSesion, horasToma (NULL si estadoResultado = 0).
--
-- El docente titular abre una toma MANUAL o QR en una sesion dentro de la ventana [inicio - ASISTENCIA/TOLERANCIA_MINUTOS,
-- fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS). Una sola toma abierta por sesion (TOM_003) y como maximo
-- TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION (TOM_004). El modo se resuelve contra ModoTomaAsistencia.codigo (TOM_002); el estado
-- ABIERTA por la bandera estaAbierta = 1. Bloqueos: Sesion (ventana) -> TomaAsistencia. Las ramas de rechazo no escriben y
-- solo confirman la transaccion propia (compatible con INSERT ... EXEC). Exito TOM_008.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_toma_asistencia]
(
    @idSesion          UNIQUEIDENTIFIER,
    @codigoModo        NVARCHAR(20),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @maximoTomas       INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION');
    DECLARE @codigoModoLimpio  NVARCHAR(20) = UPPER(TRIM(@codigoModo));
    DECLARE @idModo            UNIQUEIDENTIFIER;
    DECLARE @codigoModoResuelto NVARCHAR(20);
    DECLARE @usaCodigoQr       BIT;
    DECLARE @idEstadoAbierta   UNIQUEIDENTIFIER;
    DECLARE @idDocente         UNIQUEIDENTIFIER;
    DECLARE @idTomaAbierta     UNIQUEIDENTIFIER;
    DECLARE @totalTomas        INT;
    DECLARE @numero            SMALLINT;
    DECLARE @idToma            UNIQUEIDENTIFIER;
    DECLARE @fechaApertura     DATETIME2(0);
    DECLARE @ventanaCierre     DATETIME2(0);
    DECLARE @horasToma         DECIMAL(12,6);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
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
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE), sesion existente y titularidad
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idSesionDefecto, @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 3: modo de la toma (TOM_002) y estado ABIERTA por bandera
        IF @estadoResultado = 1
        BEGIN
            SELECT @idModo = m.id, @codigoModoResuelto = m.codigo, @usaCodigoQr = m.usaCodigoQr
            FROM dbo.ModoTomaAsistencia m
            WHERE m.codigo = @codigoModoLimpio;
            SELECT @idEstadoAbierta = e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 1;
            SELECT @idDocente = d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioEjecutorDefecto;

            IF @idModo IS NULL
            BEGIN
                SET @p1 = IIF(@codigoModo IS NULL, N'NULL', @codigoModo);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_002', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @idEstadoAbierta IS NULL OR @maximoTomas IS NULL
                THROW 52510, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 1) o TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION.', 1;
        END

        -- PASO 4: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_abrir_toma;
                SET @savepointCreado = 1;
            END

            -- Ventana con tolerancia y margen (bloquea Sesion; SES_007/008/009/010)
            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesionDefecto, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SELECT @totalTomas = COUNT(1), @numero = ISNULL(MAX(t.numero), 0) + 1,
                       @idTomaAbierta = CAST(MAX(IIF(t.fechaCierreUtc IS NULL, CAST(t.id AS NVARCHAR(36)), NULL)) AS UNIQUEIDENTIFIER)
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.sesion = @idSesionDefecto;

                IF @idTomaAbierta IS NOT NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_003', @p_param1 = @idSesionDefecto, @p_param2 = @idTomaAbierta,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @totalTomas >= @maximoTomas
                BEGIN
                    SET @p1 = CONVERT(NVARCHAR(20), @maximoTomas);
                    SET @p2 = CONVERT(NVARCHAR(36), @idSesionDefecto);
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_004', @p_param1 = @p1,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_004', @p_param1 = @p2,
                        @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    SET @idToma = NEWID();
                    SET @fechaApertura = SYSUTCDATETIME();
                    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc,
                                                    fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
                    VALUES (@idToma, @idSesionDefecto, @numero, @idModo, @idEstadoAbierta, 0, @idDocente, @fechaApertura, NULL, 0,
                            @idCorrelacionDefecto, NULL);

                    SELECT @ventanaCierre = CAST(DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), s.fechaHoraFin) AS DATETIME2(0))
                    FROM dbo.Sesion s WHERE s.id = @idSesionDefecto;
                    SET @totalTomas = @totalTomas + 1;
                    SET @horasToma = dbo.ufn_horas_toma(@idSesionDefecto);

                    SET @p1 = CONVERT(NVARCHAR(20), @numero);
                    SET @p2 = CONVERT(NVARCHAR(36), @idToma);
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_008', @p_param1 = @p1,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_008', @p_param1 = @p2, @p_param2 = @codigoModoResuelto,
                        @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END

            -- Las ramas de rechazo no escriben: solo se confirma la transaccion propia (libera el bloqueo)
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
            ROLLBACK TRANSACTION sp_abrir_toma;

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
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL),
        numero                  = IIF(@estadoResultado = 1, @numero, NULL),
        codigoModo              = IIF(@estadoResultado = 1, @codigoModoResuelto, NULL),
        usaCodigoQr             = IIF(@estadoResultado = 1, @usaCodigoQr, NULL),
        fechaAperturaUtc        = IIF(@estadoResultado = 1, @fechaApertura, NULL),
        ventanaCierreUtc        = IIF(@estadoResultado = 1, @ventanaCierre, NULL),
        totalTomasSesion        = IIF(@estadoResultado = 1, @totalTomas, NULL),
        horasToma               = IIF(@estadoResultado = 1, @horasToma, NULL);
END;
GO
