USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- HU070: unica implementacion de la regla de permanencia.
-- REGULAR < UMBRAL_ALERTA_ADVERTENCIA <= RIESGO < UMBRAL_ALERTA_PERDIDA <= PERDIDA (CatalogoParametro, grupo ASISTENCIA).
-- La matricula cancelada por inasistencia (CI) es PERDIDA. Si falta un umbral devuelve NULL: jamas asume un valor.
-- =============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_clasificar_permanencia]
(
    @porcentaje             DECIMAL(5,2),
    @codigoEstadoEstudiante NVARCHAR(10)
)
RETURNS NVARCHAR(10)
AS
BEGIN
    DECLARE @advertencia DECIMAL(5,2) = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2));
    DECLARE @perdida     DECIMAL(5,2) = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2));
    DECLARE @resultado   NVARCHAR(10) = NULL;

    IF @advertencia IS NOT NULL AND @perdida IS NOT NULL
    BEGIN
        SET @resultado = CASE
            WHEN @codigoEstadoEstudiante = N'CI' THEN N'PERDIDA'
            WHEN @porcentaje >= @perdida THEN N'PERDIDA'
            WHEN @porcentaje >= @advertencia THEN N'RIESGO'
            ELSE N'REGULAR'
        END;
    END

    RETURN @resultado;
END;
GO
