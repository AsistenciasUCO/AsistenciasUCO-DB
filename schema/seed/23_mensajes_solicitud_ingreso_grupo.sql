USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: mensajes de catalogo de las solicitudes de ingreso a un grupo (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SIG_001', 'BUSINESS_ERROR', 'MEDIO', N'Solo un estudiante puede solicitar el ingreso a un grupo.'),
    ('SIG_002', 'BUSINESS_ERROR', 'MEDIO', N'El grupo indicado no existe.'),
    ('SIG_003', 'BUSINESS_ERROR', 'MEDIO', N'El período académico del grupo ya terminó.'),
    ('SIG_004', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante ya está matriculado en este grupo.'),
    ('SIG_005', 'BUSINESS_ERROR', 'MEDIO', N'Ya existe una solicitud abierta para este grupo.'),
    ('SIG_006', 'SUCCESS', 'BAJO', N'La solicitud de ingreso al grupo fue registrada.'),
    ('SIG_007', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud indicada no existe o no está a su cargo.'),
    ('SIG_008', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud ya fue resuelta o retirada.'),
    ('SIG_009', 'BUSINESS_ERROR', 'MEDIO', N'La acción indicada no es válida; use ACEPTAR o RECHAZAR.'),
    ('SIG_010', 'BUSINESS_ERROR', 'MEDIO', N'El motivo del rechazo es obligatorio y no puede superar 500 caracteres.'),
    ('SIG_011', 'SUCCESS', 'BAJO', N'La solicitud fue aceptada y el estudiante quedó matriculado en el grupo.'),
    ('SIG_012', 'SUCCESS', 'BAJO', N'El grupo no tiene cupo: la solicitud quedó en lista de espera.'),
    ('SIG_013', 'BUSINESS_ERROR', 'MEDIO', N'El grupo sigue sin cupo; la solicitud permanece en lista de espera.'),
    ('SIG_014', 'SUCCESS', 'BAJO', N'La solicitud fue rechazada.'),
    ('SIG_015', 'SUCCESS', 'BAJO', N'La solicitud fue retirada.')
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
    ('SIG_001', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: el ejecutor no tiene dbo.Estudiante.'),
    ('SIG_002', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.Grupo con el id indicado.'),
    ('SIG_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaFin es anterior a la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER).'),
    ('SIG_004', 'BUSINESS_ERROR', 'MEDIO', N'Regla: existe dbo.EstudianteGrupo activo (A) del estudiante en el grupo.'),
    ('SIG_005', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: existe dbo.SolicitudIngresoGrupo en estado P o E para el estudiante y el grupo.'),
    ('SIG_006', 'SUCCESS', 'BAJO', N'Insercion: dbo.SolicitudIngresoGrupo en estado P.'),
    ('SIG_007', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: la solicitud no existe o el ejecutor no es el docente titular del grupo / el estudiante propietario.'),
    ('SIG_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud no esta en estado P o E.'),
    ('SIG_009', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @accion distinta de ACEPTAR o RECHAZAR.'),
    ('SIG_010', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @motivo nulo, vacio o de mas de 500 caracteres al rechazar.'),
    ('SIG_011', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud A y dbo.EstudianteGrupo activo creado (usp_registrar_estudiante_en_grupo_interno).'),
    ('SIG_012', 'SUCCESS', 'BAJO', N'Actualizacion: sin cupo (capacidad - activos <= 0) bajo UPDLOCK; solicitud P pasa a E.'),
    ('SIG_013', 'BUSINESS_ERROR', 'MEDIO', N'Regla: solicitud E sin cupo disponible bajo UPDLOCK.'),
    ('SIG_014', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud R con motivoRechazo.'),
    ('SIG_015', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud X retirada por el estudiante propietario.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
