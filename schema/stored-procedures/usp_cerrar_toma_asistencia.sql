USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_toma_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.2, DEC-013, [SUPUESTO-B-08])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, fechaCierreUtc,
-- totalAusentesMarcados, totalFaltantes, yaEstabaCerrada (NULL si estadoResultado = 0).
--
-- El docente titular cierra una toma (no exige ventana para cerrar). Ya cerrada: exito idempotente TOM_011
-- (yaEstabaCerrada = 1, sin escrituras). Si no: cierra el token QR activo de la toma; con @marcarAusentes = 1 (NULL =>
-- ModoTomaAsistencia.marcaAusentesAlCerrar: MANUAL 0, QR 1) y la ventana con margen todavia abierta, inserta SJC a las
-- matriculas activas sin detalle en la toma (usp_internal_marcar_ausentes_toma); vencida la ventana se cierra sin marcar.
-- totalFaltantes = filas de uv_faltantes_toma despues del cierre. Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- Exito TOM_009.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_toma_asistencia]
(
    @idToma            UNIQUEIDENTIFIER,
    @marcarAusentes    BIT = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTomaDefecto            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idToma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeDescartado       NVARCHAR(4000);
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaCierrePrevia DATETIME2(0);
    DECLARE @marcaPorModo      BIT;
    DECLARE @marcar            BIT;
    DECLARE @ventanaAbierta    BIT;
    DECLARE @idEstadoCerrada   UNIQUEIDENTIFIER;
    DECLARE @fechaCierre       DATETIME2(0);
    DECLARE @totalMarcados     INT = 0;
    DECLARE @totalFaltantes    INT;
    DECLARE @yaEstabaCerrada   BIT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
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

        -- Toma existente (TOM_001) y titularidad sobre su sesion
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSesion = t.sesion, @idGrupo = s.grupo
            FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
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

        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoCerrada = e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0;
            IF @idEstadoCerrada IS NULL
                THROW 52511, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;

            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cerrar_toma;
                SET @savepointCreado = 1;
            END

            -- Bloqueo de la sesion (sin exigir ventana para cerrar) y luego de la toma
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SELECT @fechaCierrePrevia = t.fechaCierreUtc, @marcaPorModo = m.marcaAusentesAlCerrar, @totalMarcados = t.totalAusentesMarcados
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo
            WHERE t.id = @idTomaDefecto;

            IF @fechaCierrePrevia IS NOT NULL
            BEGIN
                SET @yaEstabaCerrada = 1;
                SET @fechaCierre = @fechaCierrePrevia;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_011', @p_param1 = @idTomaDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                SET @fechaCierre = SYSUTCDATETIME();
                SET @marcar = IIF(@marcarAusentes IS NULL, @marcaPorModo, @marcarAusentes);
                SELECT @ventanaAbierta = v.ventanaAbierta FROM dbo.uv_sesion_estado v WHERE v.idSesion = @idSesion;
                SET @totalMarcados = 0;

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre
                WHERE toma = @idTomaDefecto AND fechaCierreUtc IS NULL;

                IF @marcar = 1 AND @ventanaAbierta = 1
                    EXEC dbo.usp_internal_marcar_ausentes_toma
                        @idToma = @idTomaDefecto, @idSesion = @idSesion, @idGrupo = @idGrupo,
                        @fechaRegistroUtc = @fechaCierre, @totalMarcados = @totalMarcados OUTPUT;

                UPDATE dbo.TomaAsistencia
                SET estado = @idEstadoCerrada,
                    fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
                    totalAusentesMarcados = @totalMarcados,
                    idCorrelacionCierre = @idCorrelacionDefecto
                WHERE id = @idTomaDefecto;

                SET @p1 = CONVERT(NVARCHAR(20), @totalMarcados);
                SET @p2 = CONVERT(NVARCHAR(36), @idTomaDefecto);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeDescartado OUTPUT;
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'TOM_009', @p_param1 = @p2, @p_param2 = @p1,
                    @mensajeUsuarioResultado = @mensajeDescartado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            SELECT @totalFaltantes = COUNT(1) FROM dbo.uv_faltantes_toma f WHERE f.idToma = @idTomaDefecto;
            SELECT @fechaCierre = t.fechaCierreUtc FROM dbo.TomaAsistencia t WHERE t.id = @idTomaDefecto;

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
            ROLLBACK TRANSACTION sp_cerrar_toma;

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
        idToma                  = IIF(@estadoResultado = 1, @idTomaDefecto, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCierreUtc          = IIF(@estadoResultado = 1, @fechaCierre, NULL),
        totalAusentesMarcados   = IIF(@estadoResultado = 1, @totalMarcados, NULL),
        totalFaltantes          = IIF(@estadoResultado = 1, @totalFaltantes, NULL),
        yaEstabaCerrada         = IIF(@estadoResultado = 1, @yaEstabaCerrada, NULL);
END;
GO
