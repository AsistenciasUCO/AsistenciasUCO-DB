USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, DEC-044 (2); HU026B): una fila por (sesion, matricula del estudiante) con la fecha limite
-- para justificar. Sobre uv_sesion_v2 + uv_sesion_estado (B.1) + uv_estudiante_grupo; uv_sesion (congelada) no se toca.
--   fechaLimiteJustificacionUtc = ufn_calcular_fecha_limite_justificacion(fechaHoraFin)  (limite exclusivo; NULL si falta
--                                 ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER)
--   plazoJustificacionVigente   = 1 solo si la sesion NO esta cancelada y SYSUTCDATETIME() < limite
-- idAsignatura, codigo, numeroSemana, codigoGrupo, nombreGrupo y codigoEstadoEstudiante completan las columnas que hoy
-- entrega la consulta de sesiones de la materia y permiten al SP filtrar la matricula inscrita.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estudiante_reclamo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        idAsignatura = g.idAsignatura,
        numero = s.numero,
        nombre = s.nombre,
        codigo = s.codigo,
        numeroSemana = s.numeroSemana,
        codigoGrupo = s.codigoGrupo,
        nombreGrupo = s.nombreGrupo,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaCancelada = se.estaCancelada,
        fechaLimiteJustificacionUtc = lim.fechaLimiteUtc,
        plazoJustificacionVigente = CAST(IIF(se.estaCancelada = 0 AND lim.fechaLimiteUtc IS NOT NULL
                                             AND SYSUTCDATETIME() < lim.fechaLimiteUtc, 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_sesion_estado se
ON      se.idSesion = s.id
INNER JOIN dbo.uv_estudiante_grupo eg
ON      eg.idGrupo = s.idGrupo
INNER JOIN dbo.uv_grupo g
ON      g.id = s.idGrupo
CROSS APPLY (SELECT fechaLimiteUtc = dbo.ufn_calcular_fecha_limite_justificacion(s.fechaHoraFin)) lim;
GO
