USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del modo de una toma de asistencia.
CREATE OR ALTER VIEW [dbo].[uv_modo_toma_asistencia]
AS
SELECT  id = m.id,
        codigo = m.codigo,
        nombre = m.nombre,
        usaCodigoQr = m.usaCodigoQr,
        marcaAusentesAlCerrar = m.marcaAusentesAlCerrar
FROM    dbo.ModoTomaAsistencia m;
GO
