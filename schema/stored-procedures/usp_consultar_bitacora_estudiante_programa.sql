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

    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT;
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
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
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

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
    OUTER APPLY (
        SELECT TOP 1 da.asistio, da.codigoRazonCausa, da.nombreRazonCausa
        FROM dbo.uv_asistencia a
        INNER JOIN dbo.uv_detalle_asistencia da ON da.idAsistencia = a.id
        WHERE a.idEstudianteGrupo = eg.id AND a.idSesion = s.id
        ORDER BY da.fechaHoraInicio DESC, da.id ASC
    ) d
    WHERE eg.idEstudiante = @idEstudiante
      AND c.idPrograma = @idPrograma
      AND c.idPeriodoAcademico = @idPeriodo
    ORDER BY s.fechaHoraInicio DESC, s.id DESC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
