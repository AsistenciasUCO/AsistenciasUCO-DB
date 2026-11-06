USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU061/HU147/HU172 (2026-11-04): permisos del runtime para el consolidado de asistencia, los componentes de
-- formacion y la consulta de auditoria. Los SP validan el perfil del ejecutor. Script aditivo e idempotente (no
-- modifica rol_asistencias_runtime.sql). El interno compartido usp_resolver_area_componente_asignatura_interno no
-- recibe permisos. HU153 quedo de solo consulta (regla de John 2026-11-04): los catalogos base no tienen SP de escritura.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_consolidado_asistencia_grupos_paginado', N'P') IS NULL
    THROW 56230, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_consolidado_asistencia_grupos_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_auditoria_eventos_paginado', N'P') IS NULL
    THROW 56231, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_auditoria_eventos_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_componentes_formacion', N'P') IS NULL
    THROW 56232, 'HU061_HU172_RUNTIME_GRANT: usp_consultar_componentes_formacion requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_consolidado_asistencia_grupos_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_auditoria_eventos_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_componentes_formacion] TO [rol_asistencias_runtime];
GO
