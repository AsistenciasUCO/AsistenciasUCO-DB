USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_horario_estudiante] AS
SELECT 
    h.id                            AS id,
    eg.estudiante                   AS idEstudiante,
    g.id                            AS idGrupo,
    a.codigo                        AS codigoMateria,
    a.nombre                        AS nombreMateria,
    g.nombre                        AS grupo,
    CASE WHEN d.nombre LIKE 'Miercol%' THEN N'Miércoles' ELSE d.nombre END AS dia,
    CONVERT(VARCHAR(5), h.horaInicio, 108) AS horaInicio,
    CONVERT(VARCHAR(5), h.horaFin, 108)    AS horaFin,
    CONCAT(u.primerNombre, ' ', ISNULL(u.segundoNombre + ' ', ''), u.primerApellido, ' ', ISNULL(u.segundoApellido, '')) AS docente
FROM [dbo].[Horario] h
INNER JOIN [dbo].[Grupo] g ON h.grupo = g.id
INNER JOIN [dbo].[Asignatura] a ON g.asignatura = a.id
INNER JOIN [dbo].[Dia] d ON h.dia = d.id
INNER JOIN [dbo].[EstudianteGrupo] eg ON eg.grupo = g.id
LEFT JOIN [dbo].[Docente] doc ON g.docente = doc.id
LEFT JOIN [dbo].[Usuario] u ON doc.usuario = u.id;
GO
