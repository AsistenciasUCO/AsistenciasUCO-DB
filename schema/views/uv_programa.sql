USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER    VIEW	[dbo].[uv_programa]
AS
SELECT		pr.id,
			nombrePrograma = pr.nombre,
			pr.estado,
			
			idFacultad = f.id,
			nombreFacultad = f.nombreFacultad,
			idInstitucion = f.idInstitucion,
			nombreInstitucion = f.nombreInstitucion,
			
			idCoordinador = ci.id,
			nombreCoordinador = ci.nombreCompleto,
			
			estaActivoPrograma = pr.estado,
			estaActivoTextoPrograma = IIF(pr.estado = 1, 'SI', 'NO'),

			-- HU076/HU077 (aditivo): tipo, modalidad y jornada
			idTipoPrograma = tp.id,
			nombreTipoPrograma = tp.nombre,
			idModalidad = m.id,
			nombreModalidad = m.nombre,
			idJornada = j.id,
			nombreJornada = j.nombre

FROM		Programa pr
INNER JOIN	uv_facultad f 
ON			pr.facultad = f.id
LEFT JOIN	uv_coordinador_identidad ci 
ON			pr.coordinador = ci.id
LEFT JOIN	uv_tipo_programa tp
ON			pr.tipoDePrograma = tp.id
LEFT JOIN	uv_modalidad m
ON			pr.modalidad = m.id
LEFT JOIN	uv_jornada j
ON			pr.jornada = j.id
GO
