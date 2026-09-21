USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_institucion]
AS
SELECT  i.id,
        i.nombre,
        i.estaActivaInstitucion,
        i.estaActivaTextoInstitucion
FROM    dbo.uv_institucion i
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NULL
   OR   EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d 
            INNER JOIN dbo.Facultad f ON d.id = f.decano 
            WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Programa pr ON pe.programa = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e
            INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Programa pr ON pe.programa = pr.id
            INNER JOIN dbo.Facultad f ON pr.facultad = f.id
            WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.institucion = i.id
        );
GO
