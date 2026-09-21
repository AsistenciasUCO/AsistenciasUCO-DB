USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_grupo]
AS
SELECT  g.id,
        g.idPeriodoAcademico,
        g.fechaInicioPeriodoAcademico,
        g.fechaFinPeriodoAcademico,
        g.idAsignatura,
        g.nombreAsignatura,
        g.idDocente,
        g.codigo,
        g.nombre,
        g.capacidadMaximaPermitida,
        g.estudiantesActivos,
        g.estudiantesFinalizados,
        g.estudiantesCanceladosVoluntad,
        g.estudiantesCanceladosInasistencia,
        g.cuposDisponibles,
        g.grupoEstaHablitado,
        g.grupoEstaHablitadoTexto
FROM    dbo.uv_grupo g
INNER JOIN dbo.Asignatura a ON g.idAsignatura = a.id
INNER JOIN dbo.SemestrePlanEstudio spe ON a.semestrePlanEstudio = spe.id
INNER JOIN dbo.PlanEstudio pe ON spe.planEstudio = pe.id
INNER JOIN dbo.Programa pr ON pe.programa = pr.id
INNER JOIN dbo.Facultad f ON pr.facultad = f.id
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NULL
   OR   EXISTS (
            SELECT 1 FROM dbo.Administrador adm WHERE adm.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND adm.institucion = f.institucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.decano = d.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.coordinador = c.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.idDocente = doc.id
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Estudiante e INNER JOIN dbo.EstudianteGrupo eg ON e.id = eg.estudiante WHERE e.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND eg.grupo = g.id
        );
GO
