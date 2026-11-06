USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU155 (2026-11-04): agrega `codigo` (aditivo) para la consulta de estados del sistema; catalogo de solo consulta.
CREATE OR ALTER  VIEW [dbo].[uv_estado]
AS
SELECT  id,
		nombre,
		codigo
FROM	Estado
GO
