USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU010/HU011 (consulta): permiso de lectura del runtime para "Mis Reclamos" del estudiante. El SP filtra por
-- el estudiante ejecutor (Estudiante.usuario) uniendo tablas base. Script aditivo e idempotente
-- (no modifica rol_asistencias_runtime.sql ni rol_asistencias_runtime_lb004d.sql).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_revision_estudiante', N'P') IS NULL
    THROW 52180, 'HU010_HU011_RUNTIME_GRANT: usp_consultar_solicitudes_revision_estudiante requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_revision_estudiante] TO [rol_asistencias_runtime];
GO
