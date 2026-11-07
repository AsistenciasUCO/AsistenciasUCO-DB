USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2): permisos de la admision de estudiantes (HU156). Solo EXECUTE sobre los SP publicos; los nucleos
-- usp_*_interno que usan NO se conceden. Aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_admitir_estudiante', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_admitir_estudiante] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_programas_institucion_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_programas_institucion_paginado] TO [rol_asistencias_runtime];
GO
