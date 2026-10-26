USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU096/HU097/HU098: permisos de minimo privilegio de los SP publicos de periodos academicos.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). El nucleo interno de resolucion de
-- institucion queda denegado al runtime; toda escritura sobre dbo.PeriodoAcademico pasa por los SP publicos.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_crear_periodo_academico', N'P') IS NULL
    THROW 52150, 'HU096_HU098_RUNTIME_GRANT: usp_crear_periodo_academico requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_actualizar_periodo_academico', N'P') IS NULL
    THROW 52151, 'HU096_HU098_RUNTIME_GRANT: usp_actualizar_periodo_academico requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_eliminar_periodo_academico', N'P') IS NULL
    THROW 52152, 'HU096_HU098_RUNTIME_GRANT: usp_eliminar_periodo_academico requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_crear_periodo_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_actualizar_periodo_academico] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_eliminar_periodo_academico] TO [rol_asistencias_runtime];
DENY EXECUTE ON [dbo].[usp_resolver_institucion_gestor_periodo_interno] TO [rol_asistencias_runtime];
DENY INSERT, UPDATE, DELETE ON [dbo].[PeriodoAcademico] TO [rol_asistencias_runtime];
GO
