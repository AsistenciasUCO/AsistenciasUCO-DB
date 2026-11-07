USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.13): permisos de ejecucion de la sesion cancelada (HU047), los dias festivos y la
-- generacion de sesiones v2. Solo EXECUTE sobre los SP publicos; sin DML directo sobre SesionCancelacion, DiaFestivo ni
-- CargaDiaFestivo. Aditivo e idempotente. Los nucleos usp_internal_* NO se conceden.
-- Las vistas nuevas (uv_sesion_estado, uv_dia_festivo, uv_carga_dia_festivo, uv_tipo_cancelacion_sesion) las cubre el
-- bucle uv_* de rol_asistencias_runtime.sql cuando deploy_schema.ps1 aplica la seguridad despues de las vistas; el
-- GRANT SELECT explicito de abajo cubre las vistas creadas por la migracion 15 fuera de ese despliegue.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cancelar_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_sesion_cancelada] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cargar_dias_festivos', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cargar_dias_festivos] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cargar_dias_festivos_automatico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cargar_dias_festivos_automatico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_aplicar_festivos_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_periodo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_aplicar_festivos_periodo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_automatico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_aplicar_festivos_automatico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_festivo_con_asistencia_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_festivo_con_asistencia_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_dias_festivos', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_dias_festivos] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_carga_festivos_anio', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_carga_festivos_anio] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_generar_sesiones_grupo_v2', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_generar_sesiones_grupo_v2] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_estado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_dia_festivo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_carga_dia_festivo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_tipo_cancelacion_sesion] TO [rol_asistencias_runtime];
GO
