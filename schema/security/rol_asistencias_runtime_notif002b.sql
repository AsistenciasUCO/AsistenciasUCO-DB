USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Permisos: rol_asistencias_runtime_notif002b (NOTIF-002B + TD-069)
-- Ambito: Procedimientos publicos de administracion de plantillas, monitor de outbox,
--         reintento manual y destinatarios de reclamos de asistencia.
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

-- 1. Administracion de plantillas (NOTIF-002B)
IF OBJECT_ID(N'dbo.usp_consultar_plantillas_notificacion_admin', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_plantillas_notificacion_admin] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_guardar_plantilla_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_guardar_plantilla_notificacion] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_activar_version_plantilla_notificacion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_activar_version_plantilla_notificacion] TO [rol_asistencias_runtime];
GO

-- 2. Monitor de cola outbox y reintento manual (TD-069)
IF OBJECT_ID(N'dbo.uv_notificacion_saliente_admin', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_notificacion_saliente_admin] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_consultar_notificaciones_salientes_admin', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_notificaciones_salientes_admin] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.usp_reintentar_notificacion_saliente', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_reintentar_notificacion_saliente] TO [rol_asistencias_runtime];
GO

-- 3. Destinatarios de reclamo de asistencia (HU010 / HU037 / HU042)
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_reclamo_asistencia', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_reclamo_asistencia] TO [rol_asistencias_runtime];
GO
