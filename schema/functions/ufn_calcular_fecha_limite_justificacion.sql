USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_calcular_fecha_limite_justificacion (CULM-001 D.1, HU026B; CONTRACT §0 [SUPUESTO-D-01], §2.2)
--
-- Limite EXCLUSIVO (UTC) para radicar una excusa: la medianoche local (TIEMPO/ZONA_HORARIA_SQLSERVER) del dia
--   fecha local de fin de la sesion + N + 1,   N = ASISTENCIA/DIAS_LIMITE_JUSTIFICACION.
-- Una radicacion se admite mientras SYSUTCDATETIME() < limite. Dias calendario locales completos: una sesion que termina
-- a las 23:30 no pierde un dia. Ejemplo (N = 5, Bogota): fin el miercoles 2026-11-04 a las 08:00 => limite 2026-11-10 00:00
-- local, es decir se puede justificar hasta el lunes 2026-11-09 a las 23:59:59.
-- Devuelve NULL si @fechaHoraFinSesionUtc es NULL, si N falta, no es entero o es negativo, o si la zona falta o no existe
-- en sys.time_zone_info: el llamador decide (REV_025). Sin escrituras. El texto vacio del parametro cuenta como ausente
-- (ufn_obtener_parametro devuelve '' para un parametro inexistente y CAST('' AS INT) seria 0).
-- ============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_fecha_limite_justificacion] (
    @fechaHoraFinSesionUtc DATETIME2(7)
)
RETURNS DATETIME2(7)
AS
BEGIN
    IF @fechaHoraFinSesionUtc IS NULL
        RETURN NULL;

    DECLARE @textoDias NVARCHAR(MAX) = dbo.ufn_obtener_parametro_texto(NULL, 'ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION');
    DECLARE @textoZona NVARCHAR(MAX) = dbo.ufn_obtener_parametro_texto(NULL, 'TIEMPO', 'ZONA_HORARIA_SQLSERVER');
    DECLARE @dias INT = TRY_CAST(@textoDias AS INT);

    IF @textoDias IS NULL OR @textoDias = N'' OR @dias IS NULL OR @dias < 0
        RETURN NULL;
    IF @textoZona IS NULL OR @textoZona = N'' OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE name = @textoZona)
        RETURN NULL;

    DECLARE @zona NVARCHAR(128) = CAST(@textoZona AS NVARCHAR(128));
    DECLARE @fechaLocalFin DATE = CAST((@fechaHoraFinSesionUtc AT TIME ZONE 'UTC') AT TIME ZONE @zona AS DATE);

    -- Defensa de desbordamiento: el limite debe seguir siendo una fecha valida.
    IF @dias + 1 > DATEDIFF(DAY, @fechaLocalFin, CAST('9999-12-30' AS DATE))
        RETURN NULL;

    DECLARE @limiteLocal DATETIME2(7) = CAST(DATEADD(DAY, @dias + 1, @fechaLocalFin) AS DATETIME2(7));
    RETURN CAST((@limiteLocal AT TIME ZONE @zona) AT TIME ZONE 'UTC' AS DATETIME2(7));
END;
GO
