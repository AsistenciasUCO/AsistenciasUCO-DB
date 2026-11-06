USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_consolidado_asistencia_grupos_paginado (HU061 consolidado por cohorte, materia y docente)
--
-- Una fila por grupo con el consolidado de asistencia de sus estudiantes. Decision de John (2026-11-04): la cohorte es
-- el PERIODO ACADEMICO del grupo (el modelo no tiene cohorte de ingreso). Filtros opcionales: periodo, programa,
-- asignatura y docente.
-- Metricas: estudiantes activos (A), sesiones ejecutadas (vencidas con registro de asistencia), asistencias, faltas sin
-- justa causa y excusas de los estudiantes activos; % de asistencia y de inasistencia sobre (sesiones x activos);
-- estudiantes activos en RIESGO y estudiantes en PERDIDA (incluye cancelados por inasistencia).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de validacion se propagan con THROW (VAL_001 / SEC_001 / PAG_001).
-- Ambito: perfiles COORDINADOR, DECANO o ADMINISTRADOR; los grupos salen de uv_auth_grupo (fail-closed): el
-- coordinador ve su programa, el decano su facultad y el administrador su institucion.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_consolidado_asistencia_grupos_paginado]
(
    @idUsuarioEjecutor   UNIQUEIDENTIFIER,
    @idCorrelacion       UNIQUEIDENTIFIER,
    @numeroPagina        INT,
    @tamanoPagina        INT,
    @idPeriodoAcademico  UNIQUEIDENTIFIER = NULL,
    @idPrograma          UNIQUEIDENTIFIER = NULL,
    @idAsignatura        UNIQUEIDENTIFIER = NULL,
    @idDocente           UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    -- Grupos del ambito materializados una vez: evita que el optimizador combine uv_auth_grupo con el resumen de
    -- asistencia en un solo plan con una reserva de memoria desproporcionada (Msg 701 en instancias pequenas).
    DECLARE @grupos TABLE (
        id UNIQUEIDENTIFIER PRIMARY KEY, codigo INT, nombre NVARCHAR(100), idPeriodoAcademico UNIQUEIDENTIFIER,
        idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idDocente UNIQUEIDENTIFIER, idPrograma UNIQUEIDENTIFIER);
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'COORDINADOR,DECANO,ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 2: Grupos del ambito del ejecutor con los filtros
        INSERT INTO @grupos (id, codigo, nombre, idPeriodoAcademico, idAsignatura, nombreAsignatura, idDocente, idPrograma)
            SELECT  g.id, g.codigo, g.nombre, g.idPeriodoAcademico, g.idAsignatura, g.nombreAsignatura, g.idDocente,
                    gp.idPrograma
            FROM    dbo.uv_auth_grupo g
            INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
            WHERE   (@idPeriodoAcademico IS NULL OR g.idPeriodoAcademico = @idPeriodoAcademico)
               AND  (@idPrograma IS NULL OR gp.idPrograma = @idPrograma)
               AND  (@idAsignatura IS NULL OR g.idAsignatura = @idAsignatura)
               AND  (@idDocente IS NULL OR g.idDocente = @idDocente);

        -- PASO 3: Consolidado de asistencia y retorno de resultados
        WITH consolidado AS (
            -- ISNULL/COALESCE permitidos solo sobre agregaciones (REC4 #3): un grupo sin estudiantes suma 0.
            SELECT  r.idGrupo,
                    activos = SUM(IIF(r.codigoEstadoEstudiante = N'A', 1, 0)),
                    sesionesEjecutadas = MAX(r.sesionesEjecutadas),
                    asistencias = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.asistencias, 0)),
                    faltas = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.faltasSinJustaCausa, 0)),
                    excusas = SUM(IIF(r.codigoEstadoEstudiante = N'A', r.excusas, 0)),
                    riesgo = SUM(IIF(r.codigoEstadoEstudiante = N'A' AND r.codigoPermanencia = N'RIESGO', 1, 0)),
                    perdida = SUM(IIF(r.codigoPermanencia = N'PERDIDA', 1, 0))
            FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
            INNER JOIN @grupos gg ON gg.id = r.idGrupo
            GROUP BY r.idGrupo
        )
        SELECT
            idGrupo                 = g.id,
            codigoGrupo             = g.codigo,
            nombreGrupo             = g.nombre,
            idPeriodoAcademico      = g.idPeriodoAcademico,
            nombrePeriodoAcademico  = pa.nombre,
            idPrograma              = g.idPrograma,
            nombrePrograma          = p.nombrePrograma,
            idAsignatura            = g.idAsignatura,
            nombreAsignatura        = g.nombreAsignatura,
            idDocente               = g.idDocente,
            nombreDocente           = d.nombreCompleto,
            estudiantesActivos      = ISNULL(c.activos, 0),
            sesionesEjecutadas      = ISNULL(c.sesionesEjecutadas, 0),
            asistencias             = ISNULL(c.asistencias, 0),
            faltasSinJustaCausa     = ISNULL(c.faltas, 0),
            excusas                 = ISNULL(c.excusas, 0),
            porcentajeAsistencia    = CAST(IIF(ISNULL(c.sesionesEjecutadas, 0) * ISNULL(c.activos, 0) = 0, 0,
                                          100.0 * c.asistencias / (c.sesionesEjecutadas * c.activos)) AS DECIMAL(5,2)),
            porcentajeInasistencia  = CAST(IIF(ISNULL(c.sesionesEjecutadas, 0) * ISNULL(c.activos, 0) = 0, 0,
                                          100.0 * c.faltas / (c.sesionesEjecutadas * c.activos)) AS DECIMAL(5,2)),
            estudiantesRiesgo       = ISNULL(c.riesgo, 0),
            estudiantesPerdida      = ISNULL(c.perdida, 0),
            totalRegistros          = COUNT(*) OVER()
        FROM @grupos g
        LEFT JOIN consolidado c ON c.idGrupo = g.id
        LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = g.idPeriodoAcademico
        LEFT JOIN dbo.uv_programa p ON p.id = g.idPrograma
        LEFT JOIN dbo.uv_docente_identidad d ON d.id = g.idDocente
        ORDER BY pa.fechaInicio DESC, g.nombreAsignatura ASC, g.codigo ASC, g.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
