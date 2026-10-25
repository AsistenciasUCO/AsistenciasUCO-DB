USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
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
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id), 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = s.idGrupo
GO
