USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: solicitud de un estudiante para ingresar a un grupo. Tabla NUEVA aprobada por John (2026-10-27,
-- skill consistencia-tablas): no modifica ninguna tabla existente. Estados en dbo.Estado: P pendiente, A aceptada
-- (se crea la matricula), R rechazada (motivo obligatorio), E en espera (sin cupo al aceptar) y X retirada por el
-- estudiante. fechaSolicitudUtc define el orden de llegada que se muestra en la lista de espera.
IF OBJECT_ID('dbo.[SolicitudIngresoGrupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SolicitudIngresoGrupo] (
    [id] uniqueidentifier NOT NULL,
    [estudiante] uniqueidentifier NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [fechaSolicitudUtc] datetime2(7) NOT NULL CONSTRAINT [DF_SolicitudIngresoGrupo_fechaSolicitudUtc] DEFAULT (SYSUTCDATETIME()),
    [fechaResolucionUtc] datetime2(7) NULL,
    [motivoRechazo] nvarchar(500) NULL,
    [docenteResolutor] uniqueidentifier NULL,
    [estudianteGrupo] uniqueidentifier NULL
);

ALTER TABLE [dbo].[SolicitudIngresoGrupo] ADD CONSTRAINT [PK_SolicitudIngresoGrupo] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- Una sola solicitud ABIERTA (pendiente B4B4D37E... o en espera C5D1E2F3...) por estudiante y grupo.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_SolicitudIngresoGrupo_Abierta' AND object_id = OBJECT_ID('dbo.SolicitudIngresoGrupo'))
    CREATE UNIQUE NONCLUSTERED INDEX [UX_SolicitudIngresoGrupo_Abierta]
        ON [dbo].[SolicitudIngresoGrupo] ([estudiante], [grupo])
        WHERE [estado] IN ('B4B4D37E-6A8F-4E1D-AF32-0B2C60E2E977', 'C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E');
GO

-- Bandeja del docente por grupo y estado, en orden de llegada.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SolicitudIngresoGrupo_Grupo_Estado_Fecha' AND object_id = OBJECT_ID('dbo.SolicitudIngresoGrupo'))
    CREATE NONCLUSTERED INDEX [IX_SolicitudIngresoGrupo_Grupo_Estado_Fecha]
        ON [dbo].[SolicitudIngresoGrupo] ([grupo], [estado], [fechaSolicitudUtc]);
GO
