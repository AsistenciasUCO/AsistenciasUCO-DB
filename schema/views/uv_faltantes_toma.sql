USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, HU175, DEC-013): faltantes de una toma = matriculas ACTIVAS (codigoEstadoEstudiante = A) del
-- grupo sin presencia en la toma: sin detalle (tieneRegistro = 0) o con SJC. Excluye a quien tiene AN o EX en la toma.
--   fueMarcadoAlCerrar = 1 si el SJC lo inserto el cierre de la toma (usp_cerrar_toma_asistencia / usp_cerrar_tomas_vencidas
--   registran el SJC con fechaRegistroUtc = fechaCierreUtc de la toma y registradoPorEstudiante = 0); si el docente lo
--   corrige despues, deja de serlo.
CREATE OR ALTER VIEW [dbo].[uv_faltantes_toma]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numeroToma = t.numero,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        nombreCompletoEstudiante = eg.nombreCompletoEstudiante,
        tieneRegistro = CAST(IIF(d.id IS NULL, 0, 1) AS BIT),
        idDetalleAsistencia = d.id,
        codigoRazonCausa = rc.codigo,
        fueMarcadoAlCerrar = CAST(IIF(d.id IS NOT NULL AND rc.codigo = N'SJC' AND d.registradoPorEstudiante = 0
                                      AND t.fechaCierreUtc IS NOT NULL AND d.fechaRegistroUtc = t.fechaCierreUtc, 1, 0) AS BIT)
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.grupo
AND     eg.codigoEstadoEstudiante = N'A'
OUTER APPLY (
        SELECT  TOP 1 da.id, da.razonCausa, da.registradoPorEstudiante, da.fechaRegistroUtc
        FROM    dbo.Asistencia a
        INNER JOIN dbo.DetalleAsistencia da ON da.asistencia = a.id AND da.toma = t.id
        WHERE   a.estudianteGrupo = eg.id AND a.sesion = t.sesion
) d
LEFT JOIN dbo.RazonCausa rc
ON      rc.id = d.razonCausa
WHERE   d.id IS NULL OR rc.codigo NOT IN (N'AN', N'EX');
GO
