USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_decano]
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
        d.idPerfil,
        d.codigoPerfil,
        d.nombrePerfil,
        d.estaActivoDecano,
        d.estaActivoTextoDecano
FROM    dbo.uv_decano d
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL   -- fail closed: sin contexto => 0 filas
   AND  (
            EXISTS (
            SELECT 1 FROM dbo.Administrador a WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = d.idInstitucion
        )
   OR   d.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO
