USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- LB-004D (ONE_TABLE): metadata durable del soporte de una solicitud de revision de asistencia.
-- Los bytes viven fuera de SQL (storage de objetos); aqui solo se conserva lo necesario para
-- identificar, autorizar, vincular y verificar la integridad. No se persisten bucket, objectKey,
-- URL ni datos de compresion: son detalle de Infrastructure y permiten cambiar de proveedor
-- (MinIO -> Azure Blob / S3) sin tocar fileId ni relaciones academicas.
--
-- Convencion temporal: las columnas *Utc son instantes UTC en DATETIME2(7) (contrato UTC v2).
-- DATETIME2 no almacena zona; el contrato es UTC por nombre de columna. Se generan con
-- SYSUTCDATETIME(), nunca con GETDATE()/CURRENT_TIMESTAMP.
--
-- Las FK viven en zz_foreign_keys.sql (se despliegan tras todas las tablas).
IF OBJECT_ID('dbo.[ArchivoSoporte]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[ArchivoSoporte] (
        [id]                          uniqueidentifier NOT NULL,
        [usuarioPropietario]          uniqueidentifier NOT NULL,
        [solicitudRevisionAsistencia] uniqueidentifier NULL,
        [nombreOriginal]              nvarchar(250)    NOT NULL,
        [tipoContenido]               varchar(50)      NOT NULL,
        [tamanioBytes]                bigint           NOT NULL,
        [checksumSha256]              char(64)         NOT NULL,
        [estado]                      varchar(10)      NOT NULL,
        [fechaRegistroUtc]            datetime2(7)     NOT NULL,
        [fechaAdjuncionUtc]           datetime2(7)     NULL,
        [fechaCambioEstadoUtc]        datetime2(7)     NOT NULL,
        [idCorrelacionRegistro]       uniqueidentifier NOT NULL,
        [idCorrelacionAdjuncion]      uniqueidentifier NULL,
        CONSTRAINT [PK_ArchivoSoporte] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [CK_ArchivoSoporte_Estado]
            CHECK ([estado] IN ('DRAFT', 'ATTACHED', 'ORPHAN')),
        CONSTRAINT [CK_ArchivoSoporte_TipoContenido]
            CHECK ([tipoContenido] IN ('application/pdf', 'image/png', 'image/jpeg')),
        CONSTRAINT [CK_ArchivoSoporte_Tamanio]
            CHECK ([tamanioBytes] > 0),
        CONSTRAINT [CK_ArchivoSoporte_Checksum]
            CHECK (LEN([checksumSha256]) = 64 AND [checksumSha256] NOT LIKE '%[^0-9a-f]%' COLLATE Latin1_General_BIN),
        CONSTRAINT [CK_ArchivoSoporte_EstadoVinculo]
            CHECK (
                ([estado] = 'ATTACHED'
                    AND [solicitudRevisionAsistencia] IS NOT NULL
                    AND [fechaAdjuncionUtc] IS NOT NULL
                    AND [idCorrelacionAdjuncion] IS NOT NULL)
                OR
                ([estado] IN ('DRAFT', 'ORPHAN')
                    AND [solicitudRevisionAsistencia] IS NULL
                    AND [fechaAdjuncionUtc] IS NULL
                    AND [idCorrelacionAdjuncion] IS NULL)
            )
    );
END
GO

-- A lo sumo un soporte por solicitud (un fileId solo puede estar en una solicitud por la PK).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'UX_ArchivoSoporte_Solicitud'
)
    CREATE UNIQUE NONCLUSTERED INDEX [UX_ArchivoSoporte_Solicitud]
    ON [dbo].[ArchivoSoporte] ([solicitudRevisionAsistencia])
    WHERE [solicitudRevisionAsistencia] IS NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.ArchivoSoporte') AND name = 'IX_ArchivoSoporte_UsuarioPropietario'
)
    CREATE NONCLUSTERED INDEX [IX_ArchivoSoporte_UsuarioPropietario]
    ON [dbo].[ArchivoSoporte] ([usuarioPropietario]);
GO
