USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU008: permiso del runtime para la oferta de grupos del estudiante. El SP acota el ambito al estudiante ejecutor
-- (Estudiante.usuario) y a sus programas (EstudiantePrograma). Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_consultar_oferta_grupos_estudiante', N'P') IS NULL
    THROW 52191, 'HU008_RUNTIME_GRANT: usp_consultar_oferta_grupos_estudiante requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_consultar_oferta_grupos_estudiante] TO [rol_asistencias_runtime];
GO
