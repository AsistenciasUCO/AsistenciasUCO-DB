USE [gestionasistenciadb];
GO
SET NOCOUNT ON;

IF DB_NAME() <> 'gestionasistenciadb'
    THROW 51900, 'TEST FAILED: public objects are not in gestionasistenciadb.', 1;

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Grupo') AND name = 'docente')
    THROW 51901, 'TEST FAILED: dbo.Grupo.docente missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Sesion') AND name = 'fechaHoraInicio')
    THROW 51902, 'TEST FAILED: dbo.Sesion.fechaHoraInicio missing.', 1;
PRINT 'TEST_PASS:SCHEMA_COLUMNS';

IF (SELECT COUNT(*) FROM sys.parameters p JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo' AND p.system_type_id = TYPE_ID('int') AND
    ((sp.name = 'usp_crear_grupo' AND p.name = '@codigo') OR
     (sp.name = 'usp_actualizar_grupo' AND p.name IN ('@codigo', '@cupoMaximo')))) >= 2
    PRINT 'TEST_PASS:PUBLIC_SIGNATURES';
ELSE
    THROW 51903, 'TEST FAILED: PUBLIC_SIGNATURES expected INT codigo/cupoMaximo public parameters.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.parameters p
    JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
      AND sp.name IN ('usp_crear_grupo', 'usp_actualizar_grupo')
      AND p.name IN (CHAR(64) + N'au' + N'la')
)
    THROW 51904, 'TEST FAILED: GROUP_PUBLIC_SIGNATURE exposes ghost parameter.', 1;
PRINT 'TEST_PASS:GROUP_PUBLIC_SIGNATURE';

IF EXISTS (
    SELECT 1
    FROM sys.parameters p
    JOIN sys.procedures sp ON sp.object_id = p.object_id
    WHERE SCHEMA_NAME(sp.schema_id) = 'dbo'
      AND sp.name IN ('usp_crear_sesion', 'usp_actualizar_sesion')
      AND p.name IN (CHAR(64) + N'au' + N'la', '@descripcion', '@tipo', '@status', '@cerrada', '@idDocente')
)
    THROW 51905, 'TEST FAILED: SESSION_PUBLIC_SIGNATURE exposes session ghost parameters.', 1;
PRINT 'TEST_PASS:SESSION_PUBLIC_SIGNATURE';

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Sesion')
      AND name IN (N'au' + N'la', 'descripcion', 'tipo', 'status', 'estado', 'cerrada')
)
    THROW 51915, 'TEST FAILED: NO_SESSION_GHOST_FIELDS found ghost column on dbo.Sesion.', 1;
PRINT 'TEST_PASS:NO_SESSION_GHOST_FIELDS';

DECLARE @view SYSNAME, @sql NVARCHAR(MAX), @refreshed INT = 0;
DECLARE view_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID('dbo') AND name LIKE 'uv[_]%' ORDER BY name;
OPEN view_cursor;
FETCH NEXT FROM view_cursor INTO @view;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sys.sp_refreshview @viewname = @view;
        SET @sql = N'SELECT TOP (0) * FROM dbo.' + QUOTENAME(@view);
        EXEC sys.sp_executesql @sql;
        SET @refreshed += 1;
    END TRY
    BEGIN CATCH
        CLOSE view_cursor;
        DEALLOCATE view_cursor;
        DECLARE @failure NVARCHAR(2048) = CONCAT('TEST FAILED: view refresh/compile ', @view, ': ', ERROR_MESSAGE());
        THROW 51906, @failure, 1;
    END CATCH;
    FETCH NEXT FROM view_cursor INTO @view;
END;
CLOSE view_cursor;
DEALLOCATE view_cursor;
IF @refreshed = 0 THROW 51907, 'TEST FAILED: no public views found.', 1;
PRINT CONCAT('PUBLIC_VIEWS_REFRESHED=', @refreshed);
PRINT 'TEST_PASS:PUBLIC_VIEWS_REFRESH';

IF EXISTS (
    SELECT 1 FROM sys.sql_expression_dependencies d
    JOIN sys.objects o ON o.object_id = d.referencing_id
    WHERE SCHEMA_NAME(o.schema_id) = 'dbo'
      AND d.referenced_database_name IS NULL
      AND d.referenced_schema_name = 'dbo'
      AND d.referenced_id IS NULL
      AND OBJECT_ID(QUOTENAME(d.referenced_schema_name) + '.' + QUOTENAME(d.referenced_entity_name)) IS NULL
)
    THROW 51908, 'TEST FAILED: broken dbo SQL expression dependencies.', 1;
PRINT 'TEST_PASS:BROKEN_DEPENDENCIES_ZERO';
GO

-- Contrato publico de lectura de asistencia (backend AsistenciasUCO):
--   SELECT da.codigoRazonCausa AS estado FROM dbo.uv_detalle_asistencia da
-- Si alguien retira estas columnas el backend deja de poder leer el estado de asistencia.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_razon_causa') AND name = 'codigo')
    THROW 51909, 'TEST FAILED: VIEW_RAZON_CAUSA_CONTRACT dbo.uv_razon_causa no expone la columna codigo.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_razon_causa') AND name = 'id')
    OR NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_razon_causa') AND name = 'nombre')
    THROW 51910, 'TEST FAILED: VIEW_RAZON_CAUSA_CONTRACT dbo.uv_razon_causa perdio id o nombre.', 1;
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (0) rc.codigo FROM dbo.uv_razon_causa rc;';
END TRY
BEGIN CATCH
    DECLARE @rcFailure NVARCHAR(2048) = CONCAT('TEST FAILED: VIEW_RAZON_CAUSA_CONTRACT SELECT rc.codigo no compila: ', ERROR_MESSAGE());
    THROW 51911, @rcFailure, 1;
END CATCH;
PRINT 'TEST_PASS:VIEW_RAZON_CAUSA_CONTRACT';

IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_detalle_asistencia')
        AND name IN ('idRazonCausa', 'codigoRazonCausa', 'nombreRazonCausa')) <> 3
    THROW 51912, 'TEST FAILED: VIEW_DETALLE_ASISTENCIA_CONTRACT falta idRazonCausa/codigoRazonCausa/nombreRazonCausa.', 1;
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.uv_detalle_asistencia')
        AND name IN ('id', 'codigo', 'idAsistencia', 'asistio', 'fechaHoraInicio', 'fechaHoraFin')) <> 6
    THROW 51913, 'TEST FAILED: VIEW_DETALLE_ASISTENCIA_CONTRACT perdio columnas preexistentes.', 1;
BEGIN TRY
    EXEC sys.sp_executesql N'SELECT TOP (0) da.codigoRazonCausa FROM dbo.uv_detalle_asistencia da;';
END TRY
BEGIN CATCH
    DECLARE @daFailure NVARCHAR(2048) = CONCAT('TEST FAILED: VIEW_DETALLE_ASISTENCIA_CONTRACT SELECT da.codigoRazonCausa no compila: ', ERROR_MESSAGE());
    THROW 51914, @daFailure, 1;
END CATCH;
PRINT 'TEST_PASS:VIEW_DETALLE_ASISTENCIA_CONTRACT';
GO
