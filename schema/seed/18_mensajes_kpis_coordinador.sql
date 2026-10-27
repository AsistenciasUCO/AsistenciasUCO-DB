USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065-HU070: mensajes de KPIs del coordinador (archivo propio; no colisiona con 04_mensaje.sql).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('KPI_001', 'BUSINESS_ERROR', 'ALTO', N'No tiene un programa académico a su cargo para consultar estos indicadores.'),
    ('KPI_002', 'BUSINESS_ERROR', 'CRITICO', N'No fue posible calcular los indicadores porque falta la configuración de umbrales de asistencia.')
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
    ('KPI_001', 'BUSINESS_ERROR', 'ALTO', N'Ámbito: el ejecutor {} no coordina ningún programa en uv_programa.'),
    ('KPI_002', 'BUSINESS_ERROR', 'CRITICO', N'Falta el parámetro ASISTENCIA/UMBRAL_ALERTA_ADVERTENCIA o ASISTENCIA/UMBRAL_ALERTA_PERDIDA en CatalogoParametro.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
