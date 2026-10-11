USE [gestionasistenciadb];
GO
/*
  MAINT-003K - limpieza de los fixtures sinteticos de desarrollo (paginacion).
  Solo toca filas cuyo id empieza por el prefijo reservado 'DE0000' (ver dev_pagination_fixture.sql).
  Idempotente. NO es un seed de despliegue: se ejecuta solo con deploy_dev_fixtures.ps1 contra un contenedor Developer.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE 'Developer%'
    THROW 55001, 'BLOCKED - dev fixtures only run on SQL Server Developer Edition.', 1;
IF DB_NAME() <> N'gestionasistenciadb'
    THROW 55002, 'BLOCKED - unexpected database for dev fixtures.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 55003, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;

BEGIN TRANSACTION;

DELETE r FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Asistencia a ON a.id = r.asistencia WHERE LEFT(CONVERT(CHAR(36), a.id), 6) = 'DE0000';
DELETE FROM dbo.DetalleAsistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Asistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.SesionProcedenciaClasificacion WHERE LEFT(CONVERT(CHAR(36), sesion), 6) = 'DE0000';
DELETE FROM dbo.Sesion WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.EstudianteGrupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Grupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.EstudiantePrograma WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Docente WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';
DELETE FROM dbo.Usuario WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000';

COMMIT TRANSACTION;
PRINT 'DEV_FIXTURE_CLEANUP_OK';
GO
