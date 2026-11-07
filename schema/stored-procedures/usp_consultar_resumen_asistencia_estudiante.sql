USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_estudiante (CULM-001 B.2, HU004/HU009/HU013; CONTRACT §2.8.4, §3.2.8, F-EST-002)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 si la validacion falla: GEN_002, SEC_001).
-- RBAC ESTUDIANTE; solo las matriculas del propio estudiante (Estudiante.usuario = @idUsuarioEjecutor). Filas: columnas de
-- uv_resumen_asistencia_estudiante_grupo (indicadores por horas). Sin paginacion (a lo sumo las materias del estudiante).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_estudiante]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

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
            @idUsuario = @idUsuarioDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

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
        sesionesConExcusa              = r.sesionesConExcusa
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.Estudiante e ON e.id = r.idEstudiante
    WHERE e.usuario = @idUsuarioDefecto
    ORDER BY r.idPeriodoAcademico ASC, r.idGrupo ASC;
END;
GO
