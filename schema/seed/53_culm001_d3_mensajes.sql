USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): mensajes de la edicion de parametros por el administrador. Idempotente (MERGE por
-- codigo). PRM_010 lo emite solo el backend (proveedor de parametros distinto de sqlserver) y vive aqui por ser SSOT de mensajes.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PRM_001', 'SUCCESS',          'BAJO',  N'Parámetro actualizado.'),
    ('PRM_002', 'BUSINESS_ERROR',   'MEDIO', N'El parámetro no existe.'),
    ('PRM_003', 'BUSINESS_ERROR',   'MEDIO', N'Este parámetro no se puede editar.'),
    ('PRM_004', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe ser de tipo {}.'),
    ('PRM_005', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe estar entre {} y {}.'),
    ('PRM_006', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe ser uno de: {}.'),
    ('PRM_007', 'VALIDATION_ERROR', 'BAJO',  N'«{}» debe ser menor que «{}».'),
    ('PRM_008', 'BUSINESS_ERROR',   'MEDIO', N'Otro usuario modificó el parámetro. Recarga y vuelve a intentarlo.'),
    ('PRM_009', 'VALIDATION_ERROR', 'BAJO',  N'Indica un motivo de al menos {} caracteres.'),
    ('PRM_010', 'BUSINESS_ERROR',   'MEDIO', N'La edición de parámetros no está disponible con el catálogo de configuración activo.'),
    ('PRM_011', 'SUCCESS',          'BAJO',  N'El valor no cambió.'),
    ('PRM_012', 'BUSINESS_ERROR',   'MEDIO', N'La edición de parámetros requiere una sola institución activa.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('PRM_001', 'SUCCESS',          'BAJO',  N'CatalogoParametro actualizado y CambioParametro registrado.'),
    ('PRM_002', 'BUSINESS_ERROR',   'MEDIO', N'CatalogoParametro no tiene un parametro activo con ese id.'),
    ('PRM_003', 'BUSINESS_ERROR',   'MEDIO', N'Parametro en un grupo de PARAMETROS/GRUPOS_NO_EDITABLES o sin fila editable en CatalogoParametroEdicion.'),
    ('PRM_004', 'VALIDATION_ERROR', 'BAJO',  N'Valor invalido para tipoDato [{}] (no numerico, con decimales en un tipo entero, vacio o de mas de 4000 caracteres).'),
    ('PRM_005', 'VALIDATION_ERROR', 'BAJO',  N'Valor fuera del rango [{}, {}] de CatalogoParametroEdicion.'),
    ('PRM_006', 'VALIDATION_ERROR', 'BAJO',  N'Valor fuera de valoresPermitidos [{}] (pertenencia exacta).'),
    ('PRM_007', 'VALIDATION_ERROR', 'BAJO',  N'Regla cruzada estricta violada: [{}] debe ser menor que [{}].'),
    ('PRM_008', 'BUSINESS_ERROR',   'MEDIO', N'fechaModificacionEsperada distinta de CatalogoParametro.fechaModificacion (concurrencia optimista).'),
    ('PRM_009', 'VALIDATION_ERROR', 'BAJO',  N'Motivo vacio o menor que PARAMETROS/LONGITUD_MINIMA_MOTIVO ({}) tras recortar.'),
    ('PRM_010', 'BUSINESS_ERROR',   'MEDIO', N'El catalogo de parametros activo del backend no es sqlserver: la edicion en BD no es la fuente de verdad.'),
    ('PRM_011', 'SUCCESS',          'BAJO',  N'El valor propuesto es igual al almacenado; no se escribio nada.'),
    ('PRM_012', 'BUSINESS_ERROR',   'MEDIO', N'[SUPUESTO-D-16] La instalacion no tiene exactamente una Institucion activa; los parametros no tienen ambito por institucion.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
