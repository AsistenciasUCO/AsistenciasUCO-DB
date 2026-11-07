USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: nucleo unico de actualizacion de sesion compartido por
--   * usp_actualizar_sesion    (v1, firma congelada DB-GP-001C) -> @procedenciaTemporal = NULL
--   * usp_actualizar_sesion_v2 (v2, instantes UTC confirmados)   -> @procedenciaTemporal = 'UTC_V2'
-- PUT completo de horas: horas y marca se escriben en el MISMO UPDATE. Una actualizacion v1 de una
-- sesion confirmada la vuelve INDETERMINADA aunque el valor temporal sea identico, porque v1 no
-- declara zona. Solo NULL o UTC_V2 se aceptan por esta via.
-- CULM-001 A.2-10 (F-DOC-017): si cambian fechaHoraInicio o fechaHoraFin respecto de la fila guardada (N6), la sesion no
-- puede cruzarse con otra del grupo o de otro grupo del mismo docente (SES_017, excluida ella misma); un cambio de solo
-- nombre no se valida, asi una sesion con un solape heredado puede seguir renombrandose. Transaccion propia o savepoint.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_sesion_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(50),
    @fechaHoraInicio         DATETIME2,
    @fechaHoraFin            DATETIME2,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @procedenciaTemporal     NVARCHAR(24),
    @idCorrelacionResultado  UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idGrupoSesion UNIQUEIDENTIFIER;
    DECLARE @inicioActual  DATETIME2;
    DECLARE @finActual     DATETIME2;

    -- Ownership transaccional (propia o savepoint bajo transaccion externa)
    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET @idCorrelacionResultado = @idCorrelacionDefecto;

    BEGIN TRY
        -- PASOS 0-1.6: procedencia, correlacion y seguridad antes de consultar la sesión.
        EXEC dbo.usp_validar_sesion_operacion_interno
            @idCorrelacion = @idCorrelacion,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @procedenciaTemporal = @procedenciaTemporal,
            @fechaHoraInicio = @fechaHoraInicio,
            @fechaHoraFin = @fechaHoraFin,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @faseValidacion = 0;

        -- PASO 2: Validar existencia de la sesión con código semántico SES_001
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @idGrupoSesion = grupo
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @idGrupoSesion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Titularidad del docente ejecutor sobre la sesión.
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

        -- PASO 4: conservar la prioridad contractual de entidad antes de fechas.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_operacion_interno
                @idCorrelacion = @idCorrelacion,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @procedenciaTemporal = @procedenciaTemporal,
                @fechaHoraInicio = @fechaHoraInicio,
                @fechaHoraFin = @fechaHoraFin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @faseValidacion = 2;
        END

        -- PASO 5 (CULM-001 A.2-10): transaccion y solape solo si cambia el horario guardado (N6)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_actualizar_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @inicioActual = s.fechaHoraInicio, @finActual = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF @inicioActual IS NULL OR @finActual IS NULL OR @inicioActual <> @fechaHoraInicio OR @finActual <> @fechaHoraFin
            BEGIN
                EXEC dbo.usp_validar_solape_sesion_interno
                    @idGrupo = @idGrupoSesion,
                    @idSesionExcluir = @idSesionDefecto,
                    @fechaHoraInicio = @fechaHoraInicio,
                    @fechaHoraFin = @fechaHoraFin,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            -- Horas y procedencia en la MISMA sentencia (UTC-D06).
            UPDATE dbo.Sesion
            SET nombre = CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE nombre END,
                fechaHoraInicio = @fechaHoraInicio,
                fechaHoraFin = @fechaHoraFin,
                procedenciaTemporal = @procedenciaTemporal
            WHERE id = @idSesionDefecto;
        END

        -- Cierre de la transaccion propia (el rechazo por solape no escribe)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_004', @p_param1 = 'Sesion', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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
        BEGIN
            ROLLBACK TRANSACTION usp_actualizar_sesion;
        END

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001', @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
