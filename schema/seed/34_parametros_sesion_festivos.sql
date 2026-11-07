USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.11): parametros de la cancelacion de sesiones (HU047) y de los dias festivos (DEC-017).
-- Patron 29_parametros_matricula_qr.sql: idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza
-- tipoDato y valorDefecto). El backend tiene en codigo un valor por defecto igual a la semilla (DEC-018).
--   SESION/MOTIVO_CANCELACION_LONGITUD_*: limites del motivo de usp_cancelar_sesion (SES_013).
--   FESTIVOS/HABILITADO: interruptor del job de carga; PROVEEDOR_PRINCIPAL + ORDEN_RESPALDO: orden de proveedores;
--   FUENTES_VALIDAS: valores admitidos en DiaFestivo.fuente; URL_*: plantillas con {anio}; NOMBRE_SECRETO_FERIADOS_IO:
--   NOMBRE del secreto en Key Vault (nunca el secreto); ANIO_*: rango de anios; MINIMO/MAXIMO_POR_ANIO: total valido;
--   PREFIJO_MOTIVO_CANCELACION: prefijo del motivo de una cancelacion automatica por festivo; ATRIBUCION_*: atribucion
--   que muestra la pantalla del administrador.
-- Reutilizados sin cambio: ASISTENCIA/TOLERANCIA_MINUTOS (15) y ASISTENCIA/MARGEN_RETARDO_MINUTOS (30).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('SESION',   'MOTIVO_CANCELACION_LONGITUD_MINIMA', N'10',  'INT',     N'10'),
    ('SESION',   'MOTIVO_CANCELACION_LONGITUD_MAXIMA', N'500', 'INT',     N'500'),
    ('FESTIVOS', 'HABILITADO',                 N'true',                   'BOOLEAN', N'true'),
    ('FESTIVOS', 'PROVEEDOR_PRINCIPAL',        N'CALENDARIOS_NACIONALES', 'STRING',  N'CALENDARIOS_NACIONALES'),
    ('FESTIVOS', 'ORDEN_RESPALDO',             N'FERIADOS_IO,CALCULO_LOCAL', 'STRING', N'FERIADOS_IO,CALCULO_LOCAL'),
    ('FESTIVOS', 'FUENTES_VALIDAS',            N'CALENDARIOS_NACIONALES,FERIADOS_IO,CALCULO_LOCAL', 'STRING', N'CALENDARIOS_NACIONALES,FERIADOS_IO,CALCULO_LOCAL'),
    ('FESTIVOS', 'URL_CALENDARIOS_NACIONALES', N'https://calendariosnacionales.com/co/v1/{anio}/nacionales.json', 'STRING', N'https://calendariosnacionales.com/co/v1/{anio}/nacionales.json'),
    ('FESTIVOS', 'URL_FERIADOS_IO',            N'https://api.feriados.io/v1/CO/holidays/{anio}', 'STRING', N'https://api.feriados.io/v1/CO/holidays/{anio}'),
    ('FESTIVOS', 'NOMBRE_SECRETO_FERIADOS_IO', N'feriados-io-api-key',    'STRING',  N'feriados-io-api-key'),
    ('FESTIVOS', 'TIMEOUT_SEGUNDOS',           N'10',                     'INT',     N'10'),
    ('FESTIVOS', 'ANIOS_ADELANTE',             N'1',                      'INT',     N'1'),
    ('FESTIVOS', 'ANIO_MINIMO',                N'2000',                   'INT',     N'2000'),
    ('FESTIVOS', 'ANIO_MAXIMO',                N'2100',                   'INT',     N'2100'),
    ('FESTIVOS', 'MINIMO_POR_ANIO',            N'15',                     'INT',     N'15'),
    ('FESTIVOS', 'MAXIMO_POR_ANIO',            N'25',                     'INT',     N'25'),
    ('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION', N'Día festivo: ',          'STRING',  N'Día festivo: '),
    ('FESTIVOS', 'ATRIBUCION_TEXTO',           N'Fuente: Calendarios Nacionales', 'STRING', N'Fuente: Calendarios Nacionales'),
    ('FESTIVOS', 'ATRIBUCION_URL',             N'https://calendariosnacionales.com', 'STRING', N'https://calendariosnacionales.com')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
