USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_carga_festivos_anio (CULM-001 B.1; CONTRACT §2.7.7, §3.4 punto 5)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET de una fila, sin usuario (lo usa el job
-- CargaFestivosScheduler para decidir si un anio falta por cargar): anio, totalActivos (0 si no hay carga),
-- fuenteUltimaCarga y fechaUltimaCargaUtc (NULL si no hay carga). THROW 51000 si falta la correlacion o el anio.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_carga_festivos_anio]
(
    @anio          INT,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND @anio IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'anio',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SELECT
        anio                = @anio,
        totalActivos        = (SELECT COUNT(1) FROM dbo.uv_dia_festivo df WHERE df.anio = @anio AND df.estaActivo = 1),
        fuenteUltimaCarga   = uc.fuente,
        fechaUltimaCargaUtc = uc.fechaCargaUtc
    FROM (SELECT x = 1) base
    OUTER APPLY (
        SELECT TOP 1 c.fuente, c.fechaCargaUtc
        FROM dbo.uv_carga_dia_festivo c
        WHERE c.anio = @anio AND c.esUltimaCargaAnio = 1
    ) uc;
END;
GO
