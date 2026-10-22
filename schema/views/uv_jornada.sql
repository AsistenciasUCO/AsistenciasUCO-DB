USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW [dbo].[uv_jornada]
AS
SELECT  id,
        codigo,
        nombre,
        estaActivoJornada = estado,
        estaActivoTextoJornada = IIF(estado = 1, 'SI', 'NO')
FROM    Jornada
GO
