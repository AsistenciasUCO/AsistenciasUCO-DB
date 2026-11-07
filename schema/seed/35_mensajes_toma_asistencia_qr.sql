USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.10): mensajes de las tomas de asistencia (TOM_*) y del QR de asistencia (AQR_*).
-- Idempotente (MERGE por codigo). TOM_005..TOM_007 quedan reservados y no se siembran. AQR_002, AQR_010 y AQR_011 los
-- emite solo el backend; viven aqui por ser SSOT de mensajes (MessageCatalogPort).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('TOM_001', 'BUSINESS_ERROR',   'BAJO',  N'La toma de asistencia no existe.'),
    ('TOM_002', 'VALIDATION_ERROR', 'BAJO',  N'El modo de la toma no es válido.'),
    ('TOM_003', 'BUSINESS_ERROR',   'BAJO',  N'Ya hay una toma abierta en esta sesión; ciérrala antes de abrir otra.'),
    ('TOM_004', 'BUSINESS_ERROR',   'BAJO',  N'La sesión ya tiene el máximo de {} tomas.'),
    ('TOM_008', 'SUCCESS',          'BAJO',  N'Toma {} abierta.'),
    ('TOM_009', 'SUCCESS',          'BAJO',  N'Toma cerrada. {} estudiantes quedaron como ausentes.'),
    ('TOM_010', 'SUCCESS',          'BAJO',  N'Asistencia de la toma guardada.'),
    ('TOM_011', 'SUCCESS',          'BAJO',  N'La toma ya estaba cerrada.'),
    ('AQR_001', 'BUSINESS_ERROR',   'BAJO',  N'El código QR o el PIN no es válido o ya venció. Pide el PIN vigente al docente.'),
    ('AQR_002', 'SECURITY_ERROR',   'MEDIO', N'Debes estar conectado a la red Wi-Fi del campus para registrar tu asistencia.'),
    ('AQR_003', 'BUSINESS_ERROR',   'BAJO',  N'Esta toma es manual; no admite código QR.'),
    ('AQR_004', 'BUSINESS_ERROR',   'BAJO',  N'No estás matriculado en el grupo de esta clase.'),
    ('AQR_005', 'BUSINESS_ERROR',   'BAJO',  N'La toma de asistencia ya se cerró.'),
    ('AQR_006', 'TECHNICAL_ERROR',  'BAJO',  N'No fue posible generar el código. Intenta de nuevo.'),
    ('AQR_007', 'VALIDATION_ERROR', 'BAJO',  N'Escanea el código QR o digita el PIN.'),
    ('AQR_008', 'SUCCESS',          'BAJO',  N'Tu asistencia a esta toma ya estaba registrada.'),
    ('AQR_009', 'SUCCESS',          'BAJO',  N'¡Listo! Tu asistencia quedó registrada.'),
    ('AQR_010', 'BUSINESS_ERROR',   'BAJO',  N'El registro de asistencia por QR no está disponible.'),
    ('AQR_011', 'SECURITY_ERROR',   'BAJO',  N'Hiciste demasiados intentos. Espera un minuto e intenta de nuevo.'),
    ('AQR_012', 'SUCCESS',          'BAJO',  N'Código QR listo para proyectar.'),
    ('AQR_013', 'SUCCESS',          'BAJO',  N'Se dejó de proyectar el código QR.')
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
    ('TOM_001', 'BUSINESS_ERROR',   'BAJO',  N'Toma [{}] inexistente o de otra sesión.'),
    ('TOM_002', 'VALIDATION_ERROR', 'BAJO',  N'@codigoModo [{}] no existe en ModoTomaAsistencia.'),
    ('TOM_003', 'BUSINESS_ERROR',   'BAJO',  N'Sesión [{}] con toma abierta [{}].'),
    ('TOM_004', 'BUSINESS_ERROR',   'BAJO',  N'TOMA_ASISTENCIA/MAXIMO_TOMAS_POR_SESION alcanzado en [{}].'),
    ('TOM_008', 'SUCCESS',          'BAJO',  N'TomaAsistencia [{}] abierta modo [{}].'),
    ('TOM_009', 'SUCCESS',          'BAJO',  N'TomaAsistencia [{}] cerrada; ausentes marcados {}.'),
    ('TOM_010', 'SUCCESS',          'BAJO',  N'Lote de toma [{}] con {} registros.'),
    ('TOM_011', 'SUCCESS',          'BAJO',  N'TomaAsistencia [{}] ya cerrada; sin escrituras.'),
    ('AQR_001', 'BUSINESS_ERROR',   'BAJO',  N'Token/PIN sin coincidencia vigente.'),
    ('AQR_002', 'SECURITY_ERROR',   'MEDIO', N'IP [{}] fuera de RED/CIDRS_CAMPUS.'),
    ('AQR_003', 'BUSINESS_ERROR',   'BAJO',  N'Toma [{}] con usaCodigoQr = 0.'),
    ('AQR_004', 'BUSINESS_ERROR',   'BAJO',  N'Estudiante [{}] sin matrícula A en grupo [{}].'),
    ('AQR_005', 'BUSINESS_ERROR',   'BAJO',  N'Toma/token [{}] cerrado o expirado.'),
    ('AQR_006', 'TECHNICAL_ERROR',  'BAJO',  N'PIN [{}] repetido entre activos/anteriores vigentes; reintentar.'),
    ('AQR_007', 'VALIDATION_ERROR', 'BAJO',  N'Se requiere exactamente uno de @tokenHash o @pin.'),
    ('AQR_008', 'SUCCESS',          'BAJO',  N'Detalle existente para estudiante [{}] toma [{}]; sin cambios.'),
    ('AQR_009', 'SUCCESS',          'BAJO',  N'Asistencia AN por token: estudiante [{}] toma [{}].'),
    ('AQR_010', 'BUSINESS_ERROR',   'BAJO',  N'ASISTENCIA_QR/HABILITADA != true.'),
    ('AQR_011', 'SECURITY_ERROR',   'BAJO',  N'Límite [{}] superado para clave [{}].'),
    ('AQR_012', 'SUCCESS',          'BAJO',  N'Token de asistencia [{}] emitido para toma [{}].'),
    ('AQR_013', 'SUCCESS',          'BAJO',  N'Token de la toma [{}] cerrado.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
