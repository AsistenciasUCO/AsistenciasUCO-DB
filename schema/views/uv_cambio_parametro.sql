USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): historial de cambios de parametros con el parametro y el ejecutor.
-- Solo lo lee usp_consultar_cambios_parametro_paginado (perfil ADMINISTRADOR).
CREATE OR ALTER VIEW [dbo].[uv_cambio_parametro]
AS
SELECT  cp.id,
        idParametro = cp.parametro,
        p.grupo,
        p.clave,
        cp.valorAnterior,
        cp.valorNuevo,
        cp.motivo,
        cp.idUsuarioEjecutor,
        nombreEjecutor = u.nombreCompleto,
        cp.idCorrelacion,
        cp.fechaCambioUtc
FROM    dbo.CambioParametro cp
INNER JOIN dbo.CatalogoParametro p
ON      p.id = cp.parametro
LEFT JOIN dbo.uv_usuario u
ON      u.id = cp.idUsuarioEjecutor;
GO
