USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU061/HU147/HU153/HU172 (2026-11-04): permisos del runtime para el consolidado de asistencia, los componentes de
-- formacion, la administracion de tipos de documento y la consulta de auditoria. Los SP validan el perfil del
-- ejecutor. Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). Los internos compartidos
-- (usp_resolver_area_componente_asignatura_interno, usp_guardar_tipo_identificacion_interno) no reciben permisos.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado', N'P') IS NULL
    THROW 56230, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_consolidado_asistencia_grupos_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado', N'P') IS NULL
    THROW 56231, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_auditoria_eventos_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_componentes_formacion', N'P') IS NULL
    THROW 56232, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_componentes_formacion requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_guardar_tipo_identificacion', N'P') IS NULL
    THROW 56233, 'HU061_HU172_RUNTIME_GRANT: usp_guardar_tipo_identificacion requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_consolidado_asistencia_grupos_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_auditoria_eventos_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_componentes_formacion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_guardar_tipo_identificacion] TO [rol_asistencias_runtime];
GO
