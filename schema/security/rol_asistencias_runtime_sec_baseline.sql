USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SEC-BASELINE-017: permisos de minimo privilegio del vinculo de identidad externa.
--
-- Script aditivo e independiente: no modifica rol_asistencias_runtime.sql (cuyo hash esta fijado en
-- DB_UTC_D06_POST_FREEZE_MANIFEST.sha256). Idempotente.
--   * Solo EXEC de los dos SP publicos nombrados; nunca GRANT EXECUTE ON SCHEMA::dbo.
--   * La lectura del vinculo usa dbo.uv_identidad_externa (la cubre el GRANT por vista de rol_asistencias_runtime.sql).
--   * Sin acceso directo del runtime a dbo.IdentidadExterna.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_vincular_identidad_externa', N'P') IS NULL
    THROW 52150, 'SEC_BASELINE_RUNTIME_GRANT: usp_vincular_identidad_externa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_revocar_identidad_externa', N'P') IS NULL
    THROW 52151, 'SEC_BASELINE_RUNTIME_GRANT: usp_revocar_identidad_externa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.IdentidadExterna', N'U') IS NULL
    THROW 52152, 'SEC_BASELINE_RUNTIME_GRANT: tabla IdentidadExterna requerida ausente.', 1;
IF OBJECT_ID(N'dbo.uv_identidad_externa', N'V') IS NULL
    THROW 52153, 'SEC_BASELINE_RUNTIME_GRANT: vista uv_identidad_externa requerida ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_vincular_identidad_externa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_revocar_identidad_externa] TO [rol_asistencias_runtime];
GRANT SELECT ON [dbo].[uv_identidad_externa] TO [rol_asistencias_runtime];
DENY SELECT, INSERT, UPDATE, DELETE ON [dbo].[IdentidadExterna] TO [rol_asistencias_runtime];
GO
