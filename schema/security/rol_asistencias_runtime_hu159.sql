USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159: permiso del runtime para corregir los datos de identidad de estudiantes (coordinador) y decanos (administrador).
-- El SP valida RBAC y el ambito por jerarquia en tablas base.
-- Los internos (usp_corregir_identidad_usuario_interno, usp_corregir_documento_usuario_interno,
-- usp_registrar_auditoria_identidad_interno) NO reciben permisos (encadenamiento de propietario).
-- Script aditivo e idempotente (no modifica rol_asistencias_runtime.sql).
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_corregir_identidad_usuario', N'P') IS NULL
    THROW 52198, 'HU159_RUNTIME_GRANT: usp_corregir_identidad_usuario requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_corregir_identidad_usuario] TO [rol_asistencias_runtime];
GO
