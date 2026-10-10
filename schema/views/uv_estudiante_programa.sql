USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- MAINT-003K: una fila EstudiantePrograma = una fila de la vista. uv_estudiante tiene una fila por matricula/grupo,
-- por lo que unirla directamente multiplicaba cada EstudiantePrograma por el numero de grupos del estudiante.
-- Se une la identidad distinta (id, nombreCompleto) de uv_estudiante: misma semantica de presencia (solo estudiantes
-- con contexto academico), mismas 4 columnas y tipos, sin duplicados por estudiantes multigrupo.
CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,
    
        idEstudiante = e.id,
        nombreEstudiante = e.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma

FROM		EstudiantePrograma ep
INNER JOIN	(SELECT DISTINCT id, nombreCompleto FROM uv_estudiante) e 
ON          ep.estudiante = e.id
INNER JOIN	uv_programa p   
ON          ep.programa = p.id
GO
