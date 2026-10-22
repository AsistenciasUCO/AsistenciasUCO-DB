USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU078: relacion grupo -> programa (via asignatura, semestre del plan y plan de estudio) y su habilitacion
-- en el periodo vigente (uv_grupo.grupoEstaHablitado). Base de la regla D4 (no desactivar con grupos activos).
CREATE OR ALTER VIEW [dbo].[uv_grupo_programa]
AS
SELECT  idGrupo = g.id,
        idPrograma = pe.programa,
        idPeriodoAcademico = g.idPeriodoAcademico,
        grupoEstaHablitado = g.grupoEstaHablitado
FROM    uv_grupo g
INNER JOIN Asignatura a ON g.idAsignatura = a.id
INNER JOIN SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
INNER JOIN PlanEstudio pe ON spe.planEstudio = pe.id
GO
