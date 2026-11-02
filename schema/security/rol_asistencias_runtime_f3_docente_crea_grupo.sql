USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F3 (2026-11-02): permiso de minimo privilegio de la consulta que alimenta el formulario "Nuevo grupo" del docente.
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql). usp_crear_grupo y usp_guardar_horarios_grupo
-- ya tienen EXECUTE para el runtime; F3 solo agrega la consulta de oferta.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_oferta_creacion_grupo_docente', N'P') IS NULL
    THROW 52195, 'F3_DOCENTE_CREA_GRUPO_RUNTIME_GRANT: usp_consultar_oferta_creacion_grupo_docente requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_oferta_creacion_grupo_docente] TO [rol_asistencias_runtime];
GO
