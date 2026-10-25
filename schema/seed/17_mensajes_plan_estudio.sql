USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU081/HU082/HU083: mensajes de catalogo del estado y los semestres del plan de estudios (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PLA_002', 'BUSINESS_ERROR', 'MEDIO', N'El plan de estudios indicado no existe.'),
    ('PLA_003', 'BUSINESS_ERROR', 'MEDIO', N'El plan de estudios ya tiene el número máximo de semestres.'),
    ('PLA_004', 'BUSINESS_ERROR', 'MEDIO', N'El semestre indicado no pertenece al plan de estudios.'),
    ('PLA_005', 'BUSINESS_ERROR', 'MEDIO', N'Solo se puede quitar el último semestre del plan de estudios.'),
    ('PLA_006', 'BUSINESS_ERROR', 'MEDIO', N'El semestre tiene asignaturas asociadas. Reubíquelas o elimínelas primero.')
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
    ('PLA_002', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.PlanEstudio con el id indicado.'),
    ('PLA_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: no existe dbo.Semestre con numero MAX(numero del plan) + 1.'),
    ('PLA_004', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.SemestrePlanEstudio del plan con el numero de semestre indicado.'),
    ('PLA_005', 'BUSINESS_ERROR', 'MEDIO', N'Regla: el numero de semestre indicado no es el mayor del plan; la malla debe seguir consecutiva.'),
    ('PLA_006', 'BUSINESS_ERROR', 'MEDIO', N'Regla: existe dbo.Asignatura que referencia el dbo.SemestrePlanEstudio a quitar.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
