USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU076/HU077/HU078/HU108: mensajes del programa academico (usuario y tecnico). Archivo propio para no colisionar con 04_mensaje.sql.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PROG_002', 'BUSINESS_ERROR', 'ALTO', N'Ya existe un programa académico con el identificador indicado.'),
    ('PROG_003', 'BUSINESS_ERROR', 'ALTO', N'Ya existe un programa académico con ese nombre en la facultad.'),
    ('PROG_004', 'BUSINESS_ERROR', 'MEDIO', N'El tipo de programa indicado no existe o está inactivo.'),
    ('PROG_005', 'BUSINESS_ERROR', 'ALTO', N'El coordinador seleccionado no está disponible: no existe, está inactivo o ya tiene un programa asignado.'),
    ('PROG_006', 'BUSINESS_ERROR', 'MEDIO', N'La modalidad o la jornada indicada no existe o está inactiva.'),
    ('PROG_007', 'BUSINESS_ERROR', 'ALTO', N'No se puede desactivar el programa porque tiene grupos activos en el período vigente.'),
    ('PROG_008', 'BUSINESS_ERROR', 'ALTO', N'No se puede activar el programa porque su facultad está inactiva.'),
    ('PAG_001', 'BUSINESS_ERROR', 'MEDIO', N'Los parámetros de paginación no son válidos.')
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
    ('PROG_002', 'BUSINESS_ERROR', 'ALTO', N'Registro duplicado: ya existe un programa con el id {} en uv_programa.'),
    ('PROG_003', 'BUSINESS_ERROR', 'ALTO', N'Regla de unicidad: el nombre [{}] ya existe en la facultad (comparación sin distinguir mayúsculas).'),
    ('PROG_004', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: tipo de programa {} inexistente o inactivo en uv_tipo_programa.'),
    ('PROG_005', 'BUSINESS_ERROR', 'ALTO', N'Regla 1 a 1: el coordinador {} no existe, está inactivo o ya figura en otro programa.'),
    ('PROG_006', 'BUSINESS_ERROR', 'MEDIO', N'Error de búsqueda: modalidad/jornada {} inexistente o inactiva.'),
    ('PROG_007', 'BUSINESS_ERROR', 'ALTO', N'Regla D4: el programa {} tiene grupos habilitados en uv_grupo_programa.'),
    ('PROG_008', 'BUSINESS_ERROR', 'ALTO', N'Regla de jerarquía: la facultad del programa {} está inactiva.'),
    ('PAG_001', 'BUSINESS_ERROR', 'MEDIO', N'Paginación inválida: numeroPagina={} y tamanoPagina={} fuera de rango (máximo según PAGINACION/TAMANO_MAXIMO).')
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
