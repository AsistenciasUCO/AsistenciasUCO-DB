USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
GO

-- ============================================================================
-- INTEGRACION-DEVELOP-20261027: el rol de minimo privilegio rol_asistencias_runtime debe tener EXECUTE sobre TODOS los
-- procedimientos que el codigo runtime del backend invoca. Contra SQL Server real, un SP sin concesion produce
-- "The EXECUTE permission was denied" => 500 DATABASE_OPERATION_ERROR (KPIs del decano/coordinador/administrador,
-- directorio de docentes del programa, catalogos de areas, etc.). Inventario derivado de src/main/java del backend.
-- ============================================================================
PRINT 'TEST START: test_runtime_grants_backend_inventory';

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

DECLARE @sinConcesion NVARCHAR(MAX) = (
    SELECT STRING_AGG(r.nombre, ', ')
    FROM @requeridos r
    WHERE OBJECT_ID(N'dbo.' + r.nombre, N'P') IS NULL
       OR NOT EXISTS (
            SELECT 1 FROM sys.database_permissions dp
            JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
            WHERE dp.major_id = OBJECT_ID(N'dbo.' + r.nombre, N'P') AND dp.permission_name = N'EXECUTE'
              AND dp.state IN ('G', 'W') AND pr.name = N'rol_asistencias_runtime'));

IF @sinConcesion IS NOT NULL
BEGIN
    DECLARE @mensaje NVARCHAR(2000) = CONCAT(N'TEST FAILED: RUNTIME_GRANTS_BACKEND_INVENTORY sin EXECUTE para rol_asistencias_runtime: ', @sinConcesion);
    THROW 52400, @mensaje, 1;
END

PRINT 'TEST PASS: test_runtime_grants_backend_inventory';
PRINT 'TEST_PASS:RUNTIME_GRANTS_BACKEND_INVENTORY';
GO
