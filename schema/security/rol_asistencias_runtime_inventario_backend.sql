USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- INTEGRACION-DEVELOP-20261027: concesiones del rol de minimo privilegio para los 34 procedimientos que el codigo runtime
-- del backend invoca y que ningun script de schema/security concedia (KPIs, comparativas, directorio de docentes del
-- programa, catalogos de areas/tipos de programa/facultades/programas/coordinadores). Sin ellas, con el login runtime
-- real, esas rutas responden 500 'EXECUTE permission was denied'. Script aditivo e idempotente: no crea logins ni
-- asigna miembros; no concede EXECUTE sobre el esquema ni sobre procedimientos *_interno.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @requeridos TABLE (nombre SYSNAME PRIMARY KEY);
INSERT INTO @requeridos (nombre) VALUES
 (N'usp_actualizar_area'), (N'usp_actualizar_coordinador'), (N'usp_actualizar_docente_programa'), (N'usp_actualizar_facultad'),
 (N'usp_actualizar_programa_academico'), (N'usp_actualizar_tipo_programa'), (N'usp_cambiar_estado_area'),
 (N'usp_cambiar_estado_coordinador'), (N'usp_cambiar_estado_docente_programa'), (N'usp_cambiar_estado_facultad'),
 (N'usp_cambiar_estado_programa_academico'), (N'usp_cambiar_estado_tipo_programa'), (N'usp_consultar_aforo_grupos_facultad'),
 (N'usp_consultar_alerta_temprana_programa'), (N'usp_consultar_bitacora_estudiante_programa'),
 (N'usp_consultar_candidatos_docente_programa'), (N'usp_consultar_comparativa_facultades'),
 (N'usp_consultar_comparativa_programas_facultad'), (N'usp_consultar_detalle_solicitud_revision_docente'),
 (N'usp_consultar_docentes_programa'), (N'usp_consultar_ficha_estudiante_programa'), (N'usp_consultar_kpis_coordinador'),
 (N'usp_consultar_kpis_decano'), (N'usp_consultar_kpis_institucion'), (N'usp_consultar_programas_academicos'),
 (N'usp_consultar_resumen_asistencia_estudiante_programa'), (N'usp_consultar_resumen_docentes_programa'),
 (N'usp_consultar_historial_grupos_docente_programa'), (N'usp_consultar_tendencia_ausentismo'), (N'usp_crear_area'),
 (N'usp_crear_facultad'), (N'usp_crear_programa_academico'), (N'usp_crear_tipo_programa'), (N'usp_vincular_docente_programa');

DECLARE @faltantes NVARCHAR(MAX) = (
    SELECT STRING_AGG(r.nombre, N', ')
    FROM @requeridos AS r
    WHERE OBJECT_ID(N'dbo.' + r.nombre, N'P') IS NULL
);

IF @faltantes IS NOT NULL
BEGIN
    DECLARE @mensaje NVARCHAR(2048) = CONCAT(N'RUNTIME_GRANT_INVENTORY: procedimientos requeridos ausentes: ', @faltantes);
    THROW 52401, @mensaje, 1;
END;

DECLARE @grantSql NVARCHAR(MAX) = (
    SELECT STRING_AGG(
        CONVERT(NVARCHAR(MAX), N'GRANT EXECUTE ON OBJECT::' + QUOTENAME(N'dbo') + N'.' + QUOTENAME(r.nombre)
            + N' TO ' + QUOTENAME(N'rol_asistencias_runtime') + N';'),
        NCHAR(13) + NCHAR(10))
    FROM @requeridos AS r
);

EXEC sys.sp_executesql @grantSql;
GO
