USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_coordinador]
AS
SELECT		ci.id,
			ci.idUsuario,
			ci.numeroIdentificacion,
			ci.nombreCompleto,
			ci.estaActivoUsuario,

			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,
			idFacultad = pr.idFacultad,
			nombreFacultad = pr.nombreFacultad,
			idInstitucion = pr.idInstitucion,
			nombreInstitucion = pr.nombreInstitucion,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoCoordinador = IIF(ci.estaActivoUsuario = 1 AND (pr.id IS NULL OR pr.estaActivoPrograma = 1), 1, 0),
			estaActivoTextoCoordinador = IIF(ci.estaActivoUsuario = 1 AND (pr.id IS NULL OR pr.estaActivoPrograma = 1), 'SI', 'NO')

FROM		uv_coordinador_identidad ci
LEFT JOIN	uv_programa pr 
ON			ci.id = pr.idCoordinador
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'CD') p
GO
