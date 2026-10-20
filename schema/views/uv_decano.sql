USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW [dbo].[uv_decano]
AS
SELECT		di.id,
			di.idUsuario,
			di.numeroIdentificacion,
			di.nombreCompleto,
			di.estaActivoUsuario,			
			idInstitucion = f.idInstitucion,
			nombreInstitucion = f.nombreInstitucion,
			idFacultad = f.id,
			nombreFacultad = f.nombreFacultad,
			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,
			estaActivoDecano = IIF(di.estaActivoUsuario = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 1, 0),
			estaActivoTextoDecano = IIF(di.estaActivoUsuario = 1 AND (f.id IS NULL OR f.estaActivaFacultad = 1), 'SI', 'NO')

FROM		uv_decano_identidad di
LEFT JOIN   uv_facultad f 
ON			di.id = f.idDecano
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'DE') p
GO
