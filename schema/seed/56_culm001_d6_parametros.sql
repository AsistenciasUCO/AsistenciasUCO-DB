USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.6 (CONTRACT v2 §7.3, HU172): prefijo de las rutas de administracion que filtra
-- usp_consultar_auditoria_eventos_paginado con @soloAdministracion = 1. Idempotente y sin pisar el valor administrado
-- (WHEN MATCHED solo actualiza tipoDato y valorDefecto). El grupo AUDITORIA esta en PARAMETROS/GRUPOS_NO_EDITABLES (D.3).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('AUDITORIA', 'PREFIJO_RUTA_ADMINISTRACION', N'/api/v1/admin/', 'STRING', N'/api/v1/admin/')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
