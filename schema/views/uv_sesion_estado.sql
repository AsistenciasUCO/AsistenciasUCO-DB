USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio). B.2 agrega totalTomas, tieneTomaAbierta, idTomaAbierta.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6))
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo;
GO
