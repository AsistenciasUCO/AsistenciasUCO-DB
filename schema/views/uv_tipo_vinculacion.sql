USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_tipo_vinculacion]
AS
SELECT		tv.id,
			tv.codigo,
			tv.nombre,
			estaActivoTipoVinculacion = tv.estado,
			estaActivoTextoTipoVinculacion = IIF(tv.estado = 1, 'SI', 'NO')
FROM		TipoVinculacion tv
GO
