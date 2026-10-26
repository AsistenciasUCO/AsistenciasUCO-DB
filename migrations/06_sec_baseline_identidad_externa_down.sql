USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- Rollback de SEC-BASELINE-017. Idempotente. DESTRUCTIVO para los vinculos registrados: antes de ejecutarlo hay que
-- retirar el backend que usa el modo baseline (o volver a legacy) y respaldar dbo.IdentidadExterna si se quiere
-- conservar la evidencia. Quita primero los objetos que dependen de la tabla.
IF OBJECT_ID(N'dbo.usp_vincular_identidad_externa', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_vincular_identidad_externa];
GO
IF OBJECT_ID(N'dbo.usp_revocar_identidad_externa', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_revocar_identidad_externa];
GO
IF OBJECT_ID(N'dbo.uv_identidad_externa', N'V') IS NOT NULL DROP VIEW [dbo].[uv_identidad_externa];
GO
IF OBJECT_ID(N'dbo.IdentidadExterna', N'U') IS NOT NULL DROP TABLE [dbo].[IdentidadExterna];
GO
