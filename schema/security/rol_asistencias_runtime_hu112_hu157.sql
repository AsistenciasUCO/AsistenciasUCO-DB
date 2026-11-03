USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU112/HU128/HU143/HU157: permisos de lectura del runtime para la tabla unificada de programas y creditos, el
-- directorio de docentes de la facultad, la busqueda transversal de asignaturas y la ficha unificada del estudiante
-- (buscador del administrador e historial). Los SP filtran por el ejecutor (uv_auth_* o su institucion).
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). El interno compartido
-- usp_validar_consulta_paginada_interno NO recibe permisos (lo invocan los SP publicos por encadenamiento de propietario).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_programas_creditos_facultad_paginado', N'P') IS NULL
    THROW 56100, 'HU112_HU157_RUNTIME_GRANT: usp_consultar_programas_creditos_facultad_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_docentes_facultad_paginado', N'P') IS NULL
    THROW 56101, 'HU112_HU157_RUNTIME_GRANT: usp_consultar_docentes_facultad_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_buscar_asignaturas_paginado', N'P') IS NULL
    THROW 56102, 'HU112_HU157_RUNTIME_GRANT: usp_buscar_asignaturas_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_buscar_estudiantes_institucion_paginado', N'P') IS NULL
    THROW 56103, 'HU112_HU157_RUNTIME_GRANT: usp_buscar_estudiantes_institucion_paginado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_historial_estudiante', N'P') IS NULL
    THROW 56104, 'HU112_HU157_RUNTIME_GRANT: usp_consultar_historial_estudiante requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_programas_creditos_facultad_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_docentes_facultad_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_buscar_asignaturas_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_buscar_estudiantes_institucion_paginado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_historial_estudiante] TO [rol_asistencias_runtime];
GO
