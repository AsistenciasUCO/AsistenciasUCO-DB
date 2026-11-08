USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.6 (CONTRACT v2 §7.3, HU172, R-4): mensajes de la consulta de auditoria. Idempotente (MERGE por codigo).
-- AUD_001: [SUPUESTO-D-16], la auditoria no tiene ambito por institucion (el prefijo AUD no existia en las semillas).
-- AUD_002: filtros excluyentes @soloAsistencia y @soloAdministracion; el backend siempre envia los dos explicitos, asi que
-- el usuario no lo ve; vive aqui por ser SSOT de mensajes (desviacion menor del contrato, que solo preveia AUD_001).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('AUD_001', 'BUSINESS_ERROR',   'MEDIO', N'La consulta de auditoría requiere una sola institución activa.'),
    ('AUD_002', 'VALIDATION_ERROR', 'BAJO',  N'Los filtros de solo asistencia y solo administración no se pueden combinar.')
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
    ('AUD_001', 'BUSINESS_ERROR',   'MEDIO', N'SUPUESTO-D-16: hay {} instituciones activas; la auditoría no tiene ámbito por institución.'),
    ('AUD_002', 'VALIDATION_ERROR', 'BAJO',  N'@soloAsistencia = 1 y @soloAdministracion = 1 son excluyentes; el llamador debe enviar los dos parametros explicitos.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
