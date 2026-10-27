USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU051: permisos del runtime para que el docente titular retire a un estudiante de su grupo y para consultar los
-- destinatarios del aviso. Ambos SP verifican la titularidad (Grupo.docente -> Docente.usuario) en tablas base.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_retirar_estudiante_grupo', N'P') IS NULL
    THROW 52181, 'HU051_RUNTIME_GRANT: usp_retirar_estudiante_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_retiro_estudiante_grupo', N'P') IS NULL
    THROW 52182, 'HU051_RUNTIME_GRANT: usp_consultar_destinatarios_retiro_estudiante_grupo requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_retirar_estudiante_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_retiro_estudiante_grupo] TO [rol_asistencias_runtime];
GO
