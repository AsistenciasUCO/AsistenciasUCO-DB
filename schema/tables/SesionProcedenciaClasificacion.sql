USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- UTC-D06-POST-FREEZE: bitacora append-only de la clasificacion administrativa UTC_OWNER.
-- Cada fila es una decision individual por sesion y ambiente, respaldada por un manifiesto
-- (identificador + hash SHA-256 de la evidencia) y un aprobador distinto del ejecutor.
-- Se escribe en la MISMA transaccion que el UPDATE de dbo.Sesion (usp_clasificar_procedencia_sesion).
IF OBJECT_ID('dbo.[SesionProcedenciaClasificacion]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SesionProcedenciaClasificacion] (
    [id] uniqueidentifier NOT NULL,
    [sesion] uniqueidentifier NOT NULL,
    [ambiente] nvarchar(32) NOT NULL,
    [idManifiesto] nvarchar(64) NOT NULL,
    [hashEvidencia] char(64) NOT NULL,
    [procedenciaAnterior] nvarchar(24) NULL,
    [procedenciaNueva] nvarchar(24) NOT NULL,
    [fechaHoraInicioAnterior] datetime2 NOT NULL,
    [fechaHoraFinAnterior] datetime2 NOT NULL,
    [fechaHoraInicioUtc] datetime2 NOT NULL,
    [fechaHoraFinUtc] datetime2 NOT NULL,
    [usuarioEjecutor] uniqueidentifier NOT NULL,
    [usuarioAprobador] uniqueidentifier NOT NULL,
    [idCorrelacion] uniqueidentifier NOT NULL,
    [fechaRegistro] datetime2 NOT NULL
);

ALTER TABLE [dbo].[SesionProcedenciaClasificacion]
    ADD CONSTRAINT [PK_SesionProcedenciaClasificacion] PRIMARY KEY CLUSTERED ([id]);
ALTER TABLE [dbo].[SesionProcedenciaClasificacion]
    ADD CONSTRAINT [DF_SesionProcedenciaClasificacion_fechaRegistro] DEFAULT (SYSUTCDATETIME()) FOR [fechaRegistro];
ALTER TABLE [dbo].[SesionProcedenciaClasificacion] WITH CHECK
    ADD CONSTRAINT [CK_SesionProcedenciaClasificacion_Nueva] CHECK ([procedenciaNueva] = N'UTC_OWNER');
ALTER TABLE [dbo].[SesionProcedenciaClasificacion] WITH CHECK
    ADD CONSTRAINT [CK_SesionProcedenciaClasificacion_Hash] CHECK ([hashEvidencia] NOT LIKE '%[^0-9a-f]%' AND LEN([hashEvidencia]) = 64);
ALTER TABLE [dbo].[SesionProcedenciaClasificacion] WITH CHECK
    ADD CONSTRAINT [CK_SesionProcedenciaClasificacion_Aprobador] CHECK ([usuarioAprobador] <> [usuarioEjecutor]);
ALTER TABLE [dbo].[SesionProcedenciaClasificacion] WITH CHECK
    ADD CONSTRAINT [FK_SesionProcedenciaClasificacion_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
CREATE UNIQUE INDEX [UX_SesionProcedenciaClasificacion_Sesion_Ambiente]
    ON [dbo].[SesionProcedenciaClasificacion] ([sesion], [ambiente]);
END
GO
