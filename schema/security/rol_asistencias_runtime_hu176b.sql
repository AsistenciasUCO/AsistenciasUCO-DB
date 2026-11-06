USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: permisos de ejecucion de la matricula por QR/PIN rotativo.
-- Solo EXECUTE sobre los SP publicos; sin DML directo sobre dbo.TokenMatriculaGrupo. Aditivo e idempotente.
-- Los usp_internal_* (resolver, rotar, matricular) son internos y NO se conceden.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_abrir_ventana_matricula_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_cerrar_ventana_matricula_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_cerrar_ventana_matricula_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_grupo', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_rotar_token_matricula_grupo] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_automatico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_rotar_token_matricula_automatico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_registrar_estudiante_por_token_publico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_registrar_estudiante_por_token_publico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_ventanas_matricula_por_rotar', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_ventanas_matricula_por_rotar] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_validar_token_matricula_publico', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_validar_token_matricula_publico] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_matricular_estudiante_por_token', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_matricular_estudiante_por_token] TO [rol_asistencias_runtime];
GO
