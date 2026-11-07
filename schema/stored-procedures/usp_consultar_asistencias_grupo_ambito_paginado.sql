USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_grupo_ambito_paginado (CULM-001 A.2-2; F-COO-003; CONTRACT §8.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo o fuera de
-- ambito). Asistencias del grupo de GET /api/v1/grupos/{grupoId}/asistencias (WORM #4: columnas de
-- AsistenciaConsultadaDTO). INNER JOIN desde uv_detalle_asistencia / uv_asistencia (vistas congeladas, solo lectura):
-- "ausencia = sin fila" (§E). Filtro opcional por sesion.
-- Ambito validado ANTES de leer filas (ejecutor activo): DOCENTE titular y ADMINISTRADOR de la institucion del grupo ven
-- todas; COORDINADOR activo del programa del grupo solo las de los estudiantes con EstudiantePrograma en sus programas
-- (DEC-031 §4). Grupo inexistente o fuera de ambito: THROW 51000 con DBCODE=SEC_002 (403).
-- @tamanoPagina NULL = todas las filas (A2-C3); con valor, 1..100. Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_grupo_ambito_paginado]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idSesion          UNIQUEIDENTIFIER = NULL,
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL, 2147483647, IIF(@tamanoPagina < 1, 1, IIF(@tamanoPagina > 100, 100, @tamanoPagina)));
    DECLARE @offset INT = IIF(@tamanoPagina IS NULL, 0, (@pagina - 1) * @tamano);
    DECLARE @ejecutorActivo BIT = 0;
    DECLARE @verTodos BIT = 0;
    DECLARE @esCoordinador BIT = 0;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- PASO 1: correlacion obligatoria
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: ejecutor obligatorio (VAL_001)
    IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    -- PASO 3: ambito del grupo, antes de leer filas
    IF @estadoResultado = 1
    BEGIN
        SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

        SET @verTodos = IIF(@ejecutorActivo = 1 AND (
                EXISTS (SELECT 1 FROM dbo.Grupo g INNER JOIN dbo.Docente d ON d.id = g.docente
                        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioEjecutor)
             OR EXISTS (SELECT 1 FROM dbo.Grupo g
                        INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                        INNER JOIN dbo.Programa p ON p.id = pe.programa
                        INNER JOIN dbo.Facultad f ON f.id = p.facultad
                        INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                        WHERE g.id = @idGrupo AND ad.usuario = @idUsuarioEjecutor)), 1, 0);

        SET @esCoordinador = IIF(@ejecutorActivo = 1 AND EXISTS (
                SELECT 1 FROM dbo.Grupo g
                INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                INNER JOIN dbo.Programa p ON p.id = pe.programa
                INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                WHERE g.id = @idGrupo AND c.usuario = @idUsuarioEjecutor AND c.estado = 1), 1, 0);

        IF @verTodos = 0 AND @esCoordinador = 0
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: asistencias registradas del grupo (el coordinador, solo las de los estudiantes de sus programas)
    SELECT
        asistencia     = da.id,
        estudiante     = eg.idEstudiante,
        grupo          = eg.idGrupo,
        sesion         = a.idSesion,
        presente       = da.asistio,
        estado         = da.codigoRazonCausa,
        observacion    = CAST(N'' AS NVARCHAR(500)),
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_detalle_asistencia da
    INNER JOIN dbo.uv_asistencia a ON a.id = da.idAsistencia
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = a.idEstudianteGrupo
    WHERE eg.idGrupo = @idGrupo
      AND (@idSesion IS NULL OR a.idSesion = @idSesion)
      AND (@verTodos = 1
           OR EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                      INNER JOIN dbo.Programa p ON p.id = ep.programa
                      INNER JOIN dbo.Coordinador c ON c.id = p.coordinador
                      WHERE ep.estudiante = eg.idEstudiante AND c.usuario = @idUsuarioEjecutor AND c.estado = 1))
    ORDER BY a.idSesion ASC, eg.idEstudiante ASC, da.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
