USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_horario_docente] AS
SELECT 
    h.id                            AS id,
    g.docente                       AS idDocente,
    g.id                            AS idGrupo,
    a.codigo                        AS codigoMateria,
    a.nombre                        AS nombreMateria,
    g.nombre                        AS seccion,
    CASE WHEN d.nombre LIKE 'Miercol%' THEN N'Miércoles' ELSE d.nombre END AS dia,
    CONVERT(VARCHAR(5), h.horaInicio, 108) AS horaInicio,
    CONVERT(VARCHAR(5), h.horaFin, 108)    AS horaFin,
    (SELECT COUNT(1) FROM [dbo].[EstudianteGrupo] eg WHERE eg.grupo = g.id) AS totalEstudiantes
FROM [dbo].[Horario] h
INNER JOIN [dbo].[Grupo] g ON h.grupo = g.id
INNER JOIN [dbo].[Asignatura] a ON g.asignatura = a.id
INNER JOIN [dbo].[Dia] d ON h.dia = d.id;
GO
