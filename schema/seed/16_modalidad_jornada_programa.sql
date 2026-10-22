USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU077: catalogos de modalidad y jornada (sembrado idempotente)
MERGE INTO [dbo].[Modalidad] AS Target
USING (VALUES
    ('7A1C5E10-0001-4A00-8000-000000000001', 'PRE', 'Presencial', 1),
    ('7A1C5E10-0001-4A00-8000-000000000002', 'VIR', 'Virtual', 1),
    ('7A1C5E10-0001-4A00-8000-000000000003', 'HIB', 'Híbrida', 1)
) AS Source (id, codigo, nombre, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estado) VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.estado);
GO

MERGE INTO [dbo].[Jornada] AS Target
USING (VALUES
    ('7A1C5E10-0002-4A00-8000-000000000001', 'DIU', 'Diurna', 1),
    ('7A1C5E10-0002-4A00-8000-000000000002', 'NOC', 'Nocturna', 1),
    ('7A1C5E10-0002-4A00-8000-000000000003', 'FDS', 'Fin de semana', 1)
) AS Source (id, codigo, nombre, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estado) VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.codigo, Source.nombre, Source.estado);
GO

-- HU108: tamano maximo de pagina para las consultas paginadas de programas (SSOT en CatalogoParametro)
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('PAGINACION', 'TAMANO_MAXIMO', '100', 'INT', '100')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.valor = Source.valor, Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
