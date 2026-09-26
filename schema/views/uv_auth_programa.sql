USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_programa]
AS
SELECT  p.id,
        p.nombrePrograma,
        p.estado,
        p.idFacultad,
        p.nombreFacultad,
        p.idInstitucion,
        p.nombreInstitucion,
        p.idCoordinador,
        p.nombreCoordinador,
        p.estaActivoPrograma,
        p.estaActivoTextoPrograma
FROM    dbo.uv_programa p
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = p.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d INNER JOIN dbo.Facultad f ON d.id = f.decano WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = p.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND p.idCoordinador = c.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc
            INNER JOIN dbo.Grupo g ON doc.id = g.docente
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
            WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pe.programa = p.id
        )
        );
GO
