USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_consultar_plantillas_notificacion_admin_interno]
-- Capacidad: Administracion de Plantillas de Notificacion (NOTIF-002B)
-- Ambito: Consulta interna atomica de versiones de plantillas y marcadores declarados.
-- Salida:
--   Result set 2: Versiones de plantillas filtradas por idioma (tipo ASC, version DESC).
--   Result set 3: Marcadores declarados (tipo ASC, obligatorio DESC, marcador ASC).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_plantillas_notificacion_admin_interno]
(
    @idioma CHAR(2) = 'es'
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idiomaDef CHAR(2) = COALESCE(NULLIF(LOWER(TRIM(@idioma)), ''), 'es');

    -- Result set 2: Tipos con su version activa actual
    SELECT
        tipo          = p.tipo,
        idioma        = p.idioma,
        versionActiva = p.[version],
        asuntoActivo  = p.asunto,
        cuerpoActivo  = p.cuerpo,
        actualizadoEn = p.creadoEn
    FROM dbo.PlantillaNotificacion p
    WHERE p.idioma = @idiomaDef
      AND p.activa = 1
    ORDER BY p.tipo ASC;

    -- Result set 3: Marcadores declarados
    SELECT
        tipo        = m.tipo,
        marcador    = m.marcador,
        descripcion = m.descripcion,
        ejemplo     = m.ejemplo,
        obligatorio = m.obligatorio
    FROM dbo.PlantillaNotificacionMarcador m
    ORDER BY m.tipo ASC, m.obligatorio DESC, m.marcador ASC;

    -- Result set 4: Historial completo de versiones por tipo
    SELECT
        id        = p.id,
        tipo      = p.tipo,
        idioma    = p.idioma,
        [version] = p.[version],
        asunto    = p.asunto,
        cuerpo    = p.cuerpo,
        activa    = p.activa,
        creadoEn  = p.creadoEn
    FROM dbo.PlantillaNotificacion p
    WHERE p.idioma = @idiomaDef
    ORDER BY p.tipo ASC, p.[version] DESC;
END;
GO
