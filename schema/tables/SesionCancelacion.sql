USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.2): cancelacion de una sesion (1:0..1 con dbo.Sesion, que no se modifica: su guard 50004
-- prohibe columnas de estado). La crea usp_cancelar_sesion (tipo manual, HU047) o usp_internal_aplicar_festivos_grupo
-- (tipo automatico FESTIVO, con diaFestivo). usuarioEjecutor NULL solo en cancelaciones automaticas del job.
-- La coherencia tipo automatico <=> diaFestivo NOT NULL la garantizan los SP (invariante INV_SESION_CANCELACION_COHERENTE).
IF OBJECT_ID('dbo.[SesionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SesionCancelacion (
        sesion               UNIQUEIDENTIFIER NOT NULL,
        tipoCancelacion      UNIQUEIDENTIFIER NOT NULL,
        motivo               NVARCHAR(500)    NOT NULL,
        diaFestivo           UNIQUEIDENTIFIER NULL,
        usuarioEjecutor      UNIQUEIDENTIFIER NULL,
        fechaCancelacionUtc  DATETIME2(0)     NOT NULL CONSTRAINT DF_SesionCancelacion_fecha DEFAULT SYSUTCDATETIME(),
        idCorrelacion        UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_SesionCancelacion PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_SesionCancelacion_motivo CHECK (LEN(LTRIM(RTRIM(motivo))) > 0),
        CONSTRAINT CK_SesionCancelacion_origen CHECK (diaFestivo IS NOT NULL OR usuarioEjecutor IS NOT NULL)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionCancelacion') AND name = 'IX_SesionCancelacion_diaFestivo')
    CREATE NONCLUSTERED INDEX IX_SesionCancelacion_diaFestivo ON dbo.SesionCancelacion (diaFestivo) WHERE diaFestivo IS NOT NULL;
GO
