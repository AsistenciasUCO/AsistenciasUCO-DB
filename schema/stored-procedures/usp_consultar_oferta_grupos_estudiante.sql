USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_oferta_grupos_estudiante (HU008)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Oferta de grupos para el ESTUDIANTE ejecutor en periodos VIGENTES o PROXIMOS (fecha local TIEMPO.ZONA_HORARIA_SQLSERVER).
-- Regla de John (2026-10-27): las asignaturas propias del programa son las del componente ESP (especificas); BAS
-- (basicas) e INS (institucionales) son TRANSVERSALES. La oferta incluye:
--   - los grupos de asignaturas ESP de los programas en que esta inscrito (EstudiantePrograma);
--   - si OFERTA.INCLUIR_TRANSVERSALES = 1 (por defecto), los grupos de asignaturas BAS/INS de cualquier programa de
--     la(s) institucion(es) de sus programas. Con 0 no se muestran transversales (solo se ingresa con el enlace del
--     docente, HU053).
-- Cada fila trae docente, horario, capacidad y cupos (capacidad - matriculas activas, minimo 0), el componente de la
-- asignatura y la relacion del estudiante con el grupo: matriculado (matricula activa A) y solicitud de ingreso abierta
-- (P o E, HU053-HU055).
-- Un ejecutor que no es estudiante obtiene 0 filas. Busqueda por asignatura (nombre o codigo) o nombre del grupo.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_oferta_grupos_estudiante]
(
    @busqueda           NVARCHAR(50) = NULL,
    @numeroPagina       INT          = 1,
    @tamanoPagina       INT          = 10,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @texto NVARCHAR(50) = NULLIF(TRIM(@busqueda), '');
    DECLARE @patron NVARCHAR(120) = IIF(@texto IS NULL, NULL,
        CONCAT('%', REPLACE(REPLACE(REPLACE(@texto, '\', '\\'), '%', '\%'), '_', '\_'), '%'));
    DECLARE @zonaHoraria NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);
    DECLARE @incluirTransversales BIT = IIF(TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('OFERTA', 'INCLUIR_TRANSVERSALES')), '') AS INT) = 0, 0, 1);

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    DECLARE @idEstudiante UNIQUEIDENTIFIER = (SELECT TOP 1 e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioDefecto);

    ;WITH oferta AS (
        SELECT
            g.id, g.codigo, g.nombre, g.cantidadEstudiantes AS capacidad,
            asg.id AS idAsignatura, asg.codigo AS codigoAsignatura, asg.nombre AS nombreAsignatura,
            g.docente, pa.id AS idPeriodo, pa.nombre AS nombrePeriodo, pa.fechaInicio, pa.fechaFin, comp.codigo AS codigoComponente,
            activos = (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                       WHERE eg.grupo = g.id AND ee.codigo = 'A')
        FROM dbo.Grupo g
        INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
        INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura
        INNER JOIN dbo.Componente comp ON comp.id = asg.componente
        INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = asg.semestrePlanEstudio
        INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
        INNER JOIN dbo.Programa pr ON pr.id = pe.programa
        INNER JOIN dbo.Facultad fa ON fa.id = pr.facultad
        WHERE @idEstudiante IS NOT NULL
          AND pa.fechaFin >= @hoyLocal
          AND (
                -- Propias: especificas de sus programas.
                (comp.codigo = 'ESP'
                 AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = @idEstudiante AND ep.programa = pe.programa))
                -- Transversales: basicas e institucionales de cualquier programa de su institucion (configurable).
                OR (@incluirTransversales = 1 AND comp.codigo IN ('BAS', 'INS')
                    AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                                INNER JOIN dbo.Programa pp ON pp.id = ep.programa
                                INNER JOIN dbo.Facultad fp ON fp.id = pp.facultad
                                WHERE ep.estudiante = @idEstudiante AND fp.institucion = fa.institucion))
              )
          AND (
                @patron IS NULL
                OR asg.nombre LIKE @patron ESCAPE '\'
                OR asg.codigo LIKE @patron ESCAPE '\'
                OR g.nombre LIKE @patron ESCAPE '\'
              )
    )
    SELECT
        idGrupo                = o.id,
        codigoGrupo            = o.codigo,
        nombreGrupo            = o.nombre,
        idAsignatura           = o.idAsignatura,
        codigoAsignatura       = o.codigoAsignatura,
        nombreAsignatura       = o.nombreAsignatura,
        nombreDocente          = CAST(CONCAT_WS(N' ',
                                     NULLIF(TRIM(ud.primerNombre), N''),
                                     NULLIF(TRIM(ud.primerApellido), N''),
                                     NULLIF(TRIM(ud.segundoApellido), N'')) AS NVARCHAR(400)),
        idPeriodoAcademico     = o.idPeriodo,
        nombrePeriodoAcademico = o.nombrePeriodo,
        fechaInicioPeriodo     = o.fechaInicio,
        fechaFinPeriodo        = o.fechaFin,
        estadoPeriodo          = CAST(IIF(@hoyLocal < o.fechaInicio, 'PROXIMO', 'VIGENTE') AS NVARCHAR(10)),
        horario                = CAST((
                                     SELECT STRING_AGG(CONCAT(d.nombre, N' ', CONVERT(CHAR(5), h.horaInicio, 108), N'-', CONVERT(CHAR(5), h.horaFin, 108)), N'; ')
                                            WITHIN GROUP (ORDER BY CHARINDEX(d.codigo, N'LUMAMIJUVISADO'), h.horaInicio)
                                     FROM dbo.Horario h INNER JOIN dbo.Dia d ON d.id = h.dia
                                     WHERE h.grupo = o.id) AS NVARCHAR(400)),
        capacidadMaxima        = o.capacidad,
        estudiantesActivos     = o.activos,
        cuposDisponibles       = IIF(o.capacidad - o.activos < 0, 0, o.capacidad - o.activos),
        matriculado            = CAST(IIF(EXISTS (
                                     SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                                     WHERE eg.grupo = o.id AND eg.estudiante = @idEstudiante AND ee.codigo = 'A'), 1, 0) AS BIT),
        idSolicitudAbierta     = sol.id,
        codigoEstadoSolicitud  = CAST(sol.codigo AS CHAR(1)),
        codigoComponente       = CAST(o.codigoComponente AS NVARCHAR(3)),
        totalRegistros         = COUNT(*) OVER()
    FROM oferta o
    INNER JOIN dbo.Docente doc ON doc.id = o.docente
    INNER JOIN dbo.Usuario ud  ON ud.id = doc.usuario
    OUTER APPLY (
        SELECT TOP 1 s.id, est.codigo
        FROM dbo.SolicitudIngresoGrupo s
        INNER JOIN dbo.Estado est ON est.id = s.estado
        WHERE s.grupo = o.id AND s.estudiante = @idEstudiante AND est.codigo IN ('P', 'E')
    ) sol
    ORDER BY o.nombreAsignatura ASC, o.fechaInicio ASC, o.codigo ASC, o.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
