USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.[AuditoriaEvento]', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[AuditoriaEvento] (
        [id]            UNIQUEIDENTIFIER   NOT NULL,
        [occurredAt]    DATETIMEOFFSET (7) NOT NULL,
        [actorId]       NVARCHAR (120)     NULL,
        [actorType]     VARCHAR (20)       NOT NULL,
        [action]        VARCHAR (120)      NOT NULL,
        [resourceType]  VARCHAR (120)      NOT NULL,
        [resourceId]    NVARCHAR (120)     NULL,
        [result]        VARCHAR (20)       NOT NULL,
        [correlationId] UNIQUEIDENTIFIER   NULL,
        [traceId]       CHAR (32)          NULL,
        [spanId]        CHAR (16)          NULL,
        [httpMethod]    VARCHAR (16)       NOT NULL,
        [path]          NVARCHAR (240)     NOT NULL,
        [httpStatus]    SMALLINT           NOT NULL,
        [clientIp]      VARCHAR (45)       NULL,
        [errorCode]     VARCHAR (120)      NULL,
        [metadata]      NVARCHAR (MAX)     NULL,
        CONSTRAINT [PK_AuditoriaEvento] PRIMARY KEY CLUSTERED ([id]),
        CONSTRAINT [CK_AuditoriaEvento_ActorType] CHECK ([actorType] IN ('USER', 'ANONYMOUS', 'SYSTEM')),
        CONSTRAINT [CK_AuditoriaEvento_Result] CHECK ([result] IN ('SUCCESS', 'FAILURE')),
        CONSTRAINT [CK_AuditoriaEvento_HttpStatus] CHECK ([httpStatus] >= 100 AND [httpStatus] <= 599),
        CONSTRAINT [CK_AuditoriaEvento_MetadataJson] CHECK ([metadata] IS NULL OR ISJSON([metadata]) = 1)
    );
END
ELSE
BEGIN
    IF (SELECT COUNT(1) FROM sys.columns WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')) <> 17
       OR EXISTS (
            SELECT 1
            FROM (VALUES
                (N'id',            N'uniqueidentifier', CONVERT(SMALLINT, 16), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'occurredAt',    N'datetimeoffset',   CONVERT(SMALLINT, 10), CONVERT(TINYINT, 7), CONVERT(BIT, 0)),
                (N'actorId',       N'nvarchar',         CONVERT(SMALLINT, 240), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'actorType',     N'varchar',          CONVERT(SMALLINT, 20), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'action',        N'varchar',          CONVERT(SMALLINT, 120), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'resourceType',  N'varchar',          CONVERT(SMALLINT, 120), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'resourceId',    N'nvarchar',         CONVERT(SMALLINT, 240), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'result',        N'varchar',          CONVERT(SMALLINT, 20), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'correlationId', N'uniqueidentifier', CONVERT(SMALLINT, 16), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'traceId',       N'char',             CONVERT(SMALLINT, 32), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'spanId',        N'char',             CONVERT(SMALLINT, 16), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'httpMethod',    N'varchar',          CONVERT(SMALLINT, 16), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'path',          N'nvarchar',         CONVERT(SMALLINT, 480), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'httpStatus',    N'smallint',         CONVERT(SMALLINT, 2), CONVERT(TINYINT, 0), CONVERT(BIT, 0)),
                (N'clientIp',      N'varchar',          CONVERT(SMALLINT, 45), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'errorCode',     N'varchar',          CONVERT(SMALLINT, 120), CONVERT(TINYINT, 0), CONVERT(BIT, 1)),
                (N'metadata',      N'nvarchar',         CONVERT(SMALLINT, -1), CONVERT(TINYINT, 0), CONVERT(BIT, 1))
            ) AS expected([name], [type_name], [max_length], [scale], [is_nullable])
            LEFT JOIN sys.columns c
              ON c.[object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
             AND c.[name] = expected.[name]
            LEFT JOIN sys.types t
              ON t.user_type_id = c.user_type_id
            WHERE c.[column_id] IS NULL
               OR t.[name] <> expected.[type_name]
               OR c.[max_length] <> expected.[max_length]
               OR c.[is_nullable] <> expected.[is_nullable]
               OR (expected.[scale] <> 0 AND c.[scale] <> expected.[scale])
       )
       OR NOT EXISTS (
            SELECT 1 FROM sys.key_constraints
            WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
              AND [name] = N'PK_AuditoriaEvento'
              AND [type] = 'PK'
       )
       OR (SELECT COUNT(1)
           FROM sys.check_constraints
           WHERE [parent_object_id] = OBJECT_ID('dbo.[AuditoriaEvento]')
             AND [name] IN (
                 N'CK_AuditoriaEvento_ActorType',
                 N'CK_AuditoriaEvento_Result',
                 N'CK_AuditoriaEvento_HttpStatus',
                 N'CK_AuditoriaEvento_MetadataJson'
             )) <> 4
    BEGIN
        THROW 51000, 'SCHEMA_CONTRACT_CONFLICT: dbo.AuditoriaEvento shape differs from DB baseline.', 1;
    END
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_OccurredAt] ON [dbo].[AuditoriaEvento] ([occurredAt]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_CorrelationId_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_CorrelationId_OccurredAt] ON [dbo].[AuditoriaEvento] ([correlationId], [occurredAt]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_TraceId_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_TraceId_OccurredAt] ON [dbo].[AuditoriaEvento] ([traceId], [occurredAt]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ActorId_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_ActorId_OccurredAt] ON [dbo].[AuditoriaEvento] ([actorId], [occurredAt]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_Action_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_Action_OccurredAt] ON [dbo].[AuditoriaEvento] ([action], [occurredAt]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('dbo.[AuditoriaEvento]') AND [name] = N'IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AuditoriaEvento_ResourceType_ResourceId_OccurredAt] ON [dbo].[AuditoriaEvento] ([resourceType], [resourceId], [occurredAt]);
END
GO
