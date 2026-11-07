USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.1): catalogos ModoTomaAsistencia y EstadoTomaAsistencia con ids fijos (patron 08_razon_causa.sql).
-- Idempotente. Los SP los resuelven por las banderas usaCodigoQr / marcaAusentesAlCerrar / estaAbierta, nunca por el codigo.
MERGE INTO [dbo].[ModoTomaAsistencia] AS Target
USING (VALUES
    (CAST('7C1E0B20-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'MANUAL', N'Registro manual del docente', CAST(0 AS BIT), CAST(0 AS BIT)),
    (CAST('7C1E0B20-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'QR',     N'Código QR y PIN rotativos',  CAST(1 AS BIT), CAST(1 AS BIT))
) AS Source (id, codigo, nombre, usaCodigoQr, marcaAusentesAlCerrar)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.usaCodigoQr = Source.usaCodigoQr,
               Target.marcaAusentesAlCerrar = Source.marcaAusentesAlCerrar
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, usaCodigoQr, marcaAusentesAlCerrar)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.usaCodigoQr, Source.marcaAusentesAlCerrar);
GO

MERGE INTO [dbo].[EstadoTomaAsistencia] AS Target
USING (VALUES
    (CAST('7C1E0B30-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'ABIERTA', N'Abierta', CAST(1 AS BIT)),
    (CAST('7C1E0B30-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'CERRADA', N'Cerrada', CAST(0 AS BIT))
) AS Source (id, codigo, nombre, estaAbierta)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.estaAbierta = Source.estaAbierta
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estaAbierta)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.estaAbierta);
GO
