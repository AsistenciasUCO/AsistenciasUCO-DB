USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2): permisos del plazo de excusas (HU026B). Solo EXECUTE sobre el SP publico de consulta y
-- SELECT sobre la vista nueva; el nucleo usp_internal_validar_plazo_justificacion NO se concede (lo invocan v1 y v2).
-- Aditivo e idempotente. El bucle uv_* de rol_asistencias_runtime.sql ya cubre la vista cuando deploy_schema.ps1 aplica la
-- seguridad despues de las vistas; el GRANT explicito cubre la vista creada por la migracion 20 fuera de ese despliegue.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_materia_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_sesion_estudiante_reclamo] TO [rol_asistencias_runtime];
GO
