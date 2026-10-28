USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_historial_grupos_docente_programa (HU094)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Ficha del docente para el COORDINADOR: historial de los grupos que el docente dicto o dicta en el programa del
-- coordinador, en todos los periodos (filtro opcional por periodo), del mas reciente al mas antiguo.
--   - el programa se resuelve del ejecutor (usp_resolver_programa_coordinador_interno; KPI_001 si no coordina);
--   - el docente debe tener una vinculacion (activa o inactiva) con ese programa; si no, GEN_001 (indistinguible de
--     un docente inexistente, para no revelar docentes de otros programas);
--   - estadoPeriodo: VIGENTE / FINALIZADO / PROXIMO segun la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER);
--   - las columnas resumen* agregan TODO el historial del docente en el programa (no dependen del filtro de periodo
--     ni de la pagina) y se repiten en cada fila.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100). Solo lectura: sin XACT_ABORT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_historial_grupos_docente_programa]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @idDocente           UNIQUEIDENTIFIER,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @numeroPagina        INT              = 1,
    @tamanoPagina        INT              = 10
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER;
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @zonaHoraria NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

    EXEC dbo.usp_resolver_programa_coordinador_interno
        @idUsuarioEjecutor = @idUsuarioEjecutor,
        @idCorrelacion = @idCorrelacion,
        @validarUmbrales = 0,
        @idPrograma = @idPrograma OUTPUT;

    IF @idDocente IS NULL
    BEGIN
        SET @msgP1 = CAST(N'Docente' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = @idDocente AND dp.programa = @idPrograma)
    BEGIN
        SET @msgP1 = CAST(N'Docente' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_001',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    ;WITH historial AS (
        SELECT
            g.id, g.codigo, g.nombre, g.idAsignatura, g.nombreAsignatura,
            g.idPeriodoAcademico, pa.codigo AS codigoPeriodo, pa.nombre AS nombrePeriodo,
            pa.fechaInicio, pa.fechaFin,
            estadoPeriodo = CASE
                                WHEN @hoyLocal < pa.fechaInicio THEN 'PROXIMO'
                                WHEN @hoyLocal > pa.fechaFin THEN 'FINALIZADO'
                                ELSE 'VIGENTE'
                            END,
            g.capacidadMaximaPermitida, g.estudiantesActivos, g.estudiantesFinalizados,
            g.estudiantesCanceladosVoluntad, g.estudiantesCanceladosInasistencia
        FROM dbo.uv_grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.idPeriodoAcademico
        INNER JOIN dbo.Asignatura a ON a.id = g.idAsignatura
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        WHERE g.idDocente = @idDocente
          AND pe.programa = @idPrograma
    ),
    resumen AS (
        SELECT
            totalGrupos      = COUNT(*),
            totalPeriodos    = COUNT(DISTINCT h.idPeriodoAcademico),
            gruposVigentes   = SUM(IIF(h.estadoPeriodo = 'VIGENTE', 1, 0)),
            activosVigentes  = SUM(IIF(h.estadoPeriodo = 'VIGENTE', h.estudiantesActivos, 0))
        FROM historial h
    )
    SELECT
        idGrupo                           = h.id,
        codigoGrupo                       = h.codigo,
        nombreGrupo                       = h.nombre,
        idAsignatura                      = h.idAsignatura,
        nombreAsignatura                  = h.nombreAsignatura,
        idPeriodoAcademico                = h.idPeriodoAcademico,
        codigoPeriodoAcademico            = h.codigoPeriodo,
        nombrePeriodoAcademico            = h.nombrePeriodo,
        fechaInicioPeriodo                = h.fechaInicio,
        fechaFinPeriodo                   = h.fechaFin,
        estadoPeriodo                     = CAST(h.estadoPeriodo AS NVARCHAR(10)),
        capacidadMaxima                   = h.capacidadMaximaPermitida,
        estudiantesActivos                = h.estudiantesActivos,
        estudiantesFinalizados            = h.estudiantesFinalizados,
        estudiantesCanceladosVoluntad     = h.estudiantesCanceladosVoluntad,
        estudiantesCanceladosInasistencia = h.estudiantesCanceladosInasistencia,
        resumenTotalGrupos                = r.totalGrupos,
        resumenTotalPeriodos              = r.totalPeriodos,
        resumenGruposVigentes             = ISNULL(r.gruposVigentes, 0),
        resumenEstudiantesActivosVigentes = ISNULL(r.activosVigentes, 0),
        totalRegistros                    = COUNT(*) OVER()
    FROM historial h
    CROSS JOIN resumen r
    WHERE (@idPeriodoAcademico IS NULL OR h.idPeriodoAcademico = @idPeriodoAcademico)
    ORDER BY h.fechaInicio DESC, h.nombreAsignatura ASC, h.codigo ASC, h.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
