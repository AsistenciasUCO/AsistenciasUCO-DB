USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2): permisos de ejecucion de la edicion de parametros por el administrador (HU168). Solo
-- EXECUTE sobre los tres SP publicos; sin DML ni SELECT directo sobre CatalogoParametroEdicion ni CambioParametro (las
-- vistas uv_parametro_edicion y uv_cambio_parametro las cubre el bucle uv_* de rol_asistencias_runtime.sql). Aditivo e
-- idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_actualizar_parametro] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_parametros_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_cambios_parametro_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_parametro_edicion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_cambio_parametro] TO [rol_asistencias_runtime];
GO
