USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091/HU092/HU093: mensajes de catalogo de la vertical de docentes del programa (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('DOC_002', 'BUSINESS_ERROR', 'MEDIO', N'El usuario ya se encuentra registrado como docente.'),
    ('DOC_003', 'BUSINESS_ERROR', 'ALTO', N'Ya existe una persona registrada con ese documento o correo. Use la opción "Vincular docente existente".'),
    ('DOC_004', 'BUSINESS_ERROR', 'MEDIO', N'El tipo de vinculación indicado no existe o está inactivo.'),
    ('DOC_005', 'BUSINESS_ERROR', 'MEDIO', N'Debe indicar un docente existente o los datos de un docente nuevo, pero no ambos.'),
    ('DOC_006', 'BUSINESS_ERROR', 'MEDIO', N'El docente ya está vinculado a este programa.'),
    ('DOC_007', 'BUSINESS_ERROR', 'BAJO', N'La búsqueda de candidatos requiere al menos 3 caracteres.'),
    ('DOC_008', 'BUSINESS_ERROR', 'MEDIO', N'El docente no está vinculado a este programa.'),
    ('DOC_009', 'BUSINESS_ERROR', 'MEDIO', N'El docente no tiene una vinculación activa con el programa.'),
    ('IAM_001', 'SYSTEM_ERROR', 'ALTO', N'El registro se guardó, pero la cuenta de acceso no pudo crearse en este momento. Intente de nuevo.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Mensajes tecnicos (el backend clasifica por el codigo via DbTechnicalError).
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('DOC_002', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: el usuario ya tiene un registro en dbo.Docente.'),
    ('DOC_003', 'BUSINESS_ERROR', 'ALTO', N'Conflicto de identidad: documento o correo ya existen en dbo.Usuario; el modo nuevo no hace find-or-create.'),
    ('DOC_004', 'BUSINESS_ERROR', 'MEDIO', N'Validación: TipoVinculacion inexistente o con estado = 0.'),
    ('DOC_005', 'BUSINESS_ERROR', 'MEDIO', N'Validación de modo: exactamente uno entre @idDocente, @idUsuario o el bloque de datos de persona nueva.'),
    ('DOC_006', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: ya existe dbo.DocentePrograma para el par (docente, programa).'),
    ('DOC_007', 'BUSINESS_ERROR', 'BAJO', N'Validación: @busqueda de candidatos con menos caracteres que DOCENTE/BUSQUEDA_MIN_CARACTERES.'),
    ('DOC_008', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.DocentePrograma para el par (docente, programa) indicado.'),
    ('DOC_009', 'BUSINESS_ERROR', 'MEDIO', N'Regla: el docente no tiene dbo.DocentePrograma con estado = 1 en el programa del grupo.'),
    ('IAM_001', 'SYSTEM_ERROR', 'ALTO', N'Aprovisionamiento IAM falló después del commit en DB (TD-015): reintentar crearCuenta de forma idempotente.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
