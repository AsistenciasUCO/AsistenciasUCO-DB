USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): dias festivos nacionales cargados (activos e inactivos).
CREATE OR ALTER VIEW [dbo].[uv_dia_festivo]
AS
SELECT  id = df.id,
        fecha = df.fecha,
        anio = df.anio,
        nombre = df.nombre,
        fuente = df.fuente,
        estaActivo = df.estaActivo,
        fechaCargaUtc = df.fechaCargaUtc,
        idCorrelacionCarga = df.idCorrelacionCarga
FROM    dbo.DiaFestivo df;
GO
