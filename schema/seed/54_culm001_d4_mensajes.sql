USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.4 (CONTRACT §5.2, HU156): mensajes de la admision de estudiantes por el administrador. Idempotente (MERGE por codigo).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('ADS_001', 'SUCCESS',          'BAJO',  N'Estudiante admitido.'),
    ('ADS_002', 'BUSINESS_ERROR',   'BAJO',  N'El estudiante ya está admitido en este programa.'),
    ('ADS_003', 'BUSINESS_ERROR',   'MEDIO', N'El programa no existe o no pertenece a tu institución.'),
    ('ADS_004', 'BUSINESS_ERROR',   'MEDIO', N'El documento y el correo corresponden a personas distintas.'),
    ('ADS_005', 'VALIDATION_ERROR', 'BAJO',  N'El correo debe ser institucional ({}).'),
    ('ADS_006', 'VALIDATION_ERROR', 'BAJO',  N'Indica una contraseña inicial para el estudiante nuevo.')
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
    ('ADS_001', 'SUCCESS',          'BAJO',  N'HU156: estudiante admitido en el programa; Usuario, Estudiante y EstudiantePrograma confirmados.'),
    ('ADS_002', 'BUSINESS_ERROR',   'BAJO',  N'HU156: EstudiantePrograma ya existe para el estudiante y el programa; sin escrituras.'),
    ('ADS_003', 'BUSINESS_ERROR',   'MEDIO', N'Ambito: el programa no existe, esta inactivo o no es de la institucion del administrador; sin escrituras.'),
    ('ADS_004', 'BUSINESS_ERROR',   'MEDIO', N'Regla: el documento y el correo no pertenecen al mismo Usuario (SUPUESTO-D-11); sin escrituras.'),
    ('ADS_005', 'VALIDATION_ERROR', 'BAJO',  N'Regla: el correo de un alta nueva no cumple REGISTRO/DOMINIO_CORREO_ESTUDIANTE ({}); sin escrituras.'),
    ('ADS_006', 'VALIDATION_ERROR', 'BAJO',  N'Regla: un alta nueva exige el hash de la contrasena inicial; sin escrituras.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
