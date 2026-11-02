USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F2 (2026-11-02): permiso de minimo privilegio de la precarga de sesiones del grupo. Script aditivo e idempotente (no
-- modifica rol_asistencias_runtime.sql). El runtime ejecuta el SP publico; el nucleo interno queda denegado y el DML directo
-- sobre dbo.Sesion ya esta denegado por rol_asistencias_runtime.sql.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo', N'P') IS NULL
    THROW 52196, 'F2_PRECARGA_SESIONES_RUNTIME_GRANT: usp_precargar_sesiones_grupo requerido ausente.', 1;
GO

IF OBJECT_ID(N'dbo.usp_precargar_sesiones_grupo_interno', N'P') IS NULL
    THROW 52197, 'F2_PRECARGA_SESIONES_RUNTIME_GRANT: usp_precargar_sesiones_grupo_interno requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_precargar_sesiones_grupo] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_precargar_sesiones_grupo_interno] TO [rol_asistencias_runtime];
GO
