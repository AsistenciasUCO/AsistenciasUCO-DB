USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU096/HU097/HU098: mensajes de catalogo de la gestion de periodos academicos (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PER_001', 'BUSINESS_ERROR', 'MEDIO', N'El período académico indicado no existe.'),
    ('PER_002', 'BUSINESS_ERROR', 'MEDIO', N'La fecha de inicio del período debe ser anterior a la fecha de fin.'),
    ('PER_003', 'BUSINESS_ERROR', 'MEDIO', N'Ya existe un período académico con ese nombre en la institución.'),
    ('PER_004', 'BUSINESS_ERROR', 'MEDIO', N'El período académico tiene grupos o sesiones asociados y no se puede eliminar.'),
    ('PER_005', 'BUSINESS_ERROR', 'MEDIO', N'No tiene una institución activa asignada como administrador para gestionar períodos académicos.'),
    ('PER_006', 'SUCCESS', 'BAJO', N'Período académico eliminado exitosamente.')
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
    ('PER_001', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.PeriodoAcademico con el id indicado en la institucion del ejecutor.'),
    ('PER_002', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: fechaInicio y fechaFin obligatorias y fechaInicio < fechaFin.'),
    ('PER_003', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: ya existe dbo.PeriodoAcademico con el mismo id o nombre en la institucion.'),
    ('PER_004', 'BUSINESS_ERROR', 'MEDIO', N'Regla: existe dbo.Grupo que referencia el periodo a eliminar.'),
    ('PER_005', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: el ejecutor no tiene dbo.Administrador en una institucion activa.'),
    ('PER_006', 'SUCCESS', 'BAJO', N'Eliminacion: dbo.PeriodoAcademico eliminado.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
