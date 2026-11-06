USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: parametros de la matricula por QR/PIN rotativo (idempotente). Son los valores que lista y administra
-- el administrador (GET /admin/parametros); los SP los leen en cada operacion (CONTRACT A1).
-- ROTACION_SEGUNDOS: cada cuanto rota el token. TOLERANCIA_SEGUNDOS: cuanto sigue valido el token anterior.
-- DURACION_MAXIMA_MINUTOS: fin de la ventana desde su apertura. ESTADO_*: valores de TokenMatriculaGrupo.estado.
-- ESTADO_MATRICULA: codigo de uv_estado_estudiante_grupo con el que queda la matricula por QR (D3 = activa).
-- LOTE_ROTACION: maximo de ventanas que rota el job en una pasada.
-- HABILITADA / LIMITE_*: interruptor y limites de intentos del backend (CONTRACT A3: viven en el catalogo de parametros).
-- RED/CIDRS_CAMPUS: rangos del campus (lista CIDR separada por comas). La semilla solo trae loopback de DESARROLLO:
-- produccion debe reemplazarlos por los rangos reales; sin rangos validos el backend niega todo (fail-closed).
-- RED/PROXIES_CONFIABLES: proxies cuyo X-Forwarded-For se acepta (D5). Vacio = no se confia en ningun proxy.
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('MATRICULA_QR', 'ROTACION_SEGUNDOS',       N'60',      'INT',    N'60'),
    ('MATRICULA_QR', 'TOLERANCIA_SEGUNDOS',     N'60',      'INT',    N'60'),
    ('MATRICULA_QR', 'DURACION_MAXIMA_MINUTOS', N'60',      'INT',    N'60'),
    ('MATRICULA_QR', 'ESTADO_ACTIVA',           N'ACTIVA',  'STRING', N'ACTIVA'),
    ('MATRICULA_QR', 'ESTADO_CERRADA',          N'CERRADA', 'STRING', N'CERRADA'),
    ('MATRICULA_QR', 'ESTADO_EXPIRADA',         N'EXPIRADA','STRING', N'EXPIRADA'),
    ('MATRICULA_QR', 'ESTADO_MATRICULA',        N'A',       'STRING', N'A'),
    ('MATRICULA_QR', 'LOTE_ROTACION',           N'200',     'INT',    N'200'),
    ('MATRICULA_QR', 'HABILITADA',              N'true',    'BOOLEAN',N'true'),
    ('MATRICULA_QR', 'LIMITE_IP_POR_MINUTO',    N'20',      'INT',    N'20'),
    ('MATRICULA_QR', 'LIMITE_REGISTROS_TOKEN_POR_MINUTO', N'5', 'INT', N'5'),
    ('MATRICULA_QR', 'URL_BASE_FRONTEND',       N'http://localhost:4200', 'STRING', N'http://localhost:4200'),
    ('RED',          'CIDRS_CAMPUS',            N'127.0.0.1/32,::1/128', 'STRING', N'127.0.0.1/32,::1/128'),
    ('RED',          'PROXIES_CONFIABLES',      N'',        'STRING', N'')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
