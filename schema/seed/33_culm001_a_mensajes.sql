USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 paquete A.2 (A2-DB-6; numeracion 33 de A; idempotente): mensajes de usuario y tecnicos.
-- Rango de sesion de A (DEC-031 §1): B ocupa SES_010..SES_016, A usa SES_017 en adelante y C usara SES_030 en adelante.
--   SES_017 solape de sesiones (A.2-10)       REV_006..REV_008 retiro del reclamo propio (A.2-7)
--   DEC_002/DEC_003 cambio de estado del decano (A.2-8)
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SES_017', 'BUSINESS_ERROR', 'MEDIO', N'La sesión se cruza con otra sesión del grupo o del docente en ese horario.'),
    ('REV_006', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud de revisión no existe.'),
    ('REV_007', 'BUSINESS_ERROR', 'MEDIO', N'Solo se puede retirar una solicitud de revisión pendiente.'),
    ('REV_008', 'SUCCESS',        'BAJO',  N'La solicitud de revisión fue retirada.'),
    ('DEC_002', 'BUSINESS_ERROR', 'ALTO',  N'No se puede desactivar al decano de una facultad con programas activos.'),
    ('DEC_003', 'SUCCESS',        'BAJO',  N'Se actualizó el estado del decano.')
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
    ('SES_017', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la sesion se cruza con la sesion [{}] del mismo grupo o de otro grupo del mismo docente (inicio < fin y fin > inicio); sin escrituras.'),
    ('REV_006', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: la solicitud de revision [{}] no existe o no es del estudiante ejecutor; sin escrituras.'),
    ('REV_007', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud de revision [{}] no esta en el estado de RECLAMO/ESTADO_PENDIENTE; sin escrituras.'),
    ('REV_008', 'SUCCESS',        'BAJO',  N'Actualizacion: la solicitud de revision [{}] paso al estado de RECLAMO/ESTADO_RETIRADO.'),
    ('DEC_002', 'BUSINESS_ERROR', 'ALTO',  N'Regla: el decano [{}] dirige una facultad con el programa activo [{}]; no se desactiva.'),
    ('DEC_003', 'SUCCESS',        'BAJO',  N'Actualizacion: Decano.estado del decano [{}] actualizado (regla D1 aplicada a Usuario.estado).')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
