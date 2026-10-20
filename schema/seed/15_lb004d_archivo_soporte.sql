USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- LB-004D: catalogo aditivo para el soporte de solicitudes de revision. Archivo independiente para no
-- alterar 03_parametro.sql ni 04_mensaje.sql. Idempotente (MERGE por clave natural).

-- Parametro: tamano maximo de un soporte (5 MiB, decision congelada D-LB004B1-003 del backend).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('ARCHIVO', 'TAMANIO_MAXIMO_BYTES', '5242880', 'INT', '5242880')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET
        Target.valor = Source.valor,
        Target.tipoDato = Source.tipoDato,
        Target.valorDefecto = Source.valorDefecto,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Mensajes de usuario. ARC_001 es identico para soporte inexistente, ajeno, ya usado u huerfano
-- (no distingue casos para no revelar existencia).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ARC_001', 'BUSINESS_ERROR', 'ALTO', N'El soporte indicado no esta disponible para esta solicitud.'),
    ('ARC_002', 'BUSINESS_ERROR', 'ALTO', N'No fue posible registrar el soporte.'),
    ('ARC_003', 'BUSINESS_ERROR', 'MEDIO', N'Los datos del soporte no son validos.'),
    ('ARC_005', 'BUSINESS_ERROR', 'ALTO', N'El estudiante indicado no corresponde al usuario autenticado.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('ARC_001', 'BUSINESS_ERROR', 'ALTO', N'Soporte no disponible para radicar: inexistente, de otro propietario, ya vinculado o no vigente.'),
    ('ARC_002', 'BUSINESS_ERROR', 'ALTO', N'Registro de soporte rechazado: el identificador ya existe con otro propietario o con metadata distinta.'),
    ('ARC_003', 'BUSINESS_ERROR', 'MEDIO', N'Metadata de soporte invalida: identificador, nombre, tipo de contenido, tamano o checksum fuera de contrato.'),
    ('ARC_005', 'BUSINESS_ERROR', 'ALTO', N'El idEstudiante no pertenece al idUsuarioEjecutor.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET
        Target.tipoMensaje = Source.tipoMensaje,
        Target.severidad = Source.severidad,
        Target.contenido = Source.contenido,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
