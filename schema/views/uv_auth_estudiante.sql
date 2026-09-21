USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_estudiante]
AS
SELECT  e.id,
        e.idUsuario,
        e.numeroIdentificacion,
        e.nombreCompleto,
        e.estaActivoUsuario,
        e.idInstitucion,
        e.nombreInstitucion,
        e.idFacultad,
        e.nombreFacultad,
        e.idPrograma,
        e.nombrePrograma,
        e.idPlanEstudio,
        e.inpPlanEstudio,
        e.idAsignatura,
        e.nombreAsignatura,
        e.idGrupo,
        e.nombreGrupo,
        e.idPerfil,
        e.codigoPerfil,
        e.nombrePerfil,
        e.estaActivoEstudiante,
        e.estaActivoTextoEstudiante
FROM    dbo.uv_estudiante e
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NULL
   OR   EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = e.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano WHERE dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = e.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = e.idPrograma
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Docente doc INNER JOIN dbo.Grupo g ON doc.id = g.docente WHERE doc.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND g.id = e.idGrupo
        )
   OR   e.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto();
GO
