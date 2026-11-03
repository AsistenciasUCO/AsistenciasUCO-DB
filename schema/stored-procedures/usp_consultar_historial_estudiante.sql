USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_historial_estudiante (HU157 ficha unificada del estudiante con historial completo)
--
-- Una fila por matricula (programa, periodo, grupo) del estudiante con sus datos personales repetidos en cada fila
-- y el resumen de asistencia del grupo (las mismas vistas que la ficha y el resumen de HU069:
-- uv_usuario y uv_resumen_asistencia_estudiante_grupo). Un estudiante sin grupos devuelve una fila con los datos
-- del programa y las columnas del grupo en NULL. 0 filas si el estudiante no esta en el ambito del ejecutor.
--
-- Resultset: READ_QUERY_RESULTSET (filas de detalle), NO el resultset canonico de 4 columnas de los comandos.
-- Las fallas se propagan con THROW (VAL_001 / SEC_001).
-- Ambito: solo perfiles ADMINISTRADOR o DECANO (SEC_001); las filas salen de uv_auth_estudiante (fail-closed):
-- el administrador ve las matriculas de su institucion y el decano solo las de su facultad.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_historial_estudiante]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGuidVacio             UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: idCorrelacion presente
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor y estudiante obligatorios (VAL_001)
        IF @estadoResultado = 1
           AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @idGuidVacio OR @idEstudianteDefecto IS NULL OR @idEstudianteDefecto = @idGuidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor/Estudiante',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil ADMINISTRADOR o DECANO (SEC_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR,DECANO',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- PASO 4: Fijar el contexto del ejecutor para las vistas uv_auth_*
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        -- PASO 5: Consulta y retorno de resultados
        SELECT
            idEstudiante              = e.id,
            idUsuario                 = e.idUsuario,
            tipoIdentificacion        = u.TipoIdentificacion,
            numeroIdentificacion      = e.numeroIdentificacion,
            nombreCompleto            = e.nombreCompleto,
            correo                    = u.correo,
            estaActivoUsuario         = e.estaActivoUsuario,
            idFacultad                = e.idFacultad,
            nombreFacultad            = e.nombreFacultad,
            idPrograma                = e.idPrograma,
            nombrePrograma            = e.nombrePrograma,
            inpPlanEstudio            = e.inpPlanEstudio,
            idPeriodoAcademico        = pa.id,
            codigoPeriodoAcademico    = pa.codigo,
            nombrePeriodoAcademico    = pa.nombre,
            idGrupo                   = e.idGrupo,
            codigoGrupo               = eg.codigoGrupo,
            idAsignatura              = e.idAsignatura,
            nombreAsignatura          = e.nombreAsignatura,
            codigoEstadoEstudiante    = eg.codigoEstadoEstudiante,
            nombreEstadoEstudiante    = eg.nombreEstadoEstudiante,
            sesionesEjecutadas        = r.sesionesEjecutadas,
            asistencias               = r.asistencias,
            faltasSinJustaCausa       = r.faltasSinJustaCausa,
            excusas                   = r.excusas,
            porcentajeInasistencia    = r.porcentajeInasistencia,
            codigoPermanencia         = r.codigoPermanencia
        FROM dbo.uv_auth_estudiante e
        LEFT JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        LEFT JOIN dbo.uv_estudiante_grupo eg ON eg.idEstudiante = e.id AND eg.idGrupo = e.idGrupo
        LEFT JOIN dbo.uv_resumen_asistencia_estudiante_grupo r ON r.idEstudianteGrupo = eg.id
        LEFT JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = e.idGrupo
        LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = gp.idPeriodoAcademico
        WHERE e.id = @idEstudiante
        ORDER BY pa.fechaInicio DESC, e.nombrePrograma ASC, e.nombreAsignatura ASC, e.idGrupo ASC;

        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'idUsuarioEjecutor',
            @value = @contextoPrevio,
            @read_only = 0;
        THROW;
    END CATCH;
END;
GO
