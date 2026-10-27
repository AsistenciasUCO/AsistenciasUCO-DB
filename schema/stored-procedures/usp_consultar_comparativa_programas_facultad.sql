USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura.
-- Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_programas_facultad]
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

    WITH persona AS (
        SELECT  r.idPrograma, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma, r.idEstudiante
    ),
    conteo AS (
        SELECT  idPrograma,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idPrograma
    ),
    asistencia AS (
        SELECT  r.idPrograma,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.faltasSinJustaCausa)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma
    ),
    resultado AS (
        SELECT
            idPrograma = p.id,
            nombrePrograma = p.nombrePrograma,
            estaActivoPrograma = CAST(p.estaActivoPrograma AS BIT),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.sesiones, 0) = 0, NULL, 100.0 * a.faltas / a.sesiones) AS DECIMAL(5,2))
        FROM dbo.uv_programa p
        LEFT JOIN conteo c ON c.idPrograma = p.id
        LEFT JOIN asistencia a ON a.idPrograma = p.id
        WHERE p.idFacultad = @idFacultad
    )
    SELECT idPrograma, nombrePrograma, estaActivoPrograma, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombrePrograma ASC, idPrograma ASC;
END;
GO
