USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU094/HU095: permisos del runtime para la ficha del docente (historial de grupos) y el consolidado del directorio
-- docente del programa del coordinador.
-- Los SP resuelven el programa del ejecutor en tablas base. Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_historial_grupos_docente_programa', N'P') IS NULL
    THROW 52189, 'HU094_RUNTIME_GRANT: usp_consultar_historial_grupos_docente_programa requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_resumen_docentes_programa', N'P') IS NULL
    THROW 52190, 'HU095_RUNTIME_GRANT: usp_consultar_resumen_docentes_programa requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_historial_grupos_docente_programa] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_resumen_docentes_programa] TO [rol_asistencias_runtime];
GO
