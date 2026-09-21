USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_periodo_academico]
AS
SELECT  pa.id,
        pa.idInstitucion,
        pa.nombreInstitucion,
        pa.nombre,
        pa.codigo,
        pa.fechaInicio,
        pa.fechaFin,
        pa.anio
FROM    dbo.uv_periodo_academico pa
INNER JOIN dbo.uv_auth_institucion ai ON pa.idInstitucion = ai.id;
GO
