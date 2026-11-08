USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.1 (CONTRACT §2.2, HU026B): mensajes del plazo de excusas. Idempotente (MERGE por codigo).
--   REV_020  la radicacion llega despues del limite (el mensaje de usuario informa la ultima fecha local admitida)
--   REV_025  falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER: no se puede validar el plazo
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('REV_020', 'BUSINESS_ERROR',  'MEDIO', N'El plazo para justificar esta inasistencia venció el {}.'),
    ('REV_025', 'TECHNICAL_ERROR', 'ALTO',  N'No es posible validar el plazo de justificación en este momento.')
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
    ('REV_020', 'BUSINESS_ERROR',  'MEDIO', N'HU026B: instante {} >= límite {} (ASISTENCIA/DIAS_LIMITE_JUSTIFICACION={}).'),
    ('REV_025', 'TECHNICAL_ERROR', 'ALTO',  N'HU026B: falta ASISTENCIA/DIAS_LIMITE_JUSTIFICACION o TIEMPO/ZONA_HORARIA_SQLSERVER.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
