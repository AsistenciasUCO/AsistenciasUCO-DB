USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INTEGRACION-DEVELOP-20261027: concesiones del rol de minimo privilegio para los 32 procedimientos que el codigo runtime
-- del backend invoca y que ningun script de schema/security concedia (KPIs, comparativas, directorio de docentes del
-- programa, catalogos de areas/tipos de programa/facultades/programas/coordinadores). Sin ellas, con el login runtime
-- real, esas rutas responden 500 'EXECUTE permission was denied'. Script aditivo e idempotente: no crea logins ni
-- asigna miembros; no concede EXECUTE sobre el esquema ni sobre procedimientos *_interno.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_actualizar_area', N'P') IS NULL
    THROW 52401, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_area requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_coordinador', N'P') IS NULL
    THROW 52402, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_coordinador requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_docente_programa', N'P') IS NULL
    THROW 52403, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_docente_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_facultad', N'P') IS NULL
    THROW 52404, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_programa_academico', N'P') IS NULL
    THROW 52405, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_programa_academico requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_tipo_programa', N'P') IS NULL
    THROW 52406, 'RUNTIME_GRANT_INVENTORY: usp_actualizar_tipo_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_area', N'P') IS NULL
    THROW 52407, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_area requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_coordinador', N'P') IS NULL
    THROW 52408, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_coordinador requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_docente_programa', N'P') IS NULL
    THROW 52409, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_docente_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_facultad', N'P') IS NULL
    THROW 52410, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_programa_academico', N'P') IS NULL
    THROW 52411, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_programa_academico requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_cambiar_estado_tipo_programa', N'P') IS NULL
    THROW 52412, 'RUNTIME_GRANT_INVENTORY: usp_cambiar_estado_tipo_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_aforo_grupos_facultad', N'P') IS NULL
    THROW 52413, 'RUNTIME_GRANT_INVENTORY: usp_consultar_aforo_grupos_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_alerta_temprana_programa', N'P') IS NULL
    THROW 52414, 'RUNTIME_GRANT_INVENTORY: usp_consultar_alerta_temprana_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_bitacora_estudiante_programa', N'P') IS NULL
    THROW 52415, 'RUNTIME_GRANT_INVENTORY: usp_consultar_bitacora_estudiante_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_candidatos_docente_programa', N'P') IS NULL
    THROW 52416, 'RUNTIME_GRANT_INVENTORY: usp_consultar_candidatos_docente_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_comparativa_facultades', N'P') IS NULL
    THROW 52417, 'RUNTIME_GRANT_INVENTORY: usp_consultar_comparativa_facultades requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_comparativa_programas_facultad', N'P') IS NULL
    THROW 52418, 'RUNTIME_GRANT_INVENTORY: usp_consultar_comparativa_programas_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_detalle_solicitud_revision_docente', N'P') IS NULL
    THROW 52419, 'RUNTIME_GRANT_INVENTORY: usp_consultar_detalle_solicitud_revision_docente requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_docentes_programa', N'P') IS NULL
    THROW 52420, 'RUNTIME_GRANT_INVENTORY: usp_consultar_docentes_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_ficha_estudiante_programa', N'P') IS NULL
    THROW 52421, 'RUNTIME_GRANT_INVENTORY: usp_consultar_ficha_estudiante_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_kpis_coordinador', N'P') IS NULL
    THROW 52422, 'RUNTIME_GRANT_INVENTORY: usp_consultar_kpis_coordinador requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_kpis_decano', N'P') IS NULL
    THROW 52423, 'RUNTIME_GRANT_INVENTORY: usp_consultar_kpis_decano requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_kpis_institucion', N'P') IS NULL
    THROW 52424, 'RUNTIME_GRANT_INVENTORY: usp_consultar_kpis_institucion requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_programas_academicos', N'P') IS NULL
    THROW 52425, 'RUNTIME_GRANT_INVENTORY: usp_consultar_programas_academicos requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_estudiante_programa', N'P') IS NULL
    THROW 52426, 'RUNTIME_GRANT_INVENTORY: usp_consultar_resumen_asistencia_estudiante_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_tendencia_ausentismo', N'P') IS NULL
    THROW 52427, 'RUNTIME_GRANT_INVENTORY: usp_consultar_tendencia_ausentismo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_crear_area', N'P') IS NULL
    THROW 52428, 'RUNTIME_GRANT_INVENTORY: usp_crear_area requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_crear_facultad', N'P') IS NULL
    THROW 52429, 'RUNTIME_GRANT_INVENTORY: usp_crear_facultad requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_crear_programa_academico', N'P') IS NULL
    THROW 52430, 'RUNTIME_GRANT_INVENTORY: usp_crear_programa_academico requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_crear_tipo_programa', N'P') IS NULL
    THROW 52431, 'RUNTIME_GRANT_INVENTORY: usp_crear_tipo_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_vincular_docente_programa', N'P') IS NULL
    THROW 52432, 'RUNTIME_GRANT_INVENTORY: usp_vincular_docente_programa requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_actualizar_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_coordinador] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_docente_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_programa_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_tipo_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_coordinador] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_docente_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_programa_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_cambiar_estado_tipo_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_aforo_grupos_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_alerta_temprana_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_bitacora_estudiante_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_candidatos_docente_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_comparativa_facultades] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_comparativa_programas_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_detalle_solicitud_revision_docente] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_docentes_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_ficha_estudiante_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_kpis_coordinador] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_kpis_decano] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_kpis_institucion] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_programas_academicos] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_resumen_asistencia_estudiante_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_tendencia_ausentismo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_area] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_facultad] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_programa_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_crear_tipo_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_vincular_docente_programa] TO [rol_asistencias_runtime];
GO
