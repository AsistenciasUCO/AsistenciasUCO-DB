USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN 22: CULM-001 D.3 - revierte los parametros editables por el administrador (CONTRACT v2 §4.2, §14.2).
-- Idempotente y tolerante (se puede ejecutar dos veces).
--   1. Exporta CambioParametro a dbo.zz_archivo_CambioParametro_culm001_d3 (patron A.1/DEC-010): el up siguiente restaura
--      el historial; las filas ya archivadas no se duplican.
--   2. DROP de los SP, las vistas y la funcion de D.3 (en orden de dependencia) y de CambioParametro y
--      CatalogoParametroEdicion (con sus FKs).
--   3. Borra los parametros PARAMETROS/* solo si valor = valorDefecto (nunca estan editados: el grupo es no editable) y los
--      mensajes PRM_001..PRM_012. NO revierte los valores administrados de CatalogoParametro (se conservan).
-- ============================================================================
PRINT 'MIGRACION 22 DOWN: historial, objetos y semillas de D.3';
GO
IF OBJECT_ID(N'dbo.CambioParametro', N'U') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.zz_archivo_CambioParametro_culm001_d3', N'U') IS NULL
        EXEC sys.sp_executesql N'SELECT id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc INTO dbo.zz_archivo_CambioParametro_culm001_d3 FROM dbo.CambioParametro;';
    ELSE
        EXEC sys.sp_executesql N'
            INSERT INTO dbo.zz_archivo_CambioParametro_culm001_d3 (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
            SELECT c.id, c.parametro, c.valorAnterior, c.valorNuevo, c.motivo, c.idUsuarioEjecutor, c.idCorrelacion, c.fechaCambioUtc
            FROM dbo.CambioParametro c
            WHERE NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_CambioParametro_culm001_d3 a WHERE a.id = c.id);';
END
GO
IF OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_actualizar_parametro];
GO
IF OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_parametros_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_cambios_parametro_paginado];
GO
IF OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_parametro_edicion];
GO
IF OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_cambio_parametro];
GO
IF OBJECT_ID(N'dbo.ufn_validar_valor_parametro', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[ufn_validar_valor_parametro];
GO
IF OBJECT_ID(N'dbo.CambioParametro', N'U') IS NOT NULL
    DROP TABLE [dbo].[CambioParametro];
GO
IF OBJECT_ID(N'dbo.CatalogoParametroEdicion', N'U') IS NOT NULL
    DROP TABLE [dbo].[CatalogoParametroEdicion];
GO
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'PARAMETROS' AND valor = valorDefecto;
GO
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo LIKE 'PRM[_]0[0-1][0-9]';
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo LIKE 'PRM[_]0[0-1][0-9]';
GO
PRINT CONCAT('MIGRACION 22 DOWN OK | archivo=', IIF(OBJECT_ID(N'dbo.zz_archivo_CambioParametro_culm001_d3', N'U') IS NULL, 'no', 'si'), ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
