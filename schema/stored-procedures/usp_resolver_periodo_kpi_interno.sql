USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_periodo_kpi_interno]
-- HU065-HU070 (D8): periodo explicito (debe existir: PER_001) o el vigente del programa (grupo habilitado); NULL si no hay vigente.
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_periodo_kpi_interno]
(
    @idPrograma          UNIQUEIDENTIFIER,
    @idPeriodoSolicitado UNIQUEIDENTIFIER = NULL,
    @idPeriodo           UNIQUEIDENTIFIER OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);

    SET @idPeriodo = NULL;

    IF @idPeriodoSolicitado IS NOT NULL
    BEGIN
        SELECT @idPeriodo = pa.id FROM dbo.uv_periodo_academico pa WHERE pa.id = @idPeriodoSolicitado;
        IF @idPeriodo IS NULL
        BEGIN
            SET @msgP1 = CAST(CONVERT(NVARCHAR(36), @idPeriodoSolicitado) AS NVARCHAR(500));
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PER_001',
                @p_param1 = @msgP1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        RETURN;
    END

    SELECT TOP 1 @idPeriodo = gp.idPeriodoAcademico
    FROM dbo.uv_grupo_programa gp
    INNER JOIN dbo.uv_periodo_academico pa ON pa.id = gp.idPeriodoAcademico
    WHERE gp.idPrograma = @idPrograma AND gp.grupoEstaHablitado = 1
    ORDER BY pa.fechaInicio DESC, pa.id ASC;
END;
GO
