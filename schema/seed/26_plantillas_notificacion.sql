USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Sembrado Idempotente: PlantillaNotificacionMarcador y PlantillaNotificacion (NOTIF-002A / NOTIF-002B)
-- =============================================================================

MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'estudiante', N'Nombre completo del estudiante retirado', N'Juan Pérez', 1),
    ('RETIRO_ESTUDIANTE_GRUPO', 'motivo', N'Motivo del retiro registrado por el docente', N'Cancelación académica', 0),
    ('SOLICITUD_INGRESO_REGISTRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_REGISTRADA', 'estudiante', N'Nombre completo del estudiante solicitante', N'Juan Pérez', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'resultado', N'Resultado de la solicitud (aceptada, puesta en espera o rechazada)', N'aceptada', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'estudiante', N'Nombre completo del estudiante que retiró la solicitud', N'Juan Pérez', 1),

    -- NOTIF-002B: Reclamos de asistencia
    ('RECLAMO_ASISTENCIA_RADICADO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'fecha', N'Fecha de la sesión reclamada', N'2026-11-05', 1),
    ('RECLAMO_ASISTENCIA_RADICADO', 'motivo', N'Categoría o motivo de la solicitud', N'Incapacidad médica', 0),

    ('RECLAMO_ASISTENCIA_RESUELTO', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'fecha', N'Fecha de la sesión reclamada', N'2026-11-05', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'estado', N'Decisión del docente (APROBAR o RECHAZAR)', N'APROBAR', 1),
    ('RECLAMO_ASISTENCIA_RESUELTO', 'observacion', N'Respuesta u observación del docente', N'Soporte médico validado.', 0),

    -- NOTIF-002B: Alertas preventivas y de pérdida
    ('ALERTA_RIESGO_INASISTENCIA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'porcentaje', N'Porcentaje de inasistencia acumulado', N'15.5', 1),
    ('ALERTA_RIESGO_INASISTENCIA', 'umbral', N'Umbral de advertencia institucional', N'15', 0),

    ('ALERTA_PERDIDA_INASISTENCIA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'porcentaje', N'Porcentaje de inasistencia acumulado', N'20.0', 1),
    ('ALERTA_PERDIDA_INASISTENCIA', 'limite', N'Límite reglamentario de pérdida por inasistencia', N'20', 0),

    -- NOTIF-002B: Cierre masivo de período
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'periodo', N'Código o nombre del período académico', N'2026-2', 1),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalEstudiantes', N'Total de matrículas procesadas', N'120', 0),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalAprobados', N'Total de aprobados por asistencia', N'108', 0),
    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'totalReprobados', N'Total de reprobados por inasistencia', N'12', 0)
) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
WHEN MATCHED THEN
    UPDATE SET
        Target.descripcion = Source.descripcion,
        Target.ejemplo     = Source.ejemplo,
        Target.obligatorio = Source.obligatorio
WHEN NOT MATCHED THEN
    INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
GO

DELETE FROM [dbo].[PlantillaNotificacionMarcador]
WHERE (tipo = 'RECLAMO_ASISTENCIA_RADICADO' AND marcador IN ('fechaSesion', 'causal'))
   OR (tipo = 'RECLAMO_ASISTENCIA_RESUELTO' AND marcador IN ('fechaSesion', 'resultado'));
GO

MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('RETIRO_ESTUDIANTE_GRUPO', 'es', 1, N'Retiro del grupo {grupo}', N'Se registró el retiro de {estudiante} del grupo {grupo}.', 1),
    ('SOLICITUD_INGRESO_REGISTRADA', 'es', 1, N'Nueva solicitud de ingreso al grupo {grupo}', N'{estudiante} solicitó ingresar al grupo {grupo}. Revísala en la plataforma.', 1),
    ('SOLICITUD_INGRESO_RESUELTA', 'es', 1, N'Respuesta a tu solicitud de ingreso al grupo {grupo}', N'Tu solicitud de ingreso al grupo {grupo} fue {resultado}. Consulta el detalle en la plataforma.', 1),
    ('SOLICITUD_INGRESO_RETIRADA', 'es', 1, N'Solicitud de ingreso retirada del grupo {grupo}', N'{estudiante} retiró su solicitud de ingreso al grupo {grupo}.', 1),

    -- NOTIF-002B: Plantillas automáticas
    ('RECLAMO_ASISTENCIA_RADICADO', 'es', 1,
     N'Nueva solicitud de revisión de asistencia en {grupo}',
     N'El estudiante {estudiante} radicó una solicitud de revisión de asistencia para la sesión del {fecha} en el grupo {grupo}. Motivo: {motivo}.',
     1),

    ('RECLAMO_ASISTENCIA_RESUELTO', 'es', 1,
     N'Respuesta a tu solicitud de revisión de asistencia en {grupo}',
     N'Tu solicitud de revisión de asistencia para la sesión del {fecha} en el grupo {grupo} fue resuelta como {estado}. Observaciones del docente: {observacion}.',
     1),

    ('ALERTA_RIESGO_INASISTENCIA', 'es', 1,
     N'Alerta de riesgo de inasistencia en {grupo}',
     N'Estimado(a) {estudiante}, se informa que acumula un {porcentaje}% de inasistencias en la asignatura {grupo}. Le recordamos que el límite institucional de inasistencia no justificada es del 20%.',
     1),

    ('ALERTA_PERDIDA_INASISTENCIA', 'es', 1,
     N'Alerta de pérdida por inasistencia en {grupo}',
     N'Estimado(a) {estudiante}, se informa que ha alcanzado el {porcentaje}% de inasistencias en la asignatura {grupo}, superando el límite institucional permitido. Por favor contacte a su docente o coordinación académica.',
     1),

    ('CIERRE_MASIVO_PERIODO_EJECUTADO', 'es', 1,
     N'Cierre masivo de periodo académico ejecutado',
     N'El cierre masivo del periodo académico {periodo} fue ejecutado exitosamente por el administrador institucional.',
     1)
) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
WHEN MATCHED THEN
    UPDATE SET
        Target.asunto = Source.asunto,
        Target.cuerpo = Source.cuerpo
WHEN NOT MATCHED THEN
    INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
GO
