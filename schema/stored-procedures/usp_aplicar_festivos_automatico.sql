USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_aplicar_festivos_automatico (CULM-001 B.1; CONTRACT §2.7.5, [SUPUESTO-B-21])
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + gruposProcesados, sesionesCanceladas,
-- sesionesConAsistencia (NULL si estadoResultado = 0).
-- Lo invoca el job del backend (sin usuario) tras cada carga de un anio: aplica los festivos (@soloFuturas = 1) a todos
-- los grupos con sesiones cuya fecha local (TIEMPO/ZONA_HORARIA_SQLSERVER) cae en el anio. Una transaccion por grupo;
-- si algun grupo falla el resultado es FES_009. Anio fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO: FES_001.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_aplicar_festivos_automatico]
(
    @anio          INT,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @anioMinimo INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MINIMO');
    DECLARE @anioMaximo INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MAXIMO');
    DECLARE @zonaHorariaSqlServer SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @gruposProcesados INT = 0, @canceladas INT = 0, @conAsistencia INT = 0, @gruposConError INT = 0;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500), @mensajeUsuarioExito NVARCHAR(4000);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@anio IS NULL OR @anioMinimo IS NULL OR @anioMaximo IS NULL OR @anio < @anioMinimo OR @anio > @anioMaximo)
        BEGIN
            SET @p1 = ISNULL(CONVERT(NVARCHAR(20), @anio), N'NULL');
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_001', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
           AND (@zonaHorariaSqlServer IS NULL OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_aplicar_festivos_grupos
                @idPeriodoAcademico = NULL,
                @anio = @anio,
                @idUsuarioAdministrador = NULL,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @gruposProcesados = @gruposProcesados OUTPUT,
                @sesionesCanceladas = @canceladas OUTPUT,
                @sesionesConAsistencia = @conAsistencia OUTPUT,
                @gruposConError = @gruposConError OUTPUT;

            IF @gruposConError > 0
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(20), @gruposConError);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'FES_009', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SELECT @p1 = CONVERT(NVARCHAR(20), @canceladas), @p2 = CONVERT(NVARCHAR(20), @conAsistencia);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'FES_008', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioExito OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @p1 = CONVERT(NVARCHAR(20), @anio);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'FES_008', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, N' Grupos: ', @gruposProcesados, N'. Canceladas: ', @canceladas,
                                                      N'. Con asistencia: ', @conAsistencia, N'. Correlacion: ', @idCorrelacionDefecto);
            END
        END
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
        gruposProcesados        = IIF(@estadoResultado = 1, @gruposProcesados, NULL),
        sesionesCanceladas      = IIF(@estadoResultado = 1, @canceladas, NULL),
        sesionesConAsistencia   = IIF(@estadoResultado = 1, @conAsistencia, NULL);
END;
GO
