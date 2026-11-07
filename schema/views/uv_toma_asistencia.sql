USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5): una fila por toma de asistencia con su modo, estado, ventana de la sesion y conteos.
--   horasSesion = ufn_horas_sesion(inicio, fin); totalTomasSesion = tomas de la sesion; horasToma = horasSesion /
--   totalTomasSesion (0 si la sesion esta cancelada). Conteos de la toma por RazonCausa (literales de catalogo cerrado,
--   [SUPUESTO-B-03]): totalPresentes AN, totalAusentes SJC, totalExcusas EX. tieneQrActivo = token sin fechaCierreUtc.
CREATE OR ALTER VIEW [dbo].[uv_toma_asistencia]
AS
SELECT  idToma = t.id,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        numero = t.numero,
        idModo = m.id,
        codigoModo = m.codigo,
        nombreModo = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar,
        idEstado = e.id,
        codigoEstado = e.codigo,
        nombreEstado = e.nombre,
        estaAbierta = e.estaAbierta,
        esImplicita = t.esImplicita,
        idDocenteApertura = t.docenteApertura,
        fechaAperturaUtc = t.fechaAperturaUtc,
        fechaCierreUtc = t.fechaCierreUtc,
        totalAusentesMarcados = t.totalAusentesMarcados,
        fechaHoraInicioSesion = s.fechaHoraInicio,
        fechaHoraFinSesion = s.fechaHoraFin,
        estaSesionCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        horasSesion = h.horasSesion,
        totalTomasSesion = n.totalTomas,
        horasToma = CAST(IIF(sc.sesion IS NULL AND n.totalTomas > 0, h.horasSesion / n.totalTomas, 0) AS DECIMAL(12,6)),
        totalRegistros = ISNULL(d.totalRegistros, 0),
        totalPresentes = ISNULL(d.totalPresentes, 0),
        totalAusentes = ISNULL(d.totalAusentes, 0),
        totalExcusas = ISNULL(d.totalExcusas, 0),
        tieneQrActivo = CAST(IIF(EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WHERE tk.toma = t.id AND tk.fechaCierreUtc IS NULL), 1, 0) AS BIT)
FROM    dbo.TomaAsistencia t
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.ModoTomaAsistencia m
ON      m.id = t.modo
INNER JOIN dbo.EstadoTomaAsistencia e
ON      e.id = t.estado
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = t.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t2 WHERE t2.sesion = t.sesion) n
OUTER APPLY (
        SELECT  totalRegistros = COUNT(1),
                totalPresentes = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                totalAusentes = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                totalExcusas = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.toma = t.id
) d;
GO
