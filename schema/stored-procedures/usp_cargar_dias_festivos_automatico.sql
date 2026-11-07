USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cargar_dias_festivos_automatico (CULM-001 B.1; CONTRACT §2.7.4, §3.4) — carga de festivos por el job del backend
-- (CargaFestivosScheduler), sin usuario ejecutor (como usp_rotar_token_matricula_automatico): la bitacora
-- dbo.CargaDiaFestivo queda con usuarioEjecutor NULL. Misma salida y validaciones que usp_cargar_dias_festivos.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cargar_dias_festivos_automatico]
(
    @anio                     INT,
    @festivosJSON             NVARCHAR(MAX),
    @fuente                   NVARCHAR(40),
    @diferenciasCalculoLocal  INT,
    @idCorrelacion            UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @insertados INT = 0, @actualizados INT = 0, @desactivados INT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_internal_cargar_dias_festivos
            @anio = @anio,
            @festivosJSON = @festivosJSON,
            @fuente = @fuente,
            @diferenciasCalculoLocal = @diferenciasCalculoLocal,
            @idCorrelacion = @idCorrelacionDefecto,
            @idUsuarioEjecutor = NULL,
            @festivosInsertados = @insertados OUTPUT,
            @festivosActualizados = @actualizados OUTPUT,
            @festivosDesactivados = @desactivados OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = -1 AND @@TRANCOUNT > 0
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
        anio                    = IIF(@estadoResultado = 1, @anio, NULL),
        totalFestivos           = IIF(@estadoResultado = 1, @insertados + @actualizados, NULL),
        festivosInsertados      = IIF(@estadoResultado = 1, @insertados, NULL),
        festivosActualizados    = IIF(@estadoResultado = 1, @actualizados, NULL),
        festivosDesactivados    = IIF(@estadoResultado = 1, @desactivados, NULL);
END;
GO
