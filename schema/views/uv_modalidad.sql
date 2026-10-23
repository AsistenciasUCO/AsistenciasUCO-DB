USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_modalidad]
AS
SELECT  id,
        codigo,
        nombre,
        estaActivoModalidad = estado,
        estaActivoTextoModalidad = IIF(estado = 1, 'SI', 'NO')
FROM    Modalidad
GO
