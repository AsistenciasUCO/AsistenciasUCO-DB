USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU055: estados adicionales de dbo.Estado para SolicitudIngresoGrupo (aprobados por John, 2026-10-27).
-- E = en espera (sin cupo al aceptar), X = retirada por el estudiante. Los ids son fijos: el indice unico filtrado
-- UX_SolicitudIngresoGrupo_Abierta los referencia. Los reclamos (SolicitudRevisionAsistencia) siguen usando P/A/R.
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES
    ('C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E', 'en espera', 'E'),
    ('D6E2F3A4-5B6C-4D7E-9F80-A12B3C4D5E6F', 'retirada', 'X')
) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo)
    VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO
