USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.10): mensajes de la sesion cancelada (HU047), la ventana con tolerancia y los dias
-- festivos. Idempotente (MERGE por codigo). SES_015 queda reservado (retirado por B-6) y no se siembra.
-- FES_010 lo emite solo el backend (informativo: uso del respaldo local); vive aqui por ser SSOT de mensajes.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_010', 'BUSINESS_ERROR',   'MEDIO', N'La sesión fue cancelada; no admite registro de asistencia.'),
    ('SES_011', 'BUSINESS_ERROR',   'BAJO',  N'La sesión ya estaba cancelada.'),
    ('SES_012', 'BUSINESS_ERROR',   'MEDIO', N'No es posible cancelar una sesión que ya tiene asistencia registrada.'),
    ('SES_013', 'VALIDATION_ERROR', 'BAJO',  N'El motivo de cancelación debe tener entre {} y {} caracteres.'),
    ('SES_014', 'SUCCESS',          'BAJO',  N'La sesión fue cancelada y se avisó a los estudiantes.'),
    ('SES_016', 'BUSINESS_ERROR',   'MEDIO', N'La sesión ya terminó y tiene asistencia registrada; no se puede cancelar. Las correcciones se hacen por reclamo.'),
    ('FES_001', 'VALIDATION_ERROR', 'BAJO',  N'El año de festivos no es válido.'),
    ('FES_002', 'VALIDATION_ERROR', 'MEDIO', N'El listado de festivos recibido no es válido.'),
    ('FES_003', 'VALIDATION_ERROR', 'MEDIO', N'El listado de festivos no tiene una cantidad válida de días.'),
    ('FES_004', 'VALIDATION_ERROR', 'MEDIO', N'La fuente de festivos no es válida.'),
    ('FES_005', 'SUCCESS',          'BAJO',  N'Se cargaron {} días festivos de {}.'),
    ('FES_006', 'VALIDATION_ERROR', 'BAJO',  N'Indica el periodo académico o el año, no ambos.'),
    ('FES_007', 'BUSINESS_ERROR',   'BAJO',  N'El periodo académico no existe.'),
    ('FES_008', 'SUCCESS',          'BAJO',  N'Se cancelaron {} sesiones por festivo; {} sesiones con asistencia quedaron sin cambios.'),
    ('FES_009', 'BUSINESS_ERROR',   'MEDIO', N'Algunos grupos no se pudieron actualizar con los festivos.'),
    ('FES_010', 'TECHNICAL_ERROR',  'ALTO',  N'No fue posible obtener los festivos del año; se usó el cálculo local.')
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
    ('SES_010', 'BUSINESS_ERROR',   'MEDIO', N'Sesión [{}] cancelada (SesionCancelacion existe); operación rechazada sin escrituras.'),
    ('SES_011', 'BUSINESS_ERROR',   'BAJO',  N'Sesión [{}] con SesionCancelacion previa; se conserva el motivo original.'),
    ('SES_012', 'BUSINESS_ERROR',   'MEDIO', N'Sesión [{}] con Asistencia o TomaAsistencia; cancelación rechazada.'),
    ('SES_013', 'VALIDATION_ERROR', 'BAJO',  N'Longitud de @motivo fuera de SESION/MOTIVO_CANCELACION_LONGITUD_*.'),
    ('SES_014', 'SUCCESS',          'BAJO',  N'SesionCancelacion creada para [{}] tipo [{}].'),
    ('SES_016', 'BUSINESS_ERROR',   'MEDIO', N'Sesión [{}] con Asistencia o TomaAsistencia y SYSUTCDATETIME() >= fin + MARGEN_RETARDO_MINUTOS; cancelación rechazada.'),
    ('FES_001', 'VALIDATION_ERROR', 'BAJO',  N'@anio [{}] fuera de FESTIVOS/ANIO_MINIMO..ANIO_MAXIMO.'),
    ('FES_002', 'VALIDATION_ERROR', 'MEDIO', N'@festivosJSON inválido: {}.'),
    ('FES_003', 'VALIDATION_ERROR', 'MEDIO', N'Total [{}] fuera de FESTIVOS/MINIMO_POR_ANIO..MAXIMO_POR_ANIO.'),
    ('FES_004', 'VALIDATION_ERROR', 'MEDIO', N'@fuente [{}] no está en FESTIVOS/FUENTES_VALIDAS.'),
    ('FES_005', 'SUCCESS',          'BAJO',  N'Carga [{}]: insertados {}, actualizados {}, desactivados {}.'),
    ('FES_006', 'VALIDATION_ERROR', 'BAJO',  N'@idPeriodoAcademico y @anio: exactamente uno.'),
    ('FES_007', 'BUSINESS_ERROR',   'BAJO',  N'Periodo [{}] inexistente.'),
    ('FES_008', 'SUCCESS',          'BAJO',  N'Aplicación de festivos grupo/periodo [{}].'),
    ('FES_009', 'BUSINESS_ERROR',   'MEDIO', N'{} grupos con error; ver log con la correlación.'),
    ('FES_010', 'TECHNICAL_ERROR',  'ALTO',  N'Proveedores [{}] fallaron; respaldo CALCULO_LOCAL.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
