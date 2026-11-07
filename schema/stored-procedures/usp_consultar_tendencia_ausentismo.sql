USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional
-- (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) del inicio de la sesion. Solo sesiones vencidas con registro; solo intervalos con datos.
-- Ausentismo del intervalo = faltas SJC / sesiones-estudiante (matriculas activas de cada sesion ejecutada), igual que los KPIs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tendencia_ausentismo]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @granularidad       NVARCHAR(6)      = N'SEMANA'
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idInstitucion = @idInstitucion OUTPUT;

    DECLARE @g NVARCHAR(6) = UPPER(TRIM(ISNULL(@granularidad, N'SEMANA')));
    -- PASO 2: Validacion de negocio (GEN_002)
    IF @g NOT IN (N'SEMANA', N'MES')
    BEGIN
        SET @msgP1 = CAST(N'granularidad' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @zona NVARCHAR(100) = COALESCE(
        (SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
        'SA Pacific Standard Time');

    -- PASO 4: Consulta y retorno de resultados
    WITH ejecutadas AS (
        SELECT  c.idSesion, c.idGrupo,
                fechaLocal = CAST(c.fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        INNER JOIN dbo.uv_programa p ON p.id = c.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND c.idPeriodoAcademico = @idPeriodo
          AND   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
    ),
    activos AS (
        SELECT idGrupo, n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE codigoEstadoEstudiante = N'A' GROUP BY idGrupo
    ),
    faltas AS (
        -- CULM-001 B.2 (CONTRACT §2.9; diferido a D: debe pasar a horas): una falta por estudiante y sesion segun el estado
        -- consolidado (uv_asistencia_sesion_horas); con una toma por sesion, identico al conteo anterior.
        SELECT  h.idSesion, f = SUM(IIF(h.tieneFaltaSinJustaCausa = 1, 1, 0))
        FROM    dbo.uv_asistencia_sesion_horas h
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = h.idEstudianteGrupo AND eg.codigoEstadoEstudiante = N'A'
        GROUP BY h.idSesion
    ),
    intervalo AS (
        SELECT  e.idSesion,
                inicio = CASE @g WHEN N'MES' THEN DATEFROMPARTS(YEAR(e.fechaLocal), MONTH(e.fechaLocal), 1)
                                 ELSE DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal) END,
                fin = CASE @g WHEN N'MES' THEN EOMONTH(e.fechaLocal)
                              ELSE DATEADD(DAY, 6, DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal)) END,
                sesionesEstudiante = ISNULL(ac.n, 0),
                faltas = ISNULL(fa.f, 0)
        FROM    ejecutadas e
        LEFT JOIN activos ac ON ac.idGrupo = e.idGrupo
        LEFT JOIN faltas fa ON fa.idSesion = e.idSesion
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        inicioIntervalo = inicio,
        finIntervalo = fin,
        sesionesEjecutadas = SUM(sesionesEstudiante),
        faltasSinJustaCausa = SUM(faltas),
        porcentajeAusentismo = CAST(IIF(SUM(sesionesEstudiante) = 0, NULL, 100.0 * SUM(faltas) / SUM(sesionesEstudiante)) AS DECIMAL(5,2))
    FROM intervalo
    GROUP BY inicio, fin
    ORDER BY inicio ASC;
END;
GO
