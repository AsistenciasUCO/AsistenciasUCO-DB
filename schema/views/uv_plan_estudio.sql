USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_plan_estudio]
AS
SELECT		pe.id,
			idPrograma = pr.id,
			nombrePrograma = pr.nombrePrograma,
			inp = pe.inp,
			-- HU081: el plan es activo solo si su programa esta activo y el propio plan (PlanEstudio.estado) tambien.
			estaActivoPlanEstudio = IIF(pr.estaActivoPrograma = 0 OR pe.estado = 0, 0, 1),
			estaActivoTextoPlanEstudio = IIF(pr.estaActivoPrograma = 0 OR pe.estado = 0, 'NO', 'SI'),
			justificacionEstado =	CASE
										WHEN pr.estaActivoPrograma = 0 THEN 'Plan Estudio inactivo porque programa est? inactivo.'
										WHEN pe.estado = 0 THEN 'Plan Estudio inactivado por el coordinador del programa.'
										ELSE 'Plan Estudio activo.'
									END

FROM		PlanEstudio pe
INNER JOIN	uv_programa pr
ON			pe.programa = pr.id
GO
