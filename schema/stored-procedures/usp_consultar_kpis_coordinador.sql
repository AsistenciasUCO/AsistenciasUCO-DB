USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_coordinador (HU065, HU070). READ_QUERY_RESULTSET (1 fila). Solo lectura: sin XACT_ABORT.
-- Ambito: el programa que coordina el ejecutor. Todas las cifras salen de las vistas de resumen (ver CONTRACT §1).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_coordinador]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT;
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @programadas INT = 0, @vencidas INT = 0, @ejecutadas INT = 0, @sinRegistro INT = 0, @sinProcedencia INT = 0;

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
                WHERE   r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @programadas = COUNT(*),
                @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @ejecutadas = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0),
                @sinRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 0, 1, 0)), 0),
                @sinProcedencia = ISNULL(SUM(IIF(c.procedenciaIndeterminada = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        WHERE   c.idPrograma = @idPrograma AND c.idPeriodoAcademico = @idPeriodo;
    END

    SELECT
        idPrograma = p.id,
        nombrePrograma = p.nombrePrograma,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaPermanencia = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesProgramadas = @programadas,
        sesionesVencidas = @vencidas,
        sesionesEjecutadas = @ejecutadas,
        sesionesVencidasSinRegistro = @sinRegistro,
        sesionesSinProcedenciaTemporal = @sinProcedencia,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @ejecutadas / @vencidas) AS DECIMAL(5,2)),
        porcentajeProgresoCalendario = CAST(IIF(@programadas = 0, NULL, 100.0 * @vencidas / @programadas) AS DECIMAL(5,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_programa p
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE p.id = @idPrograma;
END;
GO
