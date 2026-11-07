USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2, OBS-6): perfiles que pueden corregir la identidad de un estudiante y de un decano
-- (usp_corregir_identidad_usuario los lee en lugar de literales). Listas separadas por comas. Idempotente: si ya existen, no se
-- sobrescribe el valor vigente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('IDENTIDAD', 'PERFILES_CORRECCION_ESTUDIANTE', N'COORDINADOR,ADMINISTRADOR', 'STRING', N'COORDINADOR,ADMINISTRADOR'),
    ('IDENTIDAD', 'PERFILES_CORRECCION_DECANO',     N'ADMINISTRADOR',             'STRING', N'ADMINISTRADOR')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
