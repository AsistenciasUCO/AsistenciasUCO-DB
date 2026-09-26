USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_razon_causa]
AS
SELECT  id,
		nombre,
		codigo
FROM	RazonCausa
GO
