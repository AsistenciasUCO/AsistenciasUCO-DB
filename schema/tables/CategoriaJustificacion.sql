USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU005/HU016: categorias con las que el estudiante justifica una inasistencia o llegada tarde al radicar un reclamo.
-- Catalogo base de solo consulta (regla de John, 2026-11-04): se carga por seed, sin SP de escritura.
-- Todavia no se relaciona con SolicitudRevisionAsistencia: la FK y su persistencia por el SP de radicacion (TD-060)
-- tocan objetos del manifiesto LB-004D y van en un cambio coordinado aparte.
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
