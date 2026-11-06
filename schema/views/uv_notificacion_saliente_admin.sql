USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Vista: [dbo].[uv_notificacion_saliente_admin]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Administrador Institucional
-- =============================================================================
CREATE OR ALTER VIEW [dbo].[uv_notificacion_saliente_admin]
AS
SELECT
    id                    = n.id,
    tipo                  = n.tipo,
    asunto                = n.asunto,
    codigoEstado          = e.codigo,
    nombreEstado          = e.nombre,
    esTerminal            = e.esTerminal,
    cantidadDestinatarios = CASE WHEN ISJSON(n.destinatarios) = 1 THEN (SELECT COUNT(*) FROM OPENJSON(n.destinatarios)) ELSE 0 END,
    intentos              = n.intentos,
    creadoEn              = n.creadoEn,
    proximoIntentoEn      = n.proximoIntentoEn,
    entregadoEn           = n.entregadoEn,
    codigoError           = n.codigoError,
    detalleError          = n.detalleError,
    idCorrelacion         = n.idCorrelacion
FROM dbo.NotificacionSaliente n
INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado;
GO
