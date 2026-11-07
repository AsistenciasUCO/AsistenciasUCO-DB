USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero.
-- asistio = NULL cuando la sesion vencida no tiene registro de ese estudiante.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_bitacora_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 3: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;
    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idSesion = s.id,
        numeroSesion = s.numero,
        nombreSesion = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        asistio = d.asistio,
        codigoRazonCausa = d.codigoRazonCausa,
        nombreRazonCausa = d.nombreRazonCausa,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idGrupo = eg.idGrupo AND c.estaVencida = 1
    INNER JOIN dbo.uv_sesion_v2 s ON s.id = c.idSesion
    INNER JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
    -- CULM-001 B.2 (CONTRACT §2.9): estado consolidado de la sesion (uv_asistencia_sesion_horas): una fila aunque haya varias tomas
    OUTER APPLY (
        SELECT TOP 1 asistio = CAST(IIF(h.codigoRazonCausaConsolidado = N'AN', 1, 0) AS BIT),
               codigoRazonCausa = rc.codigo, nombreRazonCausa = rc.nombre, h.horasFalta
        FROM dbo.uv_asistencia_sesion_horas h
        LEFT JOIN dbo.uv_razon_causa rc ON rc.codigo = h.codigoRazonCausaConsolidado
        WHERE h.idEstudianteGrupo = eg.id AND h.idSesion = s.id AND h.codigoRazonCausaConsolidado IS NOT NULL
    ) d
    WHERE eg.idEstudiante = @idEstudiante
      AND c.idPrograma = @idPrograma
      AND c.idPeriodoAcademico = @idPeriodo
    ORDER BY s.fechaHoraInicio DESC, s.id DESC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
