USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: proyeccion v2 de sesiones con procedencia temporal.
-- Columnas 1..10: mismo nombre, orden y tipo que dbo.uv_sesion (vista v1 congelada, NO se altera).
-- Columna 11: procedenciaTemporal (NULL = INDETERMINADA).
-- Las horas y la marca se leen de la MISMA fila de dbo.Sesion en una sola sentencia SELECT,
-- para que nunca se combine una hora nueva con una marca vieja (o viceversa).
CREATE OR ALTER VIEW [dbo].[uv_sesion_v2]
AS
SELECT      id = v.id,
            nombre = v.nombre,
            numero = v.numero,
            codigo = v.codigo,
            numeroSemana = v.numeroSemana,
            idGrupo = v.idGrupo,
            codigoGrupo = v.codigoGrupo,
            nombreGrupo = v.nombreGrupo,
            fechaHoraInicio = se.fechaHoraInicio,
            fechaHoraFin = se.fechaHoraFin,
            procedenciaTemporal = se.procedenciaTemporal
FROM        dbo.uv_sesion v
INNER JOIN  dbo.Sesion se
ON          se.id = v.id
GO
