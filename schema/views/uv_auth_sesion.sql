USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_sesion]
AS
SELECT  s.id,
        s.nombre,
        s.numero,
        s.codigo,
        s.numeroSemana,
        s.idGrupo,
        s.codigoGrupo,
        s.nombreGrupo,
        s.fechaHoraInicio,
        s.fechaHoraFin
FROM    dbo.uv_sesion s
INNER JOIN dbo.uv_auth_grupo ag ON s.idGrupo = ag.id;
GO
