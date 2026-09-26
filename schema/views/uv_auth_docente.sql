USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_docente]
AS
SELECT  d.id,
        d.idUsuario,
        d.numeroIdentificacion,
        d.nombreCompleto,
        d.estaActivoUsuario,
        d.idInstitucion,
        d.nombreInstitucion,
        d.idFacultad,
        d.nombreFacultad,
        d.idPrograma,
        d.nombrePrograma,
        d.idPlanEstudio,
        d.inpPlanEstudio,
        d.idAsignatura,
        d.nombreAsignatura,
        d.idGrupo,
        d.nombreGrupo,
        d.idPerfil,
        d.codigoPerfil,
        d.nombrePerfil,
        d.estaActivoDocente,
        d.estaActivoTextoDocente
FROM    dbo.uv_docente d
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = d.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano WHERE dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = d.idFacultad
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = d.idPrograma
        )
   OR   d.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO
