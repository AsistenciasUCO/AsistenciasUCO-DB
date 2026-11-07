USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A (numeracion 33 de A; idempotente).
-- A.1 (A-C4, N10): codigos de uv_estado_estudiante_grupo que leen los SP de matricula sin literales quemados:
--   MATRICULA/ESTADO_RETIRADA = I (matricula retirada por el docente, HU051; la reactivan la matricula manual y el QR).
--   MATRICULA/ESTADO_INSCRITA = A (unica matricula que cuenta como inscrita: oferta, materias, horario).
-- A.2 (A2-DB-5; valor = valor por defecto en codigo del backend, DEC-018; se administran en GET /admin/parametros):
--   ARCHIVOS/LIMITE_SUBIDAS_POR_MINUTO = 10, ASISTENCIA_QR/LIMITE_IP_POR_MINUTO = 20 y
--   ASISTENCIA_QR/LIMITE_ESTUDIANTE_POR_MINUTO = 5 (A.2-4, limites de intentos); RECLAMO/ESTADO_PENDIENTE = P y
--   RECLAMO/ESTADO_RETIRADO = X (A.2-7, retiro del reclamo propio; codigos de dbo.Estado).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('MATRICULA',     'ESTADO_RETIRADA',              N'I',  'STRING', N'I'),
    ('MATRICULA',     'ESTADO_INSCRITA',              N'A',  'STRING', N'A'),
    ('ARCHIVOS',      'LIMITE_SUBIDAS_POR_MINUTO',    N'10', 'INT',    N'10'),
    ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO',         N'20', 'INT',    N'20'),
    ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO', N'5',  'INT',    N'5'),
    ('RECLAMO',       'ESTADO_PENDIENTE',             N'P',  'STRING', N'P'),
    ('RECLAMO',       'ESTADO_RETIRADO',              N'X',  'STRING', N'X')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- A-C3 revisada: el estado X (retirada) de dbo.Estado se conserva (antes en el seed 22, borrado con HU053-HU055) porque
-- A.2-7 lo reutiliza para el reclamo retirado por el estudiante (A2-C4). El estado E (en espera) se retira.
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES
    ('D6E2F3A4-5B6C-4D7E-9F80-A12B3C4D5E6F', 'retirada', 'X')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
