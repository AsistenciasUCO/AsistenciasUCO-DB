USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- uv_auditoria_evento (HU172): vista base de solo lectura sobre dbo.AuditoriaEvento (tabla inmutable por contrato,
-- DB_BASELINE_CONTRACT). Agrega el nombre del usuario que actuo (actorId es el Usuario.id en texto cuando actorType =
-- USER) y marca las acciones relacionadas con la asistencia (registro, revisiones, sesiones, retiro y cierre masivo).
-- Sin filtro de autorizacion: solo la lee usp_consultar_auditoria_eventos_paginado, que exige perfil ADMINISTRADOR.
CREATE OR ALTER VIEW [dbo].[uv_auditoria_evento]
AS
SELECT  ae.id,
        ae.occurredAt,
        ae.actorId,
        ae.actorType,
        nombreActor = u.nombreCompleto,
        ae.action,
        ae.resourceType,
        ae.resourceId,
        ae.result,
        ae.correlationId,
        ae.httpMethod,
        ae.path,
        ae.httpStatus,
        ae.clientIp,
        ae.errorCode,
        ae.metadata,
        esAccionAsistencia = IIF(ae.action IN (
                                    'REGISTRAR_ASISTENCIA', 'REGISTRAR_ASISTENCIAS_SESION',
                                    'SOLICITAR_REVISION_ASISTENCIA', 'RESOLVER_SOLICITUD_REVISION_ASISTENCIA',
                                    'CREAR_SESION', 'GENERAR_SESIONES_GRUPO', 'CERRAR_SESION',
                                    'RETIRO_ESTUDIANTE_GRUPO', 'CIERRE_MASIVO_PERIODO'), 1, 0)
FROM    dbo.AuditoriaEvento ae
LEFT JOIN dbo.uv_usuario u
ON      u.id = TRY_CAST(ae.actorId AS UNIQUEIDENTIFIER);
GO
