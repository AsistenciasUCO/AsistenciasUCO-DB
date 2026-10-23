USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU062/HU089: una fila por vinculo (docente, programa). No depende de los grupos (un docente recien
-- vinculado aparece con totalGruposPrograma = 0). uv_docente y uv_auth_docente no cambian.
CREATE OR ALTER VIEW [dbo].[uv_docente_programa]
AS
SELECT		idDocentePrograma = dp.id,
			idDocente = di.id,
			di.idUsuario,

			idTipoIdentificacion = u.idTipoIdentificacion,
			codigoTipoIdentificacion = u.TipoIdentificacion,
			u.numeroIdentificacion,
			u.primerNombre,
			u.segundoNombre,
			u.primerApellido,
			u.segundoApellido,
			u.nombreCompleto,
			u.correo,

			idPrograma = pr.id,
			pr.nombrePrograma,
			pr.idFacultad,
			pr.nombreFacultad,
			pr.idInstitucion,

			idTipoVinculacion = tv.id,
			codigoTipoVinculacion = tv.codigo,
			nombreTipoVinculacion = tv.nombre,

			dp.fechaVinculacionUtc,
			estaActivoVinculacion = dp.estado,
			estaActivoUsuario = u.estaActivoUsuario,
			estaActivoDocentePrograma = IIF(dp.estado = 1 AND u.estaActivoUsuario = 1 AND pr.estaActivoPrograma = 1, 1, 0),

			totalGruposPrograma = (
				SELECT	COUNT(DISTINCT x.idGrupo)
				FROM	uv_docente x
				WHERE	x.id = di.id AND x.idPrograma = pr.id
			)
FROM		DocentePrograma dp
INNER JOIN	uv_docente_identidad di
ON			dp.docente = di.id
INNER JOIN	uv_usuario u
ON			di.idUsuario = u.id
INNER JOIN	uv_programa pr
ON			dp.programa = pr.id
INNER JOIN	uv_tipo_vinculacion tv
ON			dp.tipoVinculacion = tv.id
GO
