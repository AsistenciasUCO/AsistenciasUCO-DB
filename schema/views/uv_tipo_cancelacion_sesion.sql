USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del tipo de cancelacion de sesion.
CREATE OR ALTER VIEW [dbo].[uv_tipo_cancelacion_sesion]
AS
SELECT  id = t.id,
        codigo = t.codigo,
        nombre = t.nombre,
        esAutomatica = t.esAutomatica
FROM    dbo.TipoCancelacionSesion t;
GO
