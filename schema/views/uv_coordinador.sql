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

			-- HU121/HU122 (D2): un coordinador sin programa conserva su facultad (Coordinador.facultad)
			idFacultad = fa.id,
			nombreFacultad = fa.nombreFacultad,
			idInstitucion = fa.idInstitucion,
			nombreInstitucion = fa.nombreInstitucion,

			idPerfil = p.id,
			codigoPerfil = p.codigo,
			nombrePerfil = p.nombre,

			estaActivoCoordinador = IIF(ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 AND (pr.id IS NULL OR pr.estaActivoPrograma = 1), 1, 0),
			estaActivoTextoCoordinador = IIF(ci.estaActivoUsuario = 1 AND ci.estaActivoRolCoordinador = 1 AND (pr.id IS NULL OR pr.estaActivoPrograma = 1), 'SI', 'NO'),

			-- HU121/HU122: datos editables y estado del rol
			ci.primerNombre,
			ci.segundoNombre,
			ci.primerApellido,
			ci.segundoApellido,
			ci.correo,
			ci.estaActivoRolCoordinador

FROM		uv_coordinador_identidad ci
LEFT JOIN	uv_programa pr
ON			ci.id = pr.idCoordinador
LEFT JOIN	uv_facultad fa
ON			fa.id = COALESCE(pr.idFacultad, ci.idFacultadCoordinador)
CROSS JOIN	(SELECT TOP 1 id, codigo, nombre FROM uv_perfil WHERE codigo = 'CD') p
GO
