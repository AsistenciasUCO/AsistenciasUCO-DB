USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: permisos del runtime para las solicitudes de ingreso a grupo. Cada SP valida el ambito en
-- tablas base (estudiante propietario o docente titular). Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_registrar_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52183, 'HU053_HU055_RUNTIME_GRANT: usp_registrar_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_resolver_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52184, 'HU053_HU055_RUNTIME_GRANT: usp_resolver_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52185, 'HU053_HU055_RUNTIME_GRANT: usp_retirar_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_grupo_docente', N'P') IS NULL
    THROW 52186, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_solicitudes_ingreso_grupo_docente requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_estudiante', N'P') IS NULL
    THROW 52187, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_solicitudes_ingreso_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52188, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_destinatarios_solicitud_ingreso_grupo requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_registrar_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_resolver_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_retirar_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_ingreso_grupo_docente] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_ingreso_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GO
