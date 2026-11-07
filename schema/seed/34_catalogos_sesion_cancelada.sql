USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.1): catalogo TipoCancelacionSesion con ids fijos (patron 08_razon_causa.sql). Idempotente.
-- Los SP lo resuelven por la bandera esAutomatica, nunca por el codigo.
MERGE INTO [dbo].[TipoCancelacionSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'DOCENTE', N'Cancelada por el docente', CAST(0 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'FESTIVO', N'Día festivo',              CAST(1 AS BIT))
) AS Source (id, codigo, nombre, esAutomatica)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.esAutomatica = Source.esAutomatica
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, esAutomatica)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.esAutomatica);
GO
