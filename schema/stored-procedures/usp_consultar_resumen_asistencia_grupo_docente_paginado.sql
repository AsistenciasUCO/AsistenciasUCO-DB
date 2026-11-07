USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_grupo_docente_paginado (CULM-001 B.2, HU040/HU041; CONTRACT §2.8.4, §3.2.8, F-DOC-004)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001,
-- PAG_001, GRU_*, SEC_002). RBAC DOCENTE titular del grupo. Filas: columnas de uv_resumen_asistencia_estudiante_grupo
-- (indicadores por horas) + nombreCompletoEstudiante + totalRegistros, orden nombreCompletoEstudiante (sabana del docente:
-- el cliente no calcula porcentajes).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_grupo_docente_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idGrupo           UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 50
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @offset INT;
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'DOCENTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_grupo_exista_por_id_interno
            @idGrupo = @idGrupoDefecto, @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 1
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto, @idEntidadPadre = @idGrupoDefecto, @tipoEntidadPadre = 'GRUPO',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;
    SELECT
        idEstudianteGrupo              = r.idEstudianteGrupo,
        idEstudiante                   = r.idEstudiante,
        idGrupo                        = r.idGrupo,
        idAsignatura                   = r.idAsignatura,
        idPrograma                     = r.idPrograma,
        idPeriodoAcademico             = r.idPeriodoAcademico,
        codigoEstadoEstudiante         = r.codigoEstadoEstudiante,
        sesionesEjecutadas             = r.sesionesEjecutadas,
        asistencias                    = r.asistencias,
        faltasSinJustaCausa            = r.faltasSinJustaCausa,
        excusas                        = r.excusas,
        porcentajeInasistencia         = r.porcentajeInasistencia,
        codigoPermanencia              = r.codigoPermanencia,
        tomasDictadas                  = r.tomasDictadas,
        horasDictadas                  = r.horasDictadas,
        horasAsistidas                 = r.horasAsistidas,
        horasFalta                     = r.horasFalta,
        horasExcusa                    = r.horasExcusa,
        horasSinRegistro               = r.horasSinRegistro,
        porcentajeAsistenciaHoras      = r.porcentajeAsistenciaHoras,
        porcentajeExcusaHoras          = r.porcentajeExcusaHoras,
        porcentajeSinRegistroHoras     = r.porcentajeSinRegistroHoras,
        porcentajeInasistenciaSesiones = r.porcentajeInasistenciaSesiones,
        umbralAdvertencia              = r.umbralAdvertencia,
        umbralPerdida                  = r.umbralPerdida,
        sesionesAsistidas              = r.sesionesAsistidas,
        sesionesConFaltaSinJustaCausa  = r.sesionesConFaltaSinJustaCausa,
        sesionesConExcusa              = r.sesionesConExcusa,
        nombreCompletoEstudiante       = eg.nombreCompletoEstudiante,
        totalRegistros                 = COUNT(1) OVER()
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    WHERE r.idGrupo = @idGrupoDefecto
    ORDER BY eg.nombreCompletoEstudiante ASC, r.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO
