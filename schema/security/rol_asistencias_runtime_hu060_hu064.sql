USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU064/HU060/HU061: permisos de lectura del runtime para las consultas del coordinador (grupos, sesiones y
-- detalle de asistencia de su programa). Los SP filtran por el usuario ejecutor mediante las vistas uv_auth_*.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_grupos_paginado', N'P') IS NULL
    THROW 52160, 'HU060_HU064_RUNTIME_GRANT: usp_consultar_grupos_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_grupo_paginado', N'P') IS NULL
    THROW 52161, 'HU060_HU064_RUNTIME_GRANT: usp_consultar_sesiones_grupo_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_sesion_paginado', N'P') IS NULL
    THROW 52162, 'HU060_HU064_RUNTIME_GRANT: usp_consultar_asistencias_sesion_paginado requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_grupos_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_grupo_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asistencias_sesion_paginado] TO [rol_asistencias_runtime];
GO
