USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: postura de permisos para el principal runtime del backend.
--
-- * rol_asistencias_runtime: EXEC de los SP publicos + SELECT de las vistas. Sin DML directo sobre
--   dbo.Sesion: toda escritura de horas pasa por SP que reafirman procedenciaTemporal en la misma
--   sentencia (encadenamiento de propiedad dbo -> dbo, sin conceder permisos sobre la tabla).
-- * DENY EXECUTE sobre los nucleos *_sesion_interno (solo alcanzables desde los wrappers v1/v2) y
--   sobre la clasificacion administrativa UTC_OWNER.
-- * rol_asistencias_clasificador_temporal: unico rol con EXEC de usp_clasificar_procedencia_sesion.
--
-- Este script crea los roles y permisos; NO crea logins ni asigna miembros. Mapear el login real del
-- backend a rol_asistencias_runtime es una decision de despliegue por ambiente (DB_PRINCIPAL_HARDENING
-- del addendum DB-GP-001C): mientras el backend use un principal sysadmin/db_owner, estos DENY no le
-- aplican y la unica defensa ante DML directo es tr_Sesion_procedencia_temporal.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_clasificador_temporal') IS NULL
    CREATE ROLE [rol_asistencias_clasificador_temporal] AUTHORIZATION [dbo];
GO

GRANT EXECUTE ON SCHEMA::[dbo] TO [rol_asistencias_runtime];
GO

-- Lectura solo de vistas uv_*: se concede vista por vista (no SELECT ON SCHEMA, que incluiria tablas).
DECLARE @vista SYSNAME, @sql NVARCHAR(MAX);
DECLARE vistas CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.views WHERE schema_id = SCHEMA_ID(N'dbo') AND name LIKE N'uv[_]%' ORDER BY name;
OPEN vistas;
FETCH NEXT FROM vistas INTO @vista;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'GRANT SELECT ON [dbo].' + QUOTENAME(@vista) + N' TO [rol_asistencias_runtime];';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM vistas INTO @vista;
END
CLOSE vistas;
DEALLOCATE vistas;
GO

-- Unica tabla que el backend escribe directamente (AuditEventEntity, LB-008 JPA-06B).
GRANT SELECT, INSERT ON [dbo].[AuditoriaEvento] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[Sesion] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[SesionProcedenciaClasificacion] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_crear_sesion_interno] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_actualizar_sesion_interno] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_clasificar_procedencia_sesion] TO [rol_asistencias_runtime];
GO

GRANT EXECUTE ON [dbo].[usp_clasificar_procedencia_sesion] TO [rol_asistencias_clasificador_temporal];
GRANT SELECT ON [dbo].[uv_sesion_v2] TO [rol_asistencias_clasificador_temporal];
GRANT SELECT ON [dbo].[SesionProcedenciaClasificacion] TO [rol_asistencias_clasificador_temporal];
GO
