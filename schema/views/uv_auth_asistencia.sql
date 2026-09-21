USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_auth_asistencia]
AS
SELECT  a.id,
        a.idEstudianteGrupo,
        a.idSesion
FROM    dbo.uv_asistencia a
INNER JOIN dbo.uv_auth_sesion ase ON a.idSesion = ase.id;
GO
