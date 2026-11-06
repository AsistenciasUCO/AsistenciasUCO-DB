USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN: HU176B. Revierte la ventana de matricula por QR/PIN.
-- El SP usp_registrar_estudiante_en_grupo_autonomo retirado (D6) NO se restaura: no tenia consumidores y era inseguro.
-- ============================================================================

IF OBJECT_ID(N'dbo.usp_abrir_ventana_matricula_grupo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_abrir_ventana_matricula_grupo;
GO
IF OBJECT_ID(N'dbo.usp_cerrar_ventana_matricula_grupo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_cerrar_ventana_matricula_grupo;
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_grupo', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_rotar_token_matricula_grupo;
GO
IF OBJECT_ID(N'dbo.usp_consultar_ventanas_matricula_por_rotar', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_ventanas_matricula_por_rotar;
GO
IF OBJECT_ID(N'dbo.usp_validar_token_matricula_publico', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_validar_token_matricula_publico;
GO
IF OBJECT_ID(N'dbo.usp_matricular_estudiante_por_token', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_matricular_estudiante_por_token;
GO
IF OBJECT_ID(N'dbo.usp_rotar_token_matricula_automatico', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_rotar_token_matricula_automatico;
GO
IF OBJECT_ID(N'dbo.usp_registrar_estudiante_por_token_publico', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_registrar_estudiante_por_token_publico;
GO
IF OBJECT_ID(N'dbo.usp_internal_rotar_token_matricula', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_rotar_token_matricula;
GO
IF OBJECT_ID(N'dbo.usp_internal_matricular_por_token', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_matricular_por_token;
GO
IF OBJECT_ID(N'dbo.usp_internal_resolver_token_matricula', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_resolver_token_matricula;
GO
IF OBJECT_ID(N'dbo.uv_token_matricula_grupo', N'V') IS NOT NULL DROP VIEW dbo.uv_token_matricula_grupo;
GO
IF OBJECT_ID(N'dbo.TokenMatriculaGrupo', N'U') IS NOT NULL DROP TABLE dbo.TokenMatriculaGrupo;
GO

DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('MQR_001','MQR_002','MQR_003','MQR_004','MQR_005','MQR_006','MQR_007');
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('MQR_001','MQR_002','MQR_003','MQR_004','MQR_005','MQR_006','MQR_007');
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA_QR';
GO
