USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-012, DEC-024, [SUPUESTO-B-15], NB-9): una fila por cabecera Asistencia con las horas de la
-- sesion repartidas por toma y el estado consolidado de la sesion.
--   horasSesion = ufn_horas_sesion(inicio, fin); cada toma vale horasSesion / totalTomasSesion (0 si la sesion esta cancelada)
--   horasAsistidas (AN), horasFalta (asistio = 0 y SJC), horasExcusa (EX); horasSinRegistro = horasSesion - las tres
--   (se calcula por conteo de tomas para no acumular redondeos; sin tomas o cancelada = horasSesion).
--   codigoRazonCausaConsolidado: SJC si alguna toma es SJC; si no EX si alguna es EX; si no AN si alguna es AN; si no NULL.
--   esParcial = mezcla AN y SJC. Literales de RazonCausa de catalogo cerrado ([SUPUESTO-B-03]).
CREATE OR ALTER VIEW [dbo].[uv_asistencia_sesion_horas]
AS
SELECT  idAsistencia = a.id,
        idEstudianteGrupo = a.estudianteGrupo,
        idSesion = a.sesion,
        idGrupo = s.grupo,
        totalTomasSesion = n.totalTomas,
        tomasConRegistro = ISNULL(d.conRegistro, 0),
        horasSesion = h.horasSesion,
        horasAsistidas = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nAN, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasFalta = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nFalta, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasExcusa = CAST(IIF(x.reparte = 1, h.horasSesion * ISNULL(d.nEX, 0) / n.totalTomas, 0) AS DECIMAL(12,6)),
        horasSinRegistro = CAST(IIF(x.reparte = 1,
                                    h.horasSesion * (n.totalTomas - ISNULL(d.nAN, 0) - ISNULL(d.nFalta, 0) - ISNULL(d.nEX, 0)) / n.totalTomas,
                                    h.horasSesion) AS DECIMAL(12,6)),
        codigoRazonCausaConsolidado = CAST(CASE WHEN ISNULL(d.nSJC, 0) > 0 THEN N'SJC'
                                                WHEN ISNULL(d.nEX, 0) > 0 THEN N'EX'
                                                WHEN ISNULL(d.nAN, 0) > 0 THEN N'AN'
                                           END AS NVARCHAR(10)),
        esParcial = CAST(IIF(ISNULL(d.nAN, 0) > 0 AND ISNULL(d.nSJC, 0) > 0, 1, 0) AS BIT),
        tieneFaltaSinJustaCausa = CAST(IIF(ISNULL(d.nFalta, 0) > 0, 1, 0) AS BIT)
FROM    dbo.Asistencia a
INNER JOIN dbo.Sesion s
ON      s.id = a.sesion
CROSS APPLY (SELECT horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)) h
CROSS APPLY (SELECT totalTomas = COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = a.sesion) n
CROSS APPLY (SELECT reparte = CAST(IIF(n.totalTomas > 0 AND NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = a.sesion), 1, 0) AS BIT)) x
OUTER APPLY (
        SELECT  conRegistro = COUNT(1),
                nAN = SUM(IIF(rc.codigo = N'AN', 1, 0)),
                nFalta = SUM(IIF(rc.codigo = N'SJC' AND da.asistio = 0, 1, 0)),
                nSJC = SUM(IIF(rc.codigo = N'SJC', 1, 0)),
                nEX = SUM(IIF(rc.codigo = N'EX', 1, 0))
        FROM    dbo.DetalleAsistencia da
        INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
        WHERE   da.asistencia = a.id
) d;
GO
