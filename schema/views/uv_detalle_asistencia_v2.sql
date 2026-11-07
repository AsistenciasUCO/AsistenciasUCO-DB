USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-011, DEC-012): detalle de asistencia por toma. Mismas columnas de uv_detalle_asistencia
-- (congelada, intacta) + la toma, la sesion, la matricula, el modo, las horas que vale la toma (0 si la sesion esta
-- cancelada), quien registro (registradoPorEstudiante) y cuando (fechaRegistroUtc).
CREATE OR ALTER VIEW [dbo].[uv_detalle_asistencia_v2]
AS
SELECT  id = da.id,
        codigo = da.codigo,
        idAsistencia = a.id,
        asistio = da.asistio,
        idRazonCausa = rc.id,
        nombreRazonCausa = rc.nombre,
        codigoRazonCausa = rc.codigo,
        fechaHoraInicio = da.fechaHoraInicio,
        fechaHoraFin = da.fechaHoraFin,
        idToma = t.id,
        numeroToma = t.numero,
        idSesion = a.sesion,
        idEstudianteGrupo = a.estudianteGrupo,
        idModoToma = m.id,
        codigoModoToma = m.codigo,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin) / n.totalTomas, 0) AS DECIMAL(12,6)),
        registradoPorEstudiante = da.registradoPorEstudiante,
        fechaRegistroUtc = da.fechaRegistroUtc,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT)
FROM    dbo.DetalleAsistencia da
INNER JOIN dbo.Asistencia a
ON      a.id = da.asistencia
INNER JOIN dbo.uv_razon_causa rc
ON      rc.id = da.razonCausa
INNER JOIN dbo.TomaAsistencia t
ON      t.id = da.toma
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = a.sesion
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n;
GO
