USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- P5/HU147 (2026-11-04, aditivo): expone el codigo (BAS, INS, ESP), que deciden la oferta (HU008) y la matricula.
CREATE OR ALTER  VIEW [dbo].[uv_componente]
AS
SELECT  id,
		nombre,
		codigo
FROM	Componente
GO
