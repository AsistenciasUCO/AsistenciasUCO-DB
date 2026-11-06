USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: mensajes de catalogo de la matricula por QR/PIN (usuario y tecnicos). MQR_001 es el unico mensaje para
-- cualquier token invalido (inexistente, vencido, cerrado, rotado fuera de tolerancia): anti-enumeracion.
-- MQR_002 y MQR_003 los emite el backend (red del campus y limite de intentos); viven aqui por ser SSOT de mensajes.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('MQR_001', 'BUSINESS_ERROR', 'MEDIO', N'El código de matrícula no es válido o ya no está disponible. Solicítale al docente uno nuevo.'),
    ('MQR_002', 'BUSINESS_ERROR', 'MEDIO', N'La matrícula por código solo está disponible desde la red Wi-Fi del campus UCO.'),
    ('MQR_003', 'BUSINESS_ERROR', 'BAJO',  N'Demasiados intentos. Espera un momento antes de volver a intentarlo.'),
    ('MQR_004', 'BUSINESS_ERROR', 'BAJO',  N'Ya estás matriculado en este grupo.'),
    ('MQR_005', 'BUSINESS_ERROR', 'MEDIO', N'Ya tienes una cuenta registrada. Inicia sesión para completar tu matrícula.'),
    ('MQR_006', 'BUSINESS_ERROR', 'BAJO',  N'No fue posible generar un código único. Inténtalo de nuevo.'),
    ('MQR_007', 'BUSINESS_ERROR', 'MEDIO', N'Debes indicar el código QR o el PIN, pero no ambos.')
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
    ('MQR_001', 'BUSINESS_ERROR', 'MEDIO', N'Token o PIN de matrícula inexistente, cerrado, expirado o fuera de la tolerancia de rotación.'),
    ('MQR_002', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la IP del cliente no pertenece a asistencias:red:cidrs-campus.'),
    ('MQR_003', 'BUSINESS_ERROR', 'BAJO',  N'Límite de intentos por IP o por token superado en la ventana de tiempo.'),
    ('MQR_004', 'BUSINESS_ERROR', 'BAJO',  N'Regla: el estudiante ya tiene matrícula en el grupo.'),
    ('MQR_005', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: el documento o el correo ya pertenecen a un usuario registrado.'),
    ('MQR_006', 'BUSINESS_ERROR', 'BAJO',  N'Unicidad: el PIN ya está en uso por el token vigente o anterior de otra ventana activa.'),
    ('MQR_007', 'BUSINESS_ERROR', 'MEDIO', N'Validación: debe indicarse exactamente uno entre tokenHash y pin.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
