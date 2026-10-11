USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: UNICO camino administrativo para marcar una sesion historica como UTC_OWNER.
-- No es un endpoint del backend: lo ejecuta el owner funcional/DBA con un manifiesto aprobado,
-- sesion por sesion y ambiente por ambiente. Fail-closed:
--   * el ejecutor debe tener perfil ADMINISTRADOR y el aprobador debe ser otro usuario ADMINISTRADOR;
--   * @ambiente debe coincidir con CatalogoParametro OPERACION/AMBIENTE de ESTA base (no sembrado:
--     cada ambiente lo configura su operador; sin el parametro no se puede clasificar nada);
--   * la sesion debe seguir INDETERMINADA (NULL) y con EXACTAMENTE las horas verificadas en el manifiesto;
--   * @fechaHoraInicioUtc/@fechaHoraFinUtc son los instantes UTC confirmados (iguales a los actuales si
--     solo se verifica, distintos si el manifiesto aprueba una conversion individual).
-- El UPDATE de horas+marca y la fila de bitacora se escriben en la MISMA transaccion.
-- El rol runtime del backend tiene DENY EXECUTE sobre este SP.
CREATE OR ALTER PROCEDURE [dbo].[usp_clasificar_procedencia_sesion]
(
    @idSesion                  UNIQUEIDENTIFIER,
    @ambiente                  NVARCHAR(32),
    @idManifiesto              NVARCHAR(64),
    @hashEvidencia             CHAR(64),
    @fechaHoraInicioVerificada DATETIME2,
    @fechaHoraFinVerificada    DATETIME2,
    @fechaHoraInicioUtc        DATETIME2,
    @fechaHoraFinUtc           DATETIME2,
    @idUsuarioAprobador        UNIQUEIDENTIFIER,
    @idCorrelacion             UNIQUEIDENTIFIER,
    @idUsuarioEjecutor         UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioAprobadorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioAprobador, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @ambienteDefecto          NVARCHAR(32) = TRIM(@ambiente);
    DECLARE @idManifiestoDefecto      NVARCHAR(64) = TRIM(@idManifiesto);
    DECLARE @ambienteConfigurado      NVARCHAR(32);

    DECLARE @procedenciaActual  NVARCHAR(24);
    DECLARE @inicioActual       DATETIME2;
    DECLARE @finActual          DATETIME2;
    DECLARE @sesionExiste       BIT = 0;
    DECLARE @filasClasificadas  INT = 0;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor y aprobador obligatorios y distintos, ambos ADMINISTRADOR
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idUsuarioAprobador IS NULL OR @idUsuarioAprobadorDefecto = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioAprobador',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioAprobadorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: manifiesto completo y ambiente de ESTA base
        IF @estadoResultado = 1 AND (@idManifiestoDefecto IS NULL OR @idManifiestoDefecto = N'')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idManifiesto',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@hashEvidencia IS NULL OR @hashEvidencia LIKE '%[^0-9a-f]%' OR LEN(@hashEvidencia) <> 64)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'hashEvidencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @ambienteConfigurado = CONVERT(NVARCHAR(32), valor)
            FROM dbo.CatalogoParametro
            WHERE grupo = 'OPERACION'
              AND clave = 'AMBIENTE'
              AND estaActivo = 1;

            IF @ambienteConfigurado IS NULL OR @ambienteDefecto IS NULL OR @ambienteDefecto <> @ambienteConfigurado
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'OPERACION/AMBIENTE',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: ventana UTC confirmada valida
        IF @estadoResultado = 1 AND (@fechaHoraInicioUtc IS NULL OR @fechaHoraFinUtc IS NULL
            OR @fechaHoraInicioVerificada IS NULL OR @fechaHoraFinVerificada IS NULL)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'fechaHora',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @fechaHoraFinUtc <= @fechaHoraInicioUtc
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_004', @p_param1 = 'fechaHoraFinUtc', @p_param2 = 'fechaHoraInicioUtc',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: transaccion con bloqueo de la fila; la sesion debe seguir exactamente como en el manifiesto
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_clasificar_procedencia;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1
                @sesionExiste = 1,
                @procedenciaActual = procedenciaTemporal,
                @inicioActual = fechaHoraInicio,
                @finActual = fechaHoraFin
            FROM dbo.Sesion WITH (UPDLOCK, HOLDLOCK)
            WHERE id = @idSesionDefecto;

            IF @sesionExiste = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001', @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @procedenciaActual IS NOT NULL
                 OR @inicioActual <> @fechaHoraInicioVerificada
                 OR @finActual <> @fechaHoraFinVerificada
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_006', @p_param1 = @idSesionDefecto, @p_param2 = @idManifiestoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                -- Horas y marca en la MISMA sentencia (UTC-D06).
                UPDATE dbo.Sesion
                SET fechaHoraInicio = @fechaHoraInicioUtc,
                    fechaHoraFin = @fechaHoraFinUtc,
                    procedenciaTemporal = N'UTC_OWNER'
                WHERE id = @idSesionDefecto
                  AND procedenciaTemporal IS NULL
                  AND fechaHoraInicio = @fechaHoraInicioVerificada
                  AND fechaHoraFin = @fechaHoraFinVerificada;

                SET @filasClasificadas = @@ROWCOUNT;

                IF @filasClasificadas <> 1
                    THROW 52111, 'UTC_D06_CLASIFICACION_CONCURRENTE: la sesion cambio durante la clasificacion.', 1;

                INSERT INTO dbo.SesionProcedenciaClasificacion (
                    id, sesion, ambiente, idManifiesto, hashEvidencia, procedenciaAnterior, procedenciaNueva,
                    fechaHoraInicioAnterior, fechaHoraFinAnterior, fechaHoraInicioUtc, fechaHoraFinUtc,
                    usuarioEjecutor, usuarioAprobador, idCorrelacion, fechaRegistro
                )
                VALUES (
                    NEWID(), @idSesionDefecto, @ambienteDefecto, @idManifiestoDefecto, @hashEvidencia, NULL, N'UTC_OWNER',
                    @inicioActual, @finActual, @fechaHoraInicioUtc, @fechaHoraFinUtc,
                    @idUsuarioEjecutorDefecto, @idUsuarioAprobadorDefecto, @idCorrelacionDefecto, SYSUTCDATETIME()
                );

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'SesionProcedenciaTemporal',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
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
        BEGIN
            ROLLBACK TRANSACTION usp_clasificar_procedencia;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

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
        estadoResultado         = @estadoResultado;
END;
GO
