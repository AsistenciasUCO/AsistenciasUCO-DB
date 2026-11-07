USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_aplicar_festivos_periodo (CULM-001 B.1; CONTRACT §2.7.5)
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + gruposProcesados, sesionesCanceladas,
-- sesionesConAsistencia (NULL si estadoResultado = 0).
-- El ADMINISTRADOR aplica los festivos (@soloFuturas = 1) a los grupos de un periodo de su institucion, o a los grupos
-- de los periodos de su institucion que se cruzan con un anio. Exactamente uno de los dos filtros (FES_006); periodo
-- inexistente FES_007, de otra institucion SEC_002; anio fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO FES_001.
-- Una transaccion por grupo (usp_internal_aplicar_festivos_grupos): si algun grupo falla el resultado es FES_009.
-- Lo invoca el backend tras cada recarga del anio ([SUPUESTO-B-21]).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_aplicar_festivos_periodo]
(
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @anio               INT = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @anioMinimo INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MINIMO');
    DECLARE @anioMaximo INT = dbo.ufn_obtener_parametro_int(NULL, 'FESTIVOS', 'ANIO_MAXIMO');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idInstitucionPeriodo UNIQUEIDENTIFIER;
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

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
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

        -- Exactamente uno de los dos filtros (FES_006)
        IF @estadoResultado = 1 AND ((@idPeriodoAcademico IS NULL AND @anio IS NULL) OR (@idPeriodoAcademico IS NOT NULL AND @anio IS NOT NULL))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_006',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Filtro por periodo: existente (FES_007) y de la institucion del administrador (SEC_002)
        IF @estadoResultado = 1 AND @idPeriodoAcademico IS NOT NULL
        BEGIN
            SELECT @idInstitucionPeriodo = pa.idInstitucion FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoAcademico;

            IF @idInstitucionPeriodo IS NULL
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(36), @idPeriodoAcademico);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'FES_007', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                EXEC dbo.usp_validar_titularidad_jerarquica_interno
                    @idUsuario = @idUsuarioEjecutorDefecto,
                    @idEntidadPadre = @idInstitucionPeriodo,
                    @tipoEntidadPadre = 'INSTITUCION',
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

        END

        -- Filtro por anio: grupos de los periodos de la institucion del administrador que se cruzan con el anio
        IF @estadoResultado = 1 AND @anio IS NOT NULL
        BEGIN
            IF @anioMinimo IS NULL OR @anioMaximo IS NULL OR @anio < @anioMinimo OR @anio > @anioMaximo
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(20), @anio);
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'FES_001', @p_param1 = @p1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_aplicar_festivos_grupos
                @idPeriodoAcademico = @idPeriodoAcademico,
                @anio = @anio,
                @idUsuarioAdministrador = @idUsuarioEjecutorDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
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
                SET @p1 = ISNULL(CONVERT(NVARCHAR(36), @idPeriodoAcademico), CONVERT(NVARCHAR(20), @anio));
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
