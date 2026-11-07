USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
-- CULM-001 B.2 (CONTRACT §2.6, [SUPUESTO-B-06]): tieneRegistroAsistencia = existe Asistencia O existe TomaAsistencia (una toma
-- QR abierta y cerrada sin lecturas cuenta como sesion ejecutada); columnas nuevas totalTomas y horasSesion.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        idPrograma = gp.idPrograma,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id)
                                           OR EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id), 1, 0) AS BIT),
        totalTomas = (SELECT COUNT(1) FROM dbo.TomaAsistencia t WHERE t.sesion = s.id),
        horasSesion = dbo.ufn_horas_sesion(s.fechaHoraInicio, s.fechaHoraFin)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO
