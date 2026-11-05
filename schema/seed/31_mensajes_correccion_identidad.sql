USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU159 (decision de John 2026-11-05): correccion de los datos de identidad de decanos, coordinadores, docentes y
-- estudiantes por jerarquia. IDE_003: la correccion del documento esta apagada (IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('IDE_001', 'BUSINESS_ERROR', 'MEDIO', N'El motivo de la corrección es obligatorio y no puede superar 500 caracteres.'),
    ('IDE_002', 'SUCCESS', 'BAJO', N'Los datos de identidad fueron corregidos.'),
    ('IDE_003', 'BUSINESS_ERROR', 'MEDIO', N'La corrección del tipo o número de documento no está habilitada.')
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
    ('IDE_001', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @motivo nulo, vacio o de mas de 500 caracteres.'),
    ('IDE_002', 'SUCCESS', 'BAJO', N'Actualizacion: dbo.Usuario (documento, nombres y apellidos) y registro en dbo.AuditoriaEvento.'),
    ('IDE_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla de negocio: IDENTIDAD.PERMITIR_CORREGIR_DOCUMENTO distinto de 1; el documento no se modifica.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
