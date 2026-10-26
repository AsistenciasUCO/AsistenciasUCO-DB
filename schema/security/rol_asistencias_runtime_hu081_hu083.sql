USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU081/HU082/HU083: permisos de minimo privilegio de los SP publicos de estado y semestres del plan de estudios.
--
-- Script aditivo e idempotente, igual que rol_asistencias_runtime_cc003g01.sql: no modifica
-- rol_asistencias_runtime.sql (hash fijado en su manifiesto). Solo EXEC de los SP publicos nombrados;
-- toda escritura sobre dbo.PlanEstudio y dbo.SemestrePlanEstudio pasa por ellos (encadenamiento dbo -> dbo).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_cambiar_estado_plan_estudio', N'P') IS NULL
    THROW 52140, 'HU081_HU083_RUNTIME_GRANT: usp_cambiar_estado_plan_estudio requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_agregar_semestre_plan_estudio', N'P') IS NULL
    THROW 52141, 'HU081_HU083_RUNTIME_GRANT: usp_agregar_semestre_plan_estudio requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_quitar_semestre_plan_estudio', N'P') IS NULL
    THROW 52142, 'HU081_HU083_RUNTIME_GRANT: usp_quitar_semestre_plan_estudio requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_cambiar_estado_plan_estudio] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_agregar_semestre_plan_estudio] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_quitar_semestre_plan_estudio] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[SemestrePlanEstudio] TO [rol_asistencias_runtime];
GO
