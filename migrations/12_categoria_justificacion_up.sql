USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP: HU005/HU016 - Catalogo de categorias de justificacion (solo consulta)
-- ============================================================================
-- Aditiva e idempotente. La tabla, la vista uv_categoria_justificacion, su SELECT para el runtime (bucle de vistas
-- uv_* de rol_asistencias_runtime.sql) y el seed 30_categoria_justificacion.sql tambien se despliegan con
-- deploy_schema.ps1. No toca SolicitudRevisionAsistencia ni usp_radicar_solicitud_revision_asistencia_v2 (LB-004D).
IF OBJECT_ID('dbo.CategoriaJustificacion', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CategoriaJustificacion (
        id          UNIQUEIDENTIFIER NOT NULL,
        codigo      NVARCHAR(5)      NOT NULL,
        nombre      NVARCHAR(50)     NOT NULL,
        descripcion NVARCHAR(250)    NULL,
        CONSTRAINT PK_CategoriaJustificacion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_CategoriaJustificacion_codigo UNIQUE (codigo),
        CONSTRAINT UQ_CategoriaJustificacion_nombre UNIQUE (nombre)
    );
END
GO

CREATE OR ALTER VIEW [dbo].[uv_categoria_justificacion]
AS
SELECT  id,
        codigo,
        nombre,
        descripcion
FROM    dbo.CategoriaJustificacion
GO

IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_categoria_justificacion] TO [rol_asistencias_runtime];
GO
