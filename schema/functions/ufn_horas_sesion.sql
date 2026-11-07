USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012): horas de una sesion = minutos entre inicio y fin / 60. 0 si alguna fecha es NULL o
-- si el fin no es posterior al inicio. Determinista, sin acceso a datos (inlineable).
CREATE OR ALTER FUNCTION [dbo].[ufn_horas_sesion]
(
    @fechaHoraInicio DATETIME2,
    @fechaHoraFin    DATETIME2
)
RETURNS DECIMAL(12,6)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CASE
                    WHEN @fechaHoraInicio IS NULL OR @fechaHoraFin IS NULL OR @fechaHoraFin <= @fechaHoraInicio THEN 0
                    ELSE CAST(DATEDIFF(MINUTE, @fechaHoraInicio, @fechaHoraFin) AS DECIMAL(12,6)) / 60
                END AS DECIMAL(12,6));
END;
GO
