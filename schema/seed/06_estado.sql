USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente: Estado de solicitudes de revision de asistencia (TD-057)
-- Contrato: P = Pendiente, A = Aceptada/Aprobada, R = Rechazada (Estado.codigo es CHAR(1)).
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES
    ('C1A0B3F2-5D4E-4F6A-9B8C-7D6E5F4A3B21', 'pendiente', 'P'),
    ('0792C353-78A4-4D0A-B368-60A5092DBA18', 'aceptada', 'A'),
    ('A6131416-815F-4E7C-BE98-EA2D1F881793', 'rechazada', 'R')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
