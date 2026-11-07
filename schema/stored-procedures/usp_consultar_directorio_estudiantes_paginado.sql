USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_directorio_estudiantes_paginado (CULM-001 A.2-1; F-COO-001, F-COO-002, F-DOC-013; CONTRACT §8.2.1)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Directorio de estudiantes de GET /api/v1/estudiantes y /{id} con el AMBITO DENTRO DEL SP (union si el ejecutor
-- tiene varios roles; el ejecutor debe ser un usuario activo):
--   * ADMINISTRADOR: solo su institucion (DEC-031 §3): estudiantes con EstudiantePrograma en un programa de su
--     institucion o con EstudianteGrupo en un grupo de su institucion. Un estudiante sin ningun vinculo no tiene
--     institucion resoluble y no aparece (fail-closed).
--   * COORDINADOR activo: estudiantes con EstudiantePrograma en sus programas.
--   * DOCENTE: estudiantes con alguna matricula (en cualquier estado: padron historico) en sus grupos.
--   * Cualquier otro rol: ambito vacio.
-- Modo listado (@idEstudiante NULL): 12 columnas, orden primerApellido, primerNombre, numeroIdentificacion, id;
-- paginacion protegida (pagina >= 1, tamano 1..100). Los filtros solo restringen dentro del ambito: igualdad para tipo
-- y numero de documento, LIKE con escape de %, _ y \ sobre UPPER(nombreCompleto) y LOWER(correo), y EXISTS sobre
-- uv_estudiante para los academicos.
-- Modo detalle (@idEstudiante no nulo): las 11 columnas del estudiante mas 12 de contexto academico (institucion,
-- facultad, programa, plan, asignatura y grupo, con id y nombre) LIMITADAS AL AMBITO del ejecutor: una fila por
-- contexto visible o una sola con contexto NULL. Fuera de ambito: 0 filas (el backend responde 404). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_directorio_estudiantes_paginado]
(
    @idUsuarioEjecutor    UNIQUEIDENTIFIER,
    @idCorrelacion        UNIQUEIDENTIFIER,
    @idEstudiante         UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion INT              = NULL,
    @nombre               NVARCHAR(100)    = NULL,
    @correo               NVARCHAR(100)    = NULL,
    @idInstitucion        UNIQUEIDENTIFIER = NULL,
    @idFacultad           UNIQUEIDENTIFIER = NULL,
    @idPrograma           UNIQUEIDENTIFIER = NULL,
    @idGrupo              UNIQUEIDENTIFIER = NULL,
    @activo               BIT              = NULL,
    @numeroPagina         INT              = 1,
    @tamanoPagina         INT              = 20
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 20, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @textoNombre NVARCHAR(100) = NULLIF(TRIM(@nombre), N'');
    DECLARE @textoCorreo NVARCHAR(100) = NULLIF(TRIM(@correo), N'');
    DECLARE @patronNombre NVARCHAR(320) = IIF(@textoNombre IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(UPPER(@textoNombre), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @patronCorreo NVARCHAR(320) = IIF(@textoCorreo IS NULL, NULL,
        CONCAT(N'%', REPLACE(REPLACE(REPLACE(LOWER(@textoCorreo), N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'%'));
    DECLARE @filtroAcademico BIT = IIF(@idInstitucion IS NULL AND @idFacultad IS NULL AND @idPrograma IS NULL AND @idGrupo IS NULL, 0, 1);
    DECLARE @ejecutorActivo BIT = 0;
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

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SET @ejecutorActivo = IIF(EXISTS (SELECT 1 FROM dbo.Usuario u WHERE u.id = @idUsuarioEjecutor AND u.estado = 1), 1, 0);

    -- PASO 3: modo listado
    IF @idEstudiante IS NULL
    BEGIN
        ;WITH ambito AS (
            -- ADMINISTRADOR: matriculas en grupos de su institucion
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Asignatura a ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- ADMINISTRADOR: inscripciones en programas de su institucion
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
            UNION
            -- COORDINADOR activo: inscripciones en sus programas
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1
            UNION
            -- DOCENTE: matriculas (cualquier estado) en sus grupos
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            totalRegistros       = COUNT(*) OVER()
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        WHERE e.id IN (SELECT amb.idEstudiante FROM ambito amb)
          AND (@idTipoIdentificacion IS NULL OR u.idTipoIdentificacion = @idTipoIdentificacion)
          AND (@numeroIdentificacion IS NULL OR u.numeroIdentificacion = @numeroIdentificacion)
          AND (@patronNombre IS NULL OR UPPER(u.nombreCompleto) LIKE @patronNombre ESCAPE N'\')
          AND (@patronCorreo IS NULL OR LOWER(u.correo) LIKE @patronCorreo ESCAPE N'\')
          AND (@activo IS NULL OR u.estaActivoUsuario = @activo)
          AND (@filtroAcademico = 0 OR EXISTS (
                SELECT 1 FROM dbo.uv_estudiante x
                WHERE x.id = e.id
                  AND (@idInstitucion IS NULL OR x.idInstitucion = @idInstitucion)
                  AND (@idFacultad IS NULL OR x.idFacultad = @idFacultad)
                  AND (@idPrograma IS NULL OR x.idPrograma = @idPrograma)
                  AND (@idGrupo IS NULL OR x.idGrupo = @idGrupo)))
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, e.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;
    END
    ELSE
    -- PASO 4: modo detalle (contextos limitados al ambito del ejecutor)
    BEGIN
        ;WITH ambito AS (
            SELECT eg.estudiante AS idEstudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.PlanEstudio pe ON pe.programa = p.id
            INNER JOIN dbo.SemestrePlanEstudio spe ON spe.planEstudio = pe.id
            INNER JOIN dbo.Asignatura a ON a.semestrePlanEstudio = spe.id
            INNER JOIN dbo.Grupo g ON g.asignatura = a.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Administrador ad
            INNER JOIN dbo.Facultad f ON f.institucion = ad.institucion
            INNER JOIN dbo.Programa p ON p.facultad = f.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE ad.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT ep.estudiante
            FROM dbo.Coordinador c
            INNER JOIN dbo.Programa p ON p.coordinador = c.id
            INNER JOIN dbo.EstudiantePrograma ep ON ep.programa = p.id
            WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND @ejecutorActivo = 1 AND ep.estudiante = @idEstudiante
            UNION
            SELECT eg.estudiante
            FROM dbo.Docente d
            INNER JOIN dbo.Grupo g ON g.docente = d.id
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = g.id
            WHERE d.usuario = @idUsuarioEjecutor AND @ejecutorActivo = 1 AND eg.estudiante = @idEstudiante
        ),
        contexto AS (
            SELECT DISTINCT
                x.idInstitucion, x.nombreInstitucion, x.idFacultad, x.nombreFacultad, x.idPrograma, x.nombrePrograma,
                x.idPlanEstudio, inpPlanEstudio = CAST(x.inpPlanEstudio AS NVARCHAR(20)), x.idAsignatura, x.nombreAsignatura,
                x.idGrupo, x.nombreGrupo
            FROM dbo.uv_estudiante x
            WHERE x.id = @idEstudiante
              AND @ejecutorActivo = 1
              AND (EXISTS (SELECT 1 FROM dbo.Administrador ad WHERE ad.usuario = @idUsuarioEjecutor AND ad.institucion = x.idInstitucion)
                   OR EXISTS (SELECT 1 FROM dbo.Coordinador c INNER JOIN dbo.Programa p ON p.coordinador = c.id
                              WHERE c.usuario = @idUsuarioEjecutor AND c.estado = 1 AND p.id = x.idPrograma)
                   OR EXISTS (SELECT 1 FROM dbo.Docente d INNER JOIN dbo.Grupo g ON g.docente = d.id
                              WHERE d.usuario = @idUsuarioEjecutor AND g.id = x.idGrupo))
        )
        SELECT
            id                   = e.id,
            idUsuario            = u.id,
            tipoIdentificacionId = u.idTipoIdentificacion,
            numeroIdentificacion = u.numeroIdentificacion,
            primerApellido       = u.primerApellido,
            segundoApellido      = u.segundoApellido,
            primerNombre         = u.primerNombre,
            segundoNombre        = u.segundoNombre,
            nombreCompleto       = CAST(u.nombreCompleto AS NVARCHAR(400)),
            correo               = u.correo,
            estaActivoUsuario    = u.estaActivoUsuario,
            idInstitucion        = c.idInstitucion,
            nombreInstitucion    = c.nombreInstitucion,
            idFacultad           = c.idFacultad,
            nombreFacultad       = c.nombreFacultad,
            idPrograma           = c.idPrograma,
            nombrePrograma       = c.nombrePrograma,
            idPlanEstudio        = c.idPlanEstudio,
            inpPlanEstudio       = c.inpPlanEstudio,
            idAsignatura         = c.idAsignatura,
            nombreAsignatura     = c.nombreAsignatura,
            idGrupo              = c.idGrupo,
            nombreGrupo          = c.nombreGrupo
        FROM dbo.uv_estudiante_identidad e
        INNER JOIN dbo.uv_usuario u ON u.id = e.idUsuario
        LEFT JOIN contexto c ON 1 = 1
        WHERE e.id = @idEstudiante
          AND e.id IN (SELECT amb.idEstudiante FROM ambito amb)
        ORDER BY c.nombreInstitucion, c.nombreFacultad, c.nombrePrograma, c.nombreAsignatura, c.nombreGrupo, c.idGrupo;
    END
END;
GO
