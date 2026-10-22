USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Vista con ambito (fail-closed): sin contexto de ejecutor => 0 filas. Admin de la institucion, decano de
-- la facultad, coordinador del programa de la fila, o el propio docente.
CREATE OR ALTER VIEW [dbo].[uv_auth_docente_programa]
AS
SELECT  d.idDocentePrograma,
        d.idDocente,
        d.idUsuario,
        d.idTipoIdentificacion,
        d.codigoTipoIdentificacion,
        d.numeroIdentificacion,
        d.primerNombre,
        d.segundoNombre,
        d.primerApellido,
        d.segundoApellido,
        d.nombreCompleto,
        d.correo,
        d.idPrograma,
        d.nombrePrograma,
        d.idFacultad,
        d.nombreFacultad,
        d.idInstitucion,
        d.idTipoVinculacion,
        d.codigoTipoVinculacion,
        d.nombreTipoVinculacion,
        d.fechaVinculacionUtc,
        d.estaActivoVinculacion,
        d.estaActivoUsuario,
        d.estaActivoDocentePrograma,
        d.totalGruposPrograma
FROM    dbo.uv_docente_programa d
WHERE   dbo.ufn_obtener_usuario_ejecutor_contexto() IS NOT NULL
   AND  (
            EXISTS (
                SELECT 1 FROM dbo.Administrador a
                WHERE a.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND a.institucion = d.idInstitucion
            )
        OR  EXISTS (
                SELECT 1 FROM dbo.Decano dec INNER JOIN dbo.Facultad f ON dec.id = f.decano
                WHERE dec.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND f.id = d.idFacultad
            )
        OR  EXISTS (
                SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa pr ON c.id = pr.coordinador
                WHERE c.usuario = dbo.ufn_obtener_usuario_ejecutor_contexto() AND pr.id = d.idPrograma
            )
        OR  d.idUsuario = dbo.ufn_obtener_usuario_ejecutor_contexto()
        );
GO
