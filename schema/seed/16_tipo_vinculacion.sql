USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU090 (D2): catalogo de tipos de vinculacion. Los ids se resuelven siempre por codigo.
MERGE INTO [dbo].[TipoVinculacion] AS Target
USING (VALUES
    ('PLA', N'Planta', 1),
    ('MTI', N'Medio tiempo', 1),
    ('CAT', N'Cátedra', 1),
    ('OCA', N'Ocasional', 1)
) AS Source (codigo, nombre, estado)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.estado = Source.estado
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, estado)
    VALUES (NEWID(), Source.codigo, Source.nombre, Source.estado);
GO

-- Parametros de la vertical de docentes (HU091).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('DOCENTE', 'MAX_CANDIDATOS_BUSQUEDA', '20', 'INT', '20'),
    ('DOCENTE', 'TIPO_VINCULACION_DEFECTO', 'CAT', 'STRING', 'CAT'),
    ('DOCENTE', 'BUSQUEDA_MIN_CARACTERES', '3', 'INT', '3')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.valor = Source.valor, Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- R2 (backfill idempotente): todo par (docente, programa) que hoy existe via grupos queda vinculado,
-- con el tipo por defecto resuelto por codigo desde el parametro.
INSERT INTO [dbo].[DocentePrograma] (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
SELECT NEWID(), par.idDocente, par.idPrograma, tv.id, 1, SYSUTCDATETIME()
FROM (SELECT DISTINCT id AS idDocente, idPrograma FROM [dbo].[uv_docente]) par
CROSS JOIN (SELECT TOP 1 id FROM [dbo].[TipoVinculacion] WHERE codigo = dbo.ufn_obtener_parametro('DOCENTE', 'TIPO_VINCULACION_DEFECTO')) tv
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[DocentePrograma] dp WHERE dp.docente = par.idDocente AND dp.programa = par.idPrograma);
GO
