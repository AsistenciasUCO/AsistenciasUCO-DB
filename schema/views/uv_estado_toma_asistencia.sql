USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del estado de una toma de asistencia.
CREATE OR ALTER VIEW [dbo].[uv_estado_toma_asistencia]
AS
SELECT  id = e.id,
        codigo = e.codigo,
        nombre = e.nombre,
        estaAbierta = e.estaAbierta
FROM    dbo.EstadoTomaAsistencia e;
GO
