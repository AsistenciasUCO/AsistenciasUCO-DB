USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.12): plantilla de notificacion SESION_CANCELADA (HU047) y sus marcadores. Patron
-- 26_plantillas_notificacion.sql (MERGE idempotente; la version 1 la crea el sistema, creadoPor NULL). El mismo texto
-- por defecto vive en PlantillaPorDefectoCatalogo del backend. La cancelacion automatica por FESTIVO no notifica.
MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
USING (VALUES
    ('SESION_CANCELADA', 'estudiante', N'Nombre completo del estudiante', N'Juan Pérez', 1),
    ('SESION_CANCELADA', 'asignatura', N'Nombre de la asignatura', N'Ingeniería de Software', 1),
    ('SESION_CANCELADA', 'grupo',      N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
    ('SESION_CANCELADA', 'fecha',      N'Fecha de la sesión cancelada', N'2026-11-10', 1),
    ('SESION_CANCELADA', 'horaInicio', N'Hora de inicio de la sesión (hora institucional)', N'08:00', 1),
    ('SESION_CANCELADA', 'horaFin',    N'Hora de fin de la sesión (hora institucional)', N'10:00', 1),
    ('SESION_CANCELADA', 'motivo',     N'Motivo de la cancelación registrado por el docente', N'Calamidad doméstica del docente', 1),
    ('SESION_CANCELADA', 'docente',    N'Nombre completo del docente titular', N'María Rostagno', 1)
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

MERGE INTO [dbo].[PlantillaNotificacion] AS Target
USING (VALUES
    ('SESION_CANCELADA', 'es', 1,
     N'Clase cancelada: {asignatura} ({fecha})',
     N'Hola {estudiante}. El docente {docente} canceló la clase de {asignatura} del grupo {grupo} programada para el {fecha} de {horaInicio} a {horaFin}. Motivo: {motivo}.',
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
