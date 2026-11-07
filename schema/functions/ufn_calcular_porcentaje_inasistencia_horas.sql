USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.4, DEC-012, DEC-024): porcentaje de inasistencia por horas = 100 * horasFalta / horasDictadas,
-- acotado a [0, 100]. 0 si horasDictadas es NULL o <= 0. Determinista, sin acceso a datos.
CREATE OR ALTER FUNCTION [dbo].[ufn_calcular_porcentaje_inasistencia_horas]
(
    @horasFalta    DECIMAL(12,6),
    @horasDictadas DECIMAL(12,6)
)
RETURNS DECIMAL(5,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CASE
                    WHEN @horasDictadas IS NULL OR @horasDictadas <= 0 OR @horasFalta IS NULL OR @horasFalta <= 0 THEN 0
                    WHEN @horasFalta >= @horasDictadas THEN 100
                    ELSE ROUND(100.0 * @horasFalta / @horasDictadas, 2)
                END AS DECIMAL(5,2));
END;
GO
