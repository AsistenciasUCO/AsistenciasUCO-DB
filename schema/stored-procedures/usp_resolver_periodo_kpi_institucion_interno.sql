USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_resolver_periodo_kpi_institucion_interno]
-- HU133-HU139 (D1): periodo solicitado (PER_001 si no existe) o, por defecto, el mas reciente con grupos habilitados
-- en los programas de la institucion. Devuelve NULL si la institucion no tiene grupos habilitados (no es un error).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_periodo_kpi_institucion_interno]
(
    @idInstitucion       UNIQUEIDENTIFIER,
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
    INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
    INNER JOIN dbo.uv_periodo_academico pa ON pa.id = gp.idPeriodoAcademico
    WHERE p.idInstitucion = @idInstitucion AND gp.grupoEstaHablitado = 1
    ORDER BY pa.fechaInicio DESC, pa.id ASC;
END;
GO
