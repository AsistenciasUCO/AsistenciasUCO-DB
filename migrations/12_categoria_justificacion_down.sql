USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN: HU005/HU016 - Retira el catalogo de categorias de justificacion
-- ============================================================================
-- Ningun objeto referencia la tabla (sin FK). Al borrar la vista se retira su GRANT. Idempotente.
IF OBJECT_ID(N'dbo.uv_categoria_justificacion', N'V') IS NOT NULL
    DROP VIEW [dbo].[uv_categoria_justificacion];
GO
IF OBJECT_ID(N'dbo.CategoriaJustificacion', N'U') IS NOT NULL
    DROP TABLE [dbo].[CategoriaJustificacion];
GO
