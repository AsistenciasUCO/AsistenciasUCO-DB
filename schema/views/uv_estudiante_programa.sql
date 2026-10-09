USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER  VIEW [dbo].[uv_estudiante_programa]
AS
SELECT  id = ep.id,
    
        idEstudiante = ei.id,
        nombreEstudiante = ei.nombreCompleto,
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma

-- Identidad estable: una fila por EstudiantePrograma.id.
-- uv_estudiante expande estudiante x grupo x asignatura x programa y multiplicaba la fila.
FROM		EstudiantePrograma ep
INNER JOIN	uv_estudiante_identidad ei
ON          ep.estudiante = ei.id
INNER JOIN	uv_programa p   
ON          ep.programa = p.id
GO
