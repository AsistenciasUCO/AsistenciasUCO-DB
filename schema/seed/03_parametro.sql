USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sembrado Idempotente Completo: Catálogo de Parámetros del Sistema (CatalogoParametro)
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    -- Parámetros Generales y de Sistema
    ('GENERAL', 'GUID_DEFECTO_CORRELACION', '00000000-0000-0000-0000-000000000000', 'UUID', '00000000-0000-0000-0000-000000000000'),
    ('GENERAL', 'UUID_DEFECTO', '00000000-0000-0000-0000-000000000000', 'UUID', '00000000-0000-0000-0000-000000000000'),
    ('GENERAL', 'IDIOMA_DEFECTO', 'es-CO', 'STRING', 'es-CO'),
    ('GENERAL', 'CADENA_VACIA', '', 'STRING', ''),
    ('GENERAL', 'ENTERO_CERO', '0', 'INT', '0'),

    -- Parámetros de Validación Biográfica y Formato
    ('VALIDACION', 'NUMERO_IDENTIFICACION_MIN_DIGITOS', '6', 'INT', '6'),
    ('VALIDACION', 'NUMERO_IDENTIFICACION_MAX_DIGITOS', '10', 'INT', '10'),

    -- Parámetros Globales Funcionales y Técnicos
    ('GLOBAL_FUN_GEN', 'Rol_Usuario', 'analista', 'STRING', 'analista'),
    ('GLOBAL_TEC_GEN', 'Año_Rango_Inicial', '2005', 'INT', '2005'),
    ('GLOBAL_TEC_GEN', 'Rango_Semestre', '14', 'INT', '14'),

    -- Parámetros de Perfiles y Roles Institucionales
    ('PERFIL', 'PERFIL_DEFECTO_ESTUDIANTE', 'ES', 'STRING', 'ES'),
    ('PERFIL', 'CODIGO_ESTUDIANTE', 'ES', 'STRING', 'ES'),
    ('PERFIL', 'CODIGO_DOCENTE', 'DO', 'STRING', 'DO'),
    ('PERFIL', 'CODIGO_COORDINADOR', 'CD', 'STRING', 'CD'),
    ('PERFIL', 'CODIGO_DECANO', 'DE', 'STRING', 'DE'),

    -- Parámetros de Grupos y Cupos
    ('GRUPO', 'CAPACIDAD_MAXIMA_DEFECTO', '40', 'INT', '40'),

    -- Parámetros de Control de Asistencia y Tolerancia
    ('ASISTENCIA', 'TOLERANCIA_MINUTOS', '15', 'INT', '15'),
    ('ASISTENCIA', 'MARGEN_RETARDO_MINUTOS', '30', 'INT', '30'),
    ('ASISTENCIA', 'DIAS_LIMITE_JUSTIFICACION', '5', 'INT', '5'),
    ('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA', '15', 'DECIMAL', '15'),
    ('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA', '20', 'DECIMAL', '20'),

    -- Política temporal base del contrato DB-GP-001
    ('TIEMPO', 'ZONA_HORARIA_IANA', 'America/Bogota', 'STRING', 'America/Bogota'),
    ('TIEMPO', 'ZONA_HORARIA_SQLSERVER', 'SA Pacific Standard Time', 'STRING', 'SA Pacific Standard Time'),
    ('TIEMPO', 'ALMACENAMIENTO_INSTANTES', 'UTC', 'STRING', 'UTC')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET 
        Target.valor = Source.valor, 
        Target.tipoDato = Source.tipoDato,
        Target.valorDefecto = Source.valorDefecto,
        Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
