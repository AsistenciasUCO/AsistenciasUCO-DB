USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.13): permisos de ejecucion de las tomas de asistencia, el QR de asistencia por toma
-- (HU175/HU176) y los resumenes por horas. Solo EXECUTE sobre los SP publicos; sin DML directo sobre TomaAsistencia,
-- TokenAsistenciaToma ni DetalleAsistencia. Aditivo e idempotente. Los nucleos usp_internal_* y *_interno NO se conceden.
-- SIN REVOKE: usp_registrar_asistencia_estudiante_autonomo conserva su EXECUTE (lo concede rol_asistencias_runtime.sql,
-- congelado; el REVOKE/DROP pasa al paquete D, [SUPUESTO-B-18], B-5 de REVIEW-1).
-- Las vistas nuevas las cubre el bucle uv_* de rol_asistencias_runtime.sql cuando deploy_schema.ps1 aplica la seguridad
-- despues de las vistas; el GRANT SELECT explicito de abajo cubre las vistas creadas por la migracion 16.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_abrir_toma_asistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cerrar_toma_asistencia', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cerrar_toma_asistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cerrar_tomas_vencidas', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cerrar_tomas_vencidas] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencias_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_asistencias_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_abrir_qr_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_abrir_qr_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_asistencia_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_rotar_token_asistencia_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_asistencia_automatico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_rotar_token_asistencia_automatico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_tomas_qr_por_rotar', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_tomas_qr_por_rotar] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cerrar_qr_toma', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cerrar_qr_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_por_token', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_asistencia_por_token] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_tomas_sesion', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_tomas_sesion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_faltantes_toma_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_faltantes_toma_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_toma_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_asistencias_toma_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_resumen_asistencia_estudiante] TO [rol_asistencias_runtime];
GO

IF OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_toma_asistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_token_asistencia_toma', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_token_asistencia_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_detalle_asistencia_v2', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_detalle_asistencia_v2] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_asistencia_sesion_horas] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_faltantes_toma', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_faltantes_toma] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_modo_toma_asistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_modo_toma_asistencia] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_estado_toma_asistencia', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_estado_toma_asistencia] TO [rol_asistencias_runtime];
GO
