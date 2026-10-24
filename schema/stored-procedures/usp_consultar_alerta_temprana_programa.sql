USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_alerta_temprana_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @semaforo           NVARCHAR(5)      = NULL,
    @filtroTexto        NVARCHAR(100)    = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @filtro NVARCHAR(100) = NULLIF(TRIM(@filtroTexto), '');

    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT;
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
    IF @semaforo IS NOT NULL AND @semaforo NOT IN (N'VERDE', N'AMBAR', N'ROJO')
    BEGIN
        SET @msgP1 = CAST(N'semaforo' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    WITH persona AS (
        SELECT  r.idEstudiante,
                totalMatriculasActivas = COUNT(*),
                porcentajeInasistencia = MAX(r.porcentajeInasistencia),
                faltasSinJustaCausa = SUM(r.faltasSinJustaCausa),
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idEstudiante
    )
    SELECT
        idEstudiante = pe.idEstudiante,
        nombreCompleto = u.nombreCompleto,
        numeroIdentificacion = u.numeroIdentificacion,
        correo = u.correo,
        totalMatriculasActivas = pe.totalMatriculasActivas,
        porcentajeInasistencia = pe.porcentajeInasistencia,
        faltasSinJustaCausa = pe.faltasSinJustaCausa,
        codigoPermanencia = CASE pe.peor WHEN 3 THEN N'PERDIDA' WHEN 2 THEN N'RIESGO' ELSE N'REGULAR' END,
        semaforo = CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END,
        totalRegistros = COUNT(*) OVER()
    FROM persona pe
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = pe.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE (@semaforo IS NULL OR (CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END) = @semaforo)
      AND (@filtro IS NULL
           OR CHARINDEX(@filtro, u.nombreCompleto) > 0
           OR CHARINDEX(@filtro, CONVERT(NVARCHAR(20), u.numeroIdentificacion)) > 0
           OR CHARINDEX(@filtro, u.correo) > 0)
    ORDER BY pe.porcentajeInasistencia DESC, u.nombreCompleto ASC, pe.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
