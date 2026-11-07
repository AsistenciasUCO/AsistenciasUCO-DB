USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.5, DEC-015): estado del token/PIN de asistencia de cada toma. Nunca expone tokenHash.
--   estaActivo      = fechaCierreUtc IS NULL
--   estaVigente     = activo y SYSUTCDATETIME() < fechaExpiracionUtc
--   debeRotar       = vigente y SYSUTCDATETIME() >= fechaRotacionUtc + ASISTENCIA_QR/ROTACION_SEGUNDOS
--   anteriorVigente = vigente, pinAnterior NOT NULL y SYSUTCDATETIME() < fechaRotacionUtc + ASISTENCIA_QR/TOLERANCIA_SEGUNDOS
--   totalRegistrosQr = detalles de la toma registrados por el estudiante
CREATE OR ALTER VIEW [dbo].[uv_token_asistencia_toma]
AS
SELECT  id = tk.id,
        idToma = tk.toma,
        idSesion = t.sesion,
        idGrupo = s.grupo,
        idDocenteEmisor = tk.docenteEmisor,
        pin = tk.pin,
        pinAnterior = tk.pinAnterior,
        fechaEmisionUtc = tk.fechaEmisionUtc,
        fechaRotacionUtc = tk.fechaRotacionUtc,
        fechaExpiracionUtc = tk.fechaExpiracionUtc,
        fechaCierreUtc = tk.fechaCierreUtc,
        estaActivo = CAST(IIF(tk.fechaCierreUtc IS NULL, 1, 0) AS BIT),
        estaVigente = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc, 1, 0) AS BIT),
        debeRotar = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc
                             AND SYSUTCDATETIME() >= DATEADD(SECOND, p.rotacionSegundos, tk.fechaRotacionUtc), 1, 0) AS BIT),
        anteriorVigente = CAST(IIF(tk.fechaCierreUtc IS NULL AND SYSUTCDATETIME() < tk.fechaExpiracionUtc AND tk.pinAnterior IS NOT NULL
                                   AND SYSUTCDATETIME() < DATEADD(SECOND, p.toleranciaSegundos, tk.fechaRotacionUtc), 1, 0) AS BIT),
        totalRegistrosQr = (SELECT COUNT(1) FROM dbo.DetalleAsistencia da WHERE da.toma = tk.toma AND da.registradoPorEstudiante = 1),
        nombreAsignatura = g.nombreAsignatura,
        nombreGrupo = g.nombre,
        numeroSesion = s.numero,
        numeroToma = t.numero
FROM    dbo.TokenAsistenciaToma tk
INNER JOIN dbo.TomaAsistencia t
ON      t.id = tk.toma
INNER JOIN dbo.Sesion s
ON      s.id = t.sesion
INNER JOIN dbo.uv_grupo g
ON      g.id = s.grupo
CROSS APPLY (
        SELECT  rotacionSegundos = IIF(r.valor IS NULL OR r.valor < 1, 60, r.valor),
                toleranciaSegundos = IIF(o.valor IS NULL OR o.valor < 0, 0, o.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS')) r
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS')) o
) p;
GO
