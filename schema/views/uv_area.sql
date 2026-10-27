USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_area]
AS
SELECT  id,
		nombre,
		codigo,
		estaActivaArea = estado,
		estaActivaTextoArea = IIF(estado = 1, 'SI', 'NO')
FROM	Area
GO
