USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU104/HU105/HU109/HU119/HU145: permisos de lectura del runtime para las consultas del decano (directorio y
-- ficha de estudiantes, estructura de la facultad y cronograma de sesiones). Los SP filtran por el decano
-- ejecutor mediante las vistas uv_auth_*. Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_facultad_paginado', N'P') IS NULL
    THROW 52170, 'HU104_HU145_RUNTIME_GRANT: usp_consultar_estudiantes_facultad_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_estudiante_facultad_detalle', N'P') IS NULL
    THROW 52171, 'HU104_HU145_RUNTIME_GRANT: usp_consultar_estudiante_facultad_detalle requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_estructura_facultad', N'P') IS NULL
    THROW 52172, 'HU104_HU145_RUNTIME_GRANT: usp_consultar_estructura_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_facultad_paginado', N'P') IS NULL
    THROW 52173, 'HU104_HU145_RUNTIME_GRANT: usp_consultar_sesiones_facultad_paginado requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_estudiantes_facultad_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_estudiante_facultad_detalle] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_estructura_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_sesiones_facultad_paginado] TO [rol_asistencias_runtime];
GO
