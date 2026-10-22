USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_tipo_programa]
AS
SELECT  id,
		nombre,
		codigo,
		estaActivoTipoPrograma =  estado,
		estaActivoTextoTipoPrograma = IIF(estado = 1, 'SI', 'NO'),
		codigo
FROM	TipoPrograma
GO
