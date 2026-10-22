USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU035/HU036 (D3 = A): parametro aditivo para no quemar el literal 'ATTACHED' en las consultas del soporte de
-- solicitudes de revision. Archivo independiente para no alterar 03_parametro.sql ni 15_lb004d_archivo_soporte.sql
-- (este ultimo y R2 pertenecen al manifiesto LB-004D). Idempotente (MERGE por clave natural grupo + clave).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ARCHIVO', 'ESTADO_ADJUNTO', 'ATTACHED', 'NVARCHAR', 'ATTACHED')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET
        Target.valor = Source.valor,
        Target.tipoDato = Source.tipoDato,
        Target.valorDefecto = Source.valorDefecto,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
