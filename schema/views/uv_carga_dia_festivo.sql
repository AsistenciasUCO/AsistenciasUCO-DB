USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): bitacora de cargas de festivos; esUltimaCargaAnio = 1 en la carga mas reciente del anio.
CREATE OR ALTER VIEW [dbo].[uv_carga_dia_festivo]
AS
SELECT  id = c.id,
        anio = c.anio,
        fuente = c.fuente,
        totalFestivos = c.totalFestivos,
        festivosInsertados = c.festivosInsertados,
        festivosActualizados = c.festivosActualizados,
        festivosDesactivados = c.festivosDesactivados,
        diferenciasCalculoLocal = c.diferenciasCalculoLocal,
        idUsuarioEjecutor = c.usuarioEjecutor,
        fechaCargaUtc = c.fechaCargaUtc,
        idCorrelacion = c.idCorrelacion,
        esUltimaCargaAnio = CAST(IIF(ROW_NUMBER() OVER (PARTITION BY c.anio ORDER BY c.fechaCargaUtc DESC, c.id DESC) = 1, 1, 0) AS BIT)
FROM    dbo.CargaDiaFestivo c;
GO
