USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A.2 (CONTRACT §8.2): EXECUTE del runtime sobre los SP PUBLICOS nuevos. Cada SP aplica su ambito
-- dentro (ADMINISTRADOR institucion, COORDINADOR programas, DOCENTE titularidad, ESTUDIANTE propietario). Ningun
-- GRANT a internos: usp_validar_solape_sesion_interno queda con DENY, como los demas nucleos *_sesion_interno, y
-- usp_internal_reactivar_matricula_retirada (A.1) sin permiso. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_directorio_estudiantes_paginado', N'P') IS NULL
    THROW 52301, 'CULM001_A_RUNTIME_GRANT: usp_consultar_directorio_estudiantes_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_estudiantes_grupo_ambito_paginado', N'P') IS NULL
    THROW 52302, 'CULM001_A_RUNTIME_GRANT: usp_consultar_estudiantes_grupo_ambito_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_grupo_ambito_paginado', N'P') IS NULL
    THROW 52303, 'CULM001_A_RUNTIME_GRANT: usp_consultar_asistencias_grupo_ambito_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_materias_estudiante', N'P') IS NULL
    THROW 52304, 'CULM001_A_RUNTIME_GRANT: usp_consultar_materias_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_horario_estudiante', N'P') IS NULL
    THROW 52305, 'CULM001_A_RUNTIME_GRANT: usp_consultar_horario_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_revision_asistencia', N'P') IS NULL
    THROW 52306, 'CULM001_A_RUNTIME_GRANT: usp_retirar_solicitud_revision_asistencia requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_decano', N'P') IS NULL
    THROW 52307, 'CULM001_A_RUNTIME_GRANT: usp_cambiar_estado_decano requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_buscar_estudiante_por_documento_grupo', N'P') IS NULL
    THROW 52308, 'CULM001_A_RUNTIME_GRANT: usp_buscar_estudiante_por_documento_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_validar_solape_sesion_interno', N'P') IS NULL
    THROW 52309, 'CULM001_A_RUNTIME_GRANT: usp_validar_solape_sesion_interno requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_directorio_estudiantes_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_estudiantes_grupo_ambito_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_asistencias_grupo_ambito_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_materias_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_horario_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_retirar_solicitud_revision_asistencia] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_decano] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_buscar_estudiante_por_documento_grupo] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_validar_solape_sesion_interno] TO [rol_asistencias_runtime];
GO
