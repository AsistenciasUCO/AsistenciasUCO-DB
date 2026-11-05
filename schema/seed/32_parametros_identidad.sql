USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159 (correccion de identidad de usuarios, 2026-11-05): interruptor de la correccion del tipo y numero de
-- documento. 1 = permitida (por defecto); 0 = se rechaza con IDE_003 y la correccion de nombres sigue funcionando.
-- Idempotente: si ya existe, no se sobrescribe el valor vigente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('IDENTIDAD', 'PERMITIR_CORREGIR_DOCUMENTO', N'1', 'INT', N'1')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
