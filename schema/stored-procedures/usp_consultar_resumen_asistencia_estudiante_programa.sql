USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT;
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    SELECT
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        nombreEstadoEstudiante = eg.nombreEstadoEstudiante,
        sesionesEjecutadas = r.sesionesEjecutadas,
        asistencias = r.asistencias,
        faltasSinJustaCausa = r.faltasSinJustaCausa,
        excusas = r.excusas,
        porcentajeInasistencia = r.porcentajeInasistencia,
        codigoPermanencia = r.codigoPermanencia
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    INNER JOIN dbo.uv_grupo g ON g.id = r.idGrupo
    WHERE r.idEstudiante = @idEstudiante AND r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo
    ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC;
END;
GO
