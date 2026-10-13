USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Estado
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES
    ('0792C353-78A4-4D0A-B368-60A5092DBA18', 'aceptada', 'A'),
    ('B4B4D37E-6A8F-4E1D-AF32-0B2C60E2E977', 'pendiente', 'P'),
    ('A6131416-815F-4E7C-BE98-EA2D1F881793', 'rechazada', 'R')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
