USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_generar_sesiones_grupo_v2 (CULM-001 B.1; CONTRACT §2.7.6) — generacion de sesiones con festivos cancelados.
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + sesionesCanceladasPorFestivo,
-- sesionesFestivoConAsistencia (NULL si estadoResultado = 0).
--
-- Fase 1: INSERT INTO @resultadoGeneracion EXEC dbo.usp_generar_sesiones_grupo (congelado: su texto no cambia ni se
--         invoca de otra forma). Sus errores de negocio (RBAC, titularidad, horarios, fechas, zona) ocurren antes de su
--         BEGIN TRANSACTION y no hacen ROLLBACK: su tupla llega intacta y se devuelve tal cual (paridad con el v1).
-- Fase 2: transaccion propia o SAVE TRANSACTION sp_generar_sesiones_v2 -> usp_internal_aplicar_festivos_grupo
--         (@soloFuturas = 0: toda sesion del grupo en festivo nace cancelada; las que tienen asistencia se reportan).
--         Exito: mensaje del SP congelado (GEN_004) + conteos.
-- CATCH (R2-1): la reversion depende solo de @@TRANCOUNT a la entrada (@trancountEntrada):
--   * = 0: ROLLBACK si @@TRANCOUNT > 0 y tupla SYS_001 con ufn_obtener_detalle_error (traduce el 3915 del ROLLBACK
--     del SP congelado dentro del INSERT ... EXEC o cualquier error de las fases 1 y 2). Al salir @@TRANCOUNT = 0.
--   * > 0: THROW sin ROLLBACK y sin tupla: con transaccion externa el BEGIN TRANSACTION del SP congelado queda
--     abierto (XACT_STATE() = -1) y solo el llamador puede revertir.
-- Las dos fases son idempotentes: si la segunda falla, repetir la llamada completa deja el estado correcto.
-- Como usa INSERT ... EXEC, este SP no puede anidarse en otro INSERT ... EXEC (error 8164).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_generar_sesiones_grupo_v2]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @trancountEntrada     INT = @@TRANCOUNT;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 0;
    DECLARE @idCorrelacionResultado  UNIQUEIDENTIFIER = @idCorrelacionDefecto;

    DECLARE @transaccionPropia     BIT = 0;
    DECLARE @canceladasPorFestivo  INT = 0;
    DECLARE @festivoConAsistencia  INT = 0;
    DECLARE @mensajeUsuarioFase2   NVARCHAR(4000);
    DECLARE @mensajeTecnicoFase2   NVARCHAR(4000);
    DECLARE @estadoFase2           BIT;

    DECLARE @resultadoGeneracion TABLE (
        idCorrelacion           UNIQUEIDENTIFIER NULL,
        mensajeUsuarioResultado NVARCHAR(4000)   NULL,
        mensajeTecnicoResultado NVARCHAR(4000)   NULL,
        estadoResultado         BIT              NULL
    );
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- FASE 1: generacion con el SP congelado
        INSERT INTO @resultadoGeneracion (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado)
        EXEC dbo.usp_generar_sesiones_grupo @idGrupo = @idGrupo, @idCorrelacion = @idCorrelacion, @idUsuarioEjecutor = @idUsuarioEjecutor;

        SELECT TOP 1
            @idCorrelacionResultado = r.idCorrelacion,
            @mensajeUsuarioResultado = r.mensajeUsuarioResultado,
            @mensajeTecnicoResultado = r.mensajeTecnicoResultado,
            @estadoResultado = r.estadoResultado
        FROM @resultadoGeneracion r;

        -- FASE 2: festivos de las sesiones del grupo (solo si la fase 1 fue exitosa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
                SAVE TRANSACTION sp_generar_sesiones_v2;

            EXEC dbo.usp_internal_aplicar_festivos_grupo
                @idGrupo = @idGrupoDefecto,
                @soloFuturas = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @sesionesCanceladas = @canceladasPorFestivo OUTPUT,
                @sesionesConAsistencia = @festivoConAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioFase2 OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoFase2 OUTPUT,
                @estadoResultado = @estadoFase2 OUTPUT;

            IF XACT_STATE() = -1
                THROW 51000, @mensajeTecnicoFase2, 1;

            IF @estadoFase2 = 0
            BEGIN
                -- Rechazo del nucleo sin escrituras: se informa su mensaje (la fase 1 ya quedo aplicada e idempotente)
                SELECT @mensajeUsuarioResultado = @mensajeUsuarioFase2, @mensajeTecnicoResultado = @mensajeTecnicoFase2, @estadoResultado = 0;
            END

            IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        IF @trancountEntrada > 0
            THROW;

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @idCorrelacionResultado = @idCorrelacionDefecto;
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion                 = @idCorrelacionResultado,
        mensajeUsuarioResultado       = @mensajeUsuarioResultado,
        mensajeTecnicoResultado       = @mensajeTecnicoResultado,
        estadoResultado               = @estadoResultado,
        sesionesCanceladasPorFestivo  = IIF(@estadoResultado = 1, @canceladasPorFestivo, NULL),
        sesionesFestivoConAsistencia  = IIF(@estadoResultado = 1, @festivoConAsistencia, NULL);
END;
GO
