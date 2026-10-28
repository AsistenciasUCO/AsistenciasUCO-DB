USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU008 (decision de John, 2026-10-27): la oferta de grupos del estudiante incluye los grupos de asignaturas
-- transversales (componente BAS o INS) de cualquier programa de su institucion. Para dejar de mostrarlas y que solo se
-- pueda ingresar con el enlace del docente: UPDATE dbo.CatalogoParametro SET valor = '0' WHERE grupo = 'OFERTA'
-- AND clave = 'INCLUIR_TRANSVERSALES' (efecto inmediato; no requiere desplegar codigo). Idempotente; el MERGE no
-- sobrescribe un valor ya cambiado en el ambiente.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('OFERTA', 'INCLUIR_TRANSVERSALES', '1', 'INT', '1')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET
        Target.tipoDato = Source.tipoDato,
        Target.valorDefecto = Source.valorDefecto,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
