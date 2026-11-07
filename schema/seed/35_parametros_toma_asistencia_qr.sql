USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.11): parametros de las tomas de asistencia y del QR de asistencia (DEC-015).
-- Patron 29_parametros_matricula_qr.sql: idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza
-- tipoDato y valorDefecto). El backend tiene en codigo un valor por defecto igual a la semilla (DEC-018).
--   TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION ([SUPUESTO-B-07]); LOTE_CIERRE_AUTOMATICO: tomas por pasada del job.
--   ASISTENCIA/CODIGO_RAZON_*: codigos de RazonCausa que leen los SP nuevos ([SUPUESTO-B-03]).
--   ASISTENCIA_QR/*: interruptor, rotacion, tolerancia del token anterior, lote del job, limites de intentos
--   ([SUPUESTO-B-12]: por IP solo cuentan los rechazos) y URL base del frontend para el QR.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('TOMA_ASISTENCIA', 'MAXIMO_TOMAS_POR_SESION',       N'4',     'INT',     N'4'),
    ('TOMA_ASISTENCIA', 'LOTE_CIERRE_AUTOMATICO',        N'200',   'INT',     N'200'),
    ('ASISTENCIA',      'CODIGO_RAZON_PRESENTE',         N'AN',    'STRING',  N'AN'),
    ('ASISTENCIA',      'CODIGO_RAZON_SIN_JUSTA_CAUSA',  N'SJC',   'STRING',  N'SJC'),
    ('ASISTENCIA',      'CODIGO_RAZON_EXCUSA',           N'EX',    'STRING',  N'EX'),
    ('ASISTENCIA_QR',   'HABILITADA',                    N'true',  'BOOLEAN', N'true'),
    ('ASISTENCIA_QR',   'ROTACION_SEGUNDOS',             N'60',    'INT',     N'60'),
    ('ASISTENCIA_QR',   'TOLERANCIA_SEGUNDOS',           N'60',    'INT',     N'60'),
    ('ASISTENCIA_QR',   'LOTE_ROTACION',                 N'200',   'INT',     N'200'),
    ('ASISTENCIA_QR',   'LIMITE_FALLIDOS_IP_POR_MINUTO', N'600',   'INT',     N'600'),
    ('ASISTENCIA_QR',   'LIMITE_TOKEN_POR_MINUTO',       N'120',   'INT',     N'120'),
    ('ASISTENCIA_QR',   'LIMITE_ESTUDIANTE_POR_MINUTO',  N'6',     'INT',     N'6'),
    ('ASISTENCIA_QR',   'URL_BASE_FRONTEND',             N'http://localhost:4200', 'STRING', N'http://localhost:4200')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- ASISTENCIA_QR/LIMITE_ESTUDIANTE_POR_MINUTO ya existia con 5 (semilla 29_parametros_matricula_qr.sql, A.2-4); el contrato B.2
-- (§2.11) lo fija en 6. Solo se ajusta el valor si nunca fue administrado (valor igual al defecto anterior 5).
UPDATE dbo.CatalogoParametro
SET valor = N'6', valorDefecto = N'6', fechaModificacion = SYSUTCDATETIME()
WHERE grupo = 'ASISTENCIA_QR' AND clave = 'LIMITE_ESTUDIANTE_POR_MINUTO' AND valor = N'5';
GO
