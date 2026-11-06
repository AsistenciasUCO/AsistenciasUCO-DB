USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_notificaciones_salientes_admin_interno]
-- Capacidad: Monitor de Cola Outbox (TD-069)
-- Ambito: Consulta interna paginada de notificaciones salientes y resumen por estado.
-- Salida:
--   Result set 2: Notificaciones paginadas con totalRegistros (creadoEn DESC)
--   Result set 3: Resumen de totales por estado (codigoEstado, total)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_notificaciones_salientes_admin_interno]
(
    @codigoEstado NVARCHAR(40) = NULL,
    @tipo         NVARCHAR(60) = NULL,
    @numeroPagina INT          = 1,
    @tamanoPagina INT          = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @codigoEstadoDef NVARCHAR(40) = CASE WHEN UPPER(TRIM(@codigoEstado)) = 'TODOS' THEN NULL ELSE NULLIF(TRIM(@codigoEstado), '') END;
    DECLARE @tipoDef         NVARCHAR(60) = CASE WHEN UPPER(TRIM(@tipo)) = 'TODOS' THEN NULL ELSE NULLIF(TRIM(@tipo), '') END;
    DECLARE @numPagDef       INT          = CASE WHEN COALESCE(@numeroPagina, 1) <= 1 THEN 1 ELSE @numeroPagina END;
    DECLARE @tamPagDef       INT          = COALESCE(@tamanoPagina, 20);
    DECLARE @offset          INT          = (@numPagDef - 1) * @tamPagDef;

    DECLARE @totalElementos BIGINT = (
        SELECT COUNT(*)
        FROM dbo.uv_notificacion_saliente_admin
        WHERE (@codigoEstadoDef IS NULL OR codigoEstado = @codigoEstadoDef)
          AND (@tipoDef IS NULL OR tipo = @tipoDef)
    );
    DECLARE @totalPaginas INT = CASE WHEN @totalElementos = 0 THEN 1 ELSE CEILING(CAST(@totalElementos AS FLOAT) / @tamPagDef) END;

    -- Result set 2: Lista paginada
    SELECT
        id,
        tipo,
        asunto,
        codigoEstado,
        nombreEstado,
        esTerminal,
        cantidadDestinatarios,
        intentos,
        creadoEn,
        proximoIntentoEn,
        entregadoEn,
        codigoError,
        detalleError,
        idCorrelacion
    FROM dbo.uv_notificacion_saliente_admin
    WHERE (@codigoEstadoDef IS NULL OR codigoEstado = @codigoEstadoDef)
      AND (@tipoDef IS NULL OR tipo = @tipoDef)
    ORDER BY creadoEn DESC
    OFFSET @offset ROWS
    FETCH NEXT @tamPagDef ROWS ONLY;

    -- Result set 3: Metadatos de paginacion
    SELECT
        totalElementos = @totalElementos,
        totalPaginas   = @totalPaginas;

    -- Result set 4: Resumen de totales por estado (fila unica de 5 columnas)
    SELECT
        pendientes            = COALESCE(SUM(CASE WHEN codigoEstado = 'PENDIENTE' THEN 1 ELSE 0 END), 0),
        reservadas            = COALESCE(SUM(CASE WHEN codigoEstado = 'RESERVADA' THEN 1 ELSE 0 END), 0),
        entregadas            = COALESCE(SUM(CASE WHEN codigoEstado = 'ENTREGADA' THEN 1 ELSE 0 END), 0),
        fallidasReintentables = COALESCE(SUM(CASE WHEN codigoEstado = 'FALLIDA_REINTENTABLE' THEN 1 ELSE 0 END), 0),
        fallidasDefinitivas   = COALESCE(SUM(CASE WHEN codigoEstado = 'FALLIDA_DEFINITIVA' THEN 1 ELSE 0 END), 0)
    FROM dbo.uv_notificacion_saliente_admin;
END;
GO
