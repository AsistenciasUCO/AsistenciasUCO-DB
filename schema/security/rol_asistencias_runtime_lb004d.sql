USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- LB-004D: permisos de minimo privilegio del soporte de solicitudes de revision.
--
-- Script aditivo e independiente: no modifica rol_asistencias_runtime.sql (cuyo hash esta fijado en
-- DB_UTC_D06_POST_FREEZE_MANIFEST.sha256). Idempotente y sin dependencia de orden respecto a el.
--   * Solo EXEC de los cuatro SP publicos nombrados; nunca GRANT EXECUTE ON SCHEMA::dbo.
--   * Sin acceso directo del runtime a dbo.ArchivoSoporte: toda lectura/escritura pasa por los SP
--     (encadenamiento de propiedad dbo -> dbo).
--   * Este script crea el rol si falta pero NO crea logins ni membresias (decision de despliegue).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_registrar_archivo_soporte', N'P') IS NULL
    THROW 52140, 'LB_004D_RUNTIME_GRANT: usp_registrar_archivo_soporte requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v2', N'P') IS NULL
    THROW 52141, 'LB_004D_RUNTIME_GRANT: usp_radicar_solicitud_revision_asistencia_v2 requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_archivo_soporte_autorizado', N'P') IS NULL
    THROW 52142, 'LB_004D_RUNTIME_GRANT: usp_consultar_archivo_soporte_autorizado requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_docente', N'P') IS NULL
    THROW 52143, 'LB_004D_RUNTIME_GRANT: usp_consultar_solicitudes_revision_docente requerido ausente.', 1;
IF OBJECT_ID(N'dbo.ArchivoSoporte', N'U') IS NULL
    THROW 52144, 'LB_004D_RUNTIME_GRANT: tabla ArchivoSoporte requerida ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_registrar_archivo_soporte] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_radicar_solicitud_revision_asistencia_v2] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_archivo_soporte_autorizado] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_revision_docente] TO [rol_asistencias_runtime];
DENY SELECT, INSERT, UPDATE, DELETE ON [dbo].[ArchivoSoporte] TO [rol_asistencias_runtime];
GO
