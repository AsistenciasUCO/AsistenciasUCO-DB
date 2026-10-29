USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- GESTION INSTITUCIONAL (programas, facultades, tipos de programa, coordinadores, docentes por programa):
-- permisos de minimo privilegio de los SP publicos que el backend invoca como principal de runtime.
--
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql, cuyo hash esta fijado en su manifiesto).
-- Hasta ahora estos SP solo funcionaban porque el backend corria como sysadmin; con el login de runtime
-- (rol_asistencias_runtime, sin `sa`) respondian 500 por EXECUTE denegado. Solo se concede EXEC de los SP
-- publicos nombrados; nunca `GRANT EXECUTE ON SCHEMA::dbo` ni acceso a los nucleos *_interno.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

DECLARE @procedimiento SYSNAME, @sql NVARCHAR(MAX);
DECLARE procedimientos CURSOR LOCAL FAST_FORWARD FOR
    SELECT nombre
    FROM (VALUES
        (N'usp_actualizar_coordinador'),
        (N'usp_actualizar_docente_programa'),
        (N'usp_actualizar_facultad'),
        (N'usp_actualizar_programa_academico'),
        (N'usp_actualizar_tipo_programa'),
        (N'usp_cambiar_estado_coordinador'),
        (N'usp_cambiar_estado_docente_programa'),
        (N'usp_cambiar_estado_facultad'),
        (N'usp_cambiar_estado_programa_academico'),
        (N'usp_cambiar_estado_tipo_programa'),
        (N'usp_consultar_candidatos_docente_programa'),
        (N'usp_consultar_detalle_solicitud_revision_docente'),
        (N'usp_consultar_docentes_programa'),
        (N'usp_consultar_programas_academicos'),
        (N'usp_crear_facultad'),
        (N'usp_crear_programa_academico'),
        (N'usp_crear_tipo_programa'),
        (N'usp_vincular_docente_programa')
    ) AS requeridos(nombre)
    ORDER BY nombre;
OPEN procedimientos;
FETCH NEXT FROM procedimientos INTO @procedimiento;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'dbo.' + @procedimiento, N'P') IS NULL
    BEGIN
        DECLARE @mensaje NVARCHAR(400) = N'GESTION_INSTITUCIONAL_RUNTIME_GRANT: ' + @procedimiento + N' requerido ausente.';
        THROW 52180, @mensaje, 1;
    END;
    SET @sql = N'GRANT EXECUTE ON ' + QUOTENAME(N'dbo') + N'.' + QUOTENAME(@procedimiento) + N' TO [rol_asistencias_runtime];';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM procedimientos INTO @procedimiento;
END;
CLOSE procedimientos;
DEALLOCATE procedimientos;
GO
