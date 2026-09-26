USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_facultad]
AS
SELECT  f.id,
        f.nombreFacultad,
        f.idInstitucion,
        f.nombreInstitucion,
        f.idDecano,
        f.nombreCompletoDecano,
        f.estaActivaFacultad,
        f.estaActivaTextoFacultad
FROM    dbo.uv_facultad f
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = f.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.idDecano = d.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c 
            INNER JOIN dbo.Programa pr ON c.id = pr.coordinador 
            WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Programa pr ON pe.programa = pr.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.facultad = f.id
        )
        );
GO
