USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU051: mensajes de catalogo del retiro de un estudiante del grupo por el docente titular (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('RET_001', 'BUSINESS_ERROR', 'MEDIO', N'El grupo indicado no existe o no es un grupo a su cargo.'),
    ('RET_002', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante no tiene una matrícula activa en este grupo.'),
    ('RET_003', 'BUSINESS_ERROR', 'MEDIO', N'El período académico del grupo ya terminó; no se puede retirar al estudiante.'),
    ('RET_004', 'BUSINESS_ERROR', 'MEDIO', N'El motivo del retiro es obligatorio y no puede superar 500 caracteres.'),
    ('RET_005', 'SUCCESS', 'BAJO', N'El estudiante fue retirado del grupo.')
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
    ('RET_001', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: no existe dbo.Grupo con el id indicado cuyo Docente.usuario sea el ejecutor.'),
    ('RET_002', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.EstudianteGrupo activo (estado A) para el estudiante en el grupo.'),
    ('RET_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaFin es anterior a la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER).'),
    ('RET_004', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @motivo nulo, vacio o de mas de 500 caracteres.'),
    ('RET_005', 'SUCCESS', 'BAJO', N'Actualizacion: dbo.EstudianteGrupo pasa a estado I (inactivo) y se registra dbo.AuditoriaEvento.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
