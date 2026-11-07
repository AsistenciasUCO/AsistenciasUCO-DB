USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): parametros de la edicion de parametros. Ninguno es editable.
-- Patron 29_parametros_matricula_qr.sql: idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza
-- tipoDato y valorDefecto). El backend tiene en codigo un valor por defecto igual a la semilla (DEC-018).
--   PARAMETROS/GRUPOS_NO_EDITABLES: grupos que el administrador nunca edita (red, tiempo, constantes de dominio y
--     parametros de gobierno); gana sobre la lista blanca de CatalogoParametroEdicion (OBS-9).
--   PARAMETROS/TIPOS_NUMERICOS y TIPOS_ENTEROS: tipos de CatalogoParametro.tipoDato validados como numero y como entero
--     (ufn_validar_valor_parametro, sin literales de tipo en el codigo).
--   PARAMETROS/LONGITUD_MINIMA_MOTIVO: longitud minima del motivo del cambio (PRM_009); el maximo es la columna (500).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('PARAMETROS', 'GRUPOS_NO_EDITABLES',    N'RED,TIEMPO,GENERAL,REGISTRO,IDENTIDAD,RECLAMO,TOMA_ASISTENCIA,PARAMETROS,AUDITORIA,PAGINACION,MATRICULA', 'STRING',
                                             N'RED,TIEMPO,GENERAL,REGISTRO,IDENTIDAD,RECLAMO,TOMA_ASISTENCIA,PARAMETROS,AUDITORIA,PAGINACION,MATRICULA'),
    ('PARAMETROS', 'TIPOS_NUMERICOS',        N'INT,DECIMAL', 'STRING', N'INT,DECIMAL'),
    ('PARAMETROS', 'TIPOS_ENTEROS',          N'INT',         'STRING', N'INT'),
    ('PARAMETROS', 'LONGITUD_MINIMA_MOTIVO', N'10',          'INT',    N'10')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
