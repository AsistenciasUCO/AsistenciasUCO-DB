USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPrograma = gp.idPrograma,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo, sesionesEjecutadas = COUNT(*)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  a.idEstudianteGrupo,
                    asistencias = SUM(IIF(da.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(da.asistio = 0 AND da.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(da.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_asistencia a
            INNER JOIN dbo.uv_detalle_asistencia da ON da.idAsistencia = a.id
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = a.idSesion AND c.estaVencida = 1
            GROUP BY a.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT porcentaje = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0, 100.0 * ISNULL(de.faltas, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2))
          ) p
GO
