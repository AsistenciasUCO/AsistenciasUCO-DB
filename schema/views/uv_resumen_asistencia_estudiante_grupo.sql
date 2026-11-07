USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
-- CULM-001 B.2 (CONTRACT §2.6, §2.9, DEC-012, DEC-024, NB-2): inasistencia por HORAS conservando los nombres.
--   sesionesEjecutadas: sesiones vencidas, con registro (Asistencia o TomaAsistencia) y no canceladas (sin cambio de nombre).
--   asistencias / faltasSinJustaCausa / excusas: pasan a contar TOMAS (con una toma por sesion = sesiones, igual que antes).
--   tomasDictadas / horasDictadas: tomas y horas (ufn_horas_sesion) de esas mismas sesiones, sin mirar el estado de la toma.
--   horasAsistidas / horasFalta / horasExcusa: suma de uv_asistencia_sesion_horas en esas sesiones; horasSinRegistro =
--   horasDictadas - las tres (nunca negativo).
--   porcentajeInasistencia = ufn_calcular_porcentaje_inasistencia_horas(horasFalta, horasDictadas); codigoPermanencia sobre ese
--   porcentaje (ufn_clasificar_permanencia sin cambio). porcentajeInasistenciaSesiones = formula anterior por sesiones
--   (sesionesConFaltaSinJustaCausa / sesionesEjecutadas), solo trazabilidad. umbralAdvertencia / umbralPerdida: parametros.
--   sesionesAsistidas / sesionesConFaltaSinJustaCausa / sesionesConExcusa: sesiones por estado consolidado (consumidores
--   diferidos a D).
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
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante),
        tomasDictadas = ISNULL(se.tomasDictadas, 0),
        horasDictadas = hd.horasDictadas,
        horasAsistidas = hd.horasAsistidas,
        horasFalta = hd.horasFalta,
        horasExcusa = hd.horasExcusa,
        horasSinRegistro = hd.horasSinRegistro,
        porcentajeAsistenciaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasAsistidas, hd.horasDictadas),
        porcentajeExcusaHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasExcusa, hd.horasDictadas),
        porcentajeSinRegistroHoras = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasSinRegistro, hd.horasDictadas),
        porcentajeInasistenciaSesiones = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0,
                                                  100.0 * ISNULL(hs.sesionesConFalta, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2)),
        umbralAdvertencia = u.umbralAdvertencia,
        umbralPerdida = u.umbralPerdida,
        sesionesAsistidas = ISNULL(hs.sesionesAsistidas, 0),
        sesionesConFaltaSinJustaCausa = ISNULL(hs.sesionesConFalta, 0),
        sesionesConExcusa = ISNULL(hs.sesionesConExcusa, 0)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo,
                    sesionesEjecutadas = COUNT(*),
                    tomasDictadas = SUM(c.totalTomas),
                    horasDictadas = SUM(c.horasSesion)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  v.idEstudianteGrupo,
                    asistencias = SUM(IIF(v.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(v.asistio = 0 AND v.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(v.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_detalle_asistencia_v2 v
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = v.idSesion AND c.estaVencida = 1
            GROUP BY v.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
LEFT JOIN (
            SELECT  h.idEstudianteGrupo,
                    horasAsistidas = SUM(h.horasAsistidas),
                    horasFalta = SUM(h.horasFalta),
                    horasExcusa = SUM(h.horasExcusa),
                    sesionesAsistidas = SUM(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0)),
                    sesionesConFalta = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0)),
                    sesionesConExcusa = SUM(IIF(h.codigoRazonCausaConsolidado = N'EX', 1, 0))
            FROM    dbo.uv_asistencia_sesion_horas h
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = h.idSesion AND c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY h.idEstudianteGrupo
          ) hs
ON      hs.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT  horasDictadas = CAST(ISNULL(se.horasDictadas, 0) AS DECIMAL(12,6)),
                    horasAsistidas = CAST(ISNULL(hs.horasAsistidas, 0) AS DECIMAL(12,6)),
                    horasFalta = CAST(ISNULL(hs.horasFalta, 0) AS DECIMAL(12,6)),
                    horasExcusa = CAST(ISNULL(hs.horasExcusa, 0) AS DECIMAL(12,6)),
                    horasSinRegistro = CAST(IIF(ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0) < 0, 0,
                                                ISNULL(se.horasDictadas, 0) - ISNULL(hs.horasAsistidas, 0) - ISNULL(hs.horasFalta, 0) - ISNULL(hs.horasExcusa, 0)) AS DECIMAL(12,6))
          ) hd
CROSS APPLY (SELECT porcentaje = dbo.ufn_calcular_porcentaje_inasistencia_horas(hd.horasFalta, hd.horasDictadas)) p
CROSS APPLY (
            SELECT  umbralAdvertencia = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA') AS NVARCHAR(20))), '') AS DECIMAL(5,2)),
                    umbralPerdida = TRY_CAST(NULLIF(TRIM(CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA') AS NVARCHAR(20))), '') AS DECIMAL(5,2))
          ) u;
GO
