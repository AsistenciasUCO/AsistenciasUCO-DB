USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3).
-- Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / sesiones ejecutadas, ponderado por matricula activa (D1).
-- sesionesEjecutadas = suma por matricula activa (denominador del ausentismo). Aforo = matriculados activos / cupo de los grupos habilitados (D4).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_decano]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idFacultad = @idFacultad);
    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @grupos INT = 0, @cupo INT = 0, @matriculados INT = 0;

    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
                WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @grupos = COUNT(*),
                @cupo = ISNULL(SUM(g.capacidadMaximaPermitida), 0),
                @matriculados = ISNULL(SUM(g.estudiantesActivos), 0)
        FROM    dbo.uv_grupo_programa gp
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_grupo g ON g.id = gp.idGrupo
        WHERE   p.idFacultad = @idFacultad AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1;
    END

    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@sesiones = 0, NULL, 100.0 * @faltas / @sesiones) AS DECIMAL(5,2));

    SELECT
        idFacultad = f.id,
        nombreFacultad = f.nombreFacultad,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        gruposActivos = @grupos,
        cupoTotal = @cupo,
        matriculadosActivos = @matriculados,
        tasaAforo = CAST(IIF(@cupo = 0, NULL, 100.0 * @matriculados / @cupo) AS DECIMAL(7,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_facultad f
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE f.id = @idFacultad;
END;
GO
