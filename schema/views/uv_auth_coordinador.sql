USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_coordinador]
AS
SELECT  c.id,
        c.idUsuario,
        c.numeroIdentificacion,
        c.nombreCompleto,
        c.estaActivoUsuario,
        c.idPrograma,
        c.nombrePrograma,
        c.idFacultad,
        c.nombreFacultad,
        c.idInstitucion,
        c.nombreInstitucion,
        c.idPerfil,
        c.codigoPerfil,
        c.nombrePerfil,
        c.estaActivoCoordinador,
        c.estaActivoTextoCoordinador
FROM    dbo.uv_coordinador c
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = c.idInstitucion
        )
   OR   EXISTS (
            SELECT 1 FROM dbo.Decano d INNER JOIN dbo.Facultad f ON d.id = f.decano WHERE d.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = c.idFacultad
        )
   OR   c.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO
