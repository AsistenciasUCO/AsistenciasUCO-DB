USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por
-- matricula activa (sesionesEjecutadas = suma por matricula); retencion = (regular + riesgo) / total.
-- Cumplimiento (HU138) = sesiones vencidas con registro / sesiones vencidas. Censo (HU135/HU136): con matricula o grupo activo
-- en el periodo y registrados (usuario activo; docentes = titulares de al menos un grupo de la institucion, sin depender del periodo).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_institucion]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @facultades INT = (SELECT COUNT(*) FROM dbo.uv_facultad f WHERE f.idInstitucion = @idInstitucion);
    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idInstitucion = @idInstitucion);
    DECLARE @estudiantesRegistrados INT = (
        SELECT COUNT(DISTINCT ep.idEstudiante)
        FROM dbo.uv_estudiante_programa ep
        INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
        WHERE p.idInstitucion = @idInstitucion AND ei.estaActivoUsuario = 1);
    DECLARE @docentesRegistrados INT = (
        SELECT COUNT(DISTINCT g.idDocente)
        FROM dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE p.idInstitucion = @idInstitucion AND di.estaActivoUsuario = 1);

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @vencidas INT = 0, @conRegistro INT = 0;
    DECLARE @docentesActivos INT = 0;

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
                WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @conRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        INNER JOIN dbo.uv_programa p ON p.id = c.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND c.idPeriodoAcademico = @idPeriodo;

        SELECT  @docentesActivos = COUNT(DISTINCT g.idDocente)
        FROM    dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE   p.idInstitucion = @idInstitucion AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1;
    END

    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@sesiones = 0, NULL, 100.0 * @faltas / @sesiones) AS DECIMAL(5,2));

    SELECT
        idInstitucion = i.id,
        nombreInstitucion = i.nombre,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalFacultades = @facultades,
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
        sesionesVencidas = @vencidas,
        sesionesConRegistro = @conRegistro,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @conRegistro / @vencidas) AS DECIMAL(5,2)),
        estudiantesConMatriculaActiva = @total,
        estudiantesRegistrados = @estudiantesRegistrados,
        docentesConGrupoActivo = @docentesActivos,
        docentesRegistrados = @docentesRegistrados,
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_institucion i
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE i.id = @idInstitucion;
END;
GO
