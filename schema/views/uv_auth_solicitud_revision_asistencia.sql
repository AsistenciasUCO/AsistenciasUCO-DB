USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_solicitud_revision_asistencia]
AS
SELECT  sr.id,
        sr.nombre,
        sr.idAsistencia,
        sr.fecha,
        sr.idEstado,
        sr.nombreEstado,
        sr.justificacionSolicitud,
        sr.justificacionRespuesta
FROM    dbo.uv_solicitud_revision_asistencia sr
INNER JOIN dbo.uv_auth_asistencia aa ON sr.idAsistencia = aa.id;
GO
