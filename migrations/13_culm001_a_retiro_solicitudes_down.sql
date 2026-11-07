USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_culm001_a_retiro_solicitudes_down.sql: rollback de 13_culm001_a_retiro_solicitudes_up.sql (CONTRACT §2.5).
-- Restaura los objetos tal como estaban en develop (65a4998); los cuerpos de los SP salen de git show 65a4998:<ruta>.
-- Tolera lo que paso despues del up (depuracion, reintentos, reservas vencidas) y solo se detiene si se perderian
-- solicitudes (THROW 53310, unico THROW). Idempotente: R-5, R-7 y R-8 se saltan si las tablas de archivo ya no existen.
-- Si se aplico 14_culm001_a_correcciones_fase1_up.sql, aplicar antes su down. El backend que acompana es el de develop.
-- ============================================================================

-- R-1: SP de develop (van antes que la tabla: la resolucion diferida de nombres lo permite).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @correo                  NVARCHAR(100),
    @password                NVARCHAR(500),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteResultado    UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor (obligatorio)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'DOCENTE,COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.8: Validar existencia del grupo antes de sincronizar identidad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 1.9: Validar cupo disponible antes de sincronizar identidad.
        -- usp_validar_grupo_exista_por_id_interno ya no valida cupo (sesiones se pueden programar en grupos llenos);
        -- la matrícula debe rechazarse aquí para no dejar Usuario/Estudiante parciales.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Sincronización de identidad (Usuario y Estudiante) e inscripción en grupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @idTipoIdTarget UNIQUEIDENTIFIER = @idTipoIdIdentificacion;
            IF @idTipoIdTarget IS NULL
            BEGIN
                SELECT TOP 1 @idTipoIdTarget = id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC';
                IF @idTipoIdTarget IS NULL SELECT TOP 1 @idTipoIdTarget = id FROM dbo.TipoIdentificacion;
            END

            DECLARE @idUsuarioTarget UNIQUEIDENTIFIER;
            SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));

            -- IDENT-001: en un alta nueva (sin usuario con ese correo) el correo debe ser institucional. El dominio es el
            -- parametro REGISTRO/DOMINIO_CORREO_ESTUDIANTE; un usuario existente no se revalida (D5).
            IF @estadoResultado = 1 AND @idUsuarioTarget IS NULL
            BEGIN
                DECLARE @dominioInstitucional NVARCHAR(255) = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
                IF dbo.ufn_correo_cumple_dominio_institucional(@correo, @dominioInstitucional) = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'VCE_001',
                        @p_param1 = @dominioInstitucional,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            IF @estadoResultado = 1 AND @idUsuarioTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdTarget,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioTarget = id FROM dbo.Usuario WHERE correo = LOWER(TRIM(@correo));
            END

            IF @estadoResultado = 1 AND @idUsuarioTarget IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = id FROM dbo.Estudiante WHERE usuario = @idUsuarioTarget;

                IF @idEstudianteResultado IS NULL
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idEstudianteResultado = id FROM dbo.Estudiante WHERE usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteResultado IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteResultado,
                    @idGrupo = @idGrupoDefecto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_estudiante_en_grupo_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(10) = 'A',
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstadoActivo       UNIQUEIDENTIFIER;

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Obtener identificador del Estado para EstudianteGrupo
        IF @estadoResultado = 1
        BEGIN
            DECLARE @codigoEstadoDefecto NVARCHAR(10) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstado, 'GENERAL', 'CADENA_VACIA')));
            IF @codigoEstadoDefecto = '' SET @codigoEstadoDefecto = 'A';

            SELECT @idEstadoActivo = id 
            FROM dbo.uv_estado_estudiante_grupo 
            WHERE codigo = @codigoEstadoDefecto;

            IF @idEstadoActivo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Estado Estudiante Grupo (A)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Validaciones de reglas de negocio en sub-procedimientos
        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_cruce_horario_estudiante_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 
        BEGIN
            EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Inserción final del estudiante en el grupo en dbo.EstudianteGrupo
        IF @estadoResultado = 1 
        BEGIN
            DECLARE @idProgramaGrupo UNIQUEIDENTIFIER;
            SELECT TOP 1 @idProgramaGrupo = pe.programa 
            FROM dbo.Grupo g 
            INNER JOIN dbo.Asignatura a ON g.asignatura = a.id
            -- HU008 (regla de John 2026-10-27): solo una asignatura ESPECIFICA (componente ESP) inscribe al estudiante
            -- en el programa; las transversales (BAS/INS) no crean fila en EstudiantePrograma.
            INNER JOIN dbo.Componente comp ON comp.id = a.componente AND comp.codigo = 'ESP'
            INNER JOIN dbo.SemestrePlanEstudio sp ON a.semestrePlanEstudio = sp.id
            INNER JOIN dbo.PlanEstudio pe ON sp.planEstudio = pe.id
            WHERE g.id = @idGrupoDefecto;

            IF @idProgramaGrupo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma WHERE estudiante = @idEstudianteDefecto AND programa = @idProgramaGrupo)
            BEGIN
                INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                VALUES (NEWID(), @idEstudianteDefecto, @idProgramaGrupo);
            END

            INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
            VALUES (NEWID(), @idEstadoActivo, @idEstudianteDefecto, @idGrupoDefecto);

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Estudiante en Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 1;
        END

    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
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

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
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
    DECLARE @idEstudiante UNIQUEIDENTIFIER;

BEGIN
    SET NOCOUNT ON;

-- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    -- PASO 3: Validacion de entrada
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SET @idEstudiante = (SELECT TOP 1 e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioDefecto);

    -- PASO 4: Consulta y retorno de resultados
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
    -- PASO 5: Consulta y retorno de resultados
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

-- R-2: SP de reactivacion y parametros MATRICULA/* de A.1.
USE [gestionasistenciadb];
GO
IF OBJECT_ID(N'dbo.usp_internal_reactivar_matricula_retirada', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_internal_reactivar_matricula_retirada];
GO
DELETE FROM dbo.CatalogoParametro WHERE grupo = 'MATRICULA' AND clave IN ('ESTADO_RETIRADA', 'ESTADO_INSCRITA');
GO

-- R-3: estado E (en espera) con su id fijo. X sigue existiendo (no se borro).
MERGE INTO [dbo].[Estado] AS Target
USING (VALUES ('C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E', 'en espera', 'E')) AS Source (id, nombre, codigo)
ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
WHEN NOT MATCHED THEN
    INSERT (id, nombre, codigo) VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);
GO

-- R-4: tabla, PK, default e indices (contenido de develop de tables/SolicitudIngresoGrupo.sql).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: solicitud de un estudiante para ingresar a un grupo. Tabla NUEVA aprobada por John (2026-10-27,
-- skill consistencia-tablas): no modifica ninguna tabla existente. Estados en dbo.Estado: P pendiente, A aceptada
-- (se crea la matricula), R rechazada (motivo obligatorio), E en espera (sin cupo al aceptar) y X retirada por el
-- estudiante. fechaSolicitudUtc define el orden de llegada que se muestra en la lista de espera.
IF OBJECT_ID('dbo.[SolicitudIngresoGrupo]', 'U') IS NULL
BEGIN
CREATE TABLE [dbo].[SolicitudIngresoGrupo] (
    [id] uniqueidentifier NOT NULL,
    [estudiante] uniqueidentifier NOT NULL,
    [grupo] uniqueidentifier NOT NULL,
    [estado] uniqueidentifier NOT NULL,
    [fechaSolicitudUtc] datetime2(7) NOT NULL CONSTRAINT [DF_SolicitudIngresoGrupo_fechaSolicitudUtc] DEFAULT (SYSUTCDATETIME()),
    [fechaResolucionUtc] datetime2(7) NULL,
    [motivoRechazo] nvarchar(500) NULL,
    [docenteResolutor] uniqueidentifier NULL,
    [estudianteGrupo] uniqueidentifier NULL
);

ALTER TABLE [dbo].[SolicitudIngresoGrupo] ADD CONSTRAINT [PK_SolicitudIngresoGrupo] PRIMARY KEY CLUSTERED ([id]);
END
GO

-- Una sola solicitud ABIERTA (pendiente B4B4D37E... o en espera C5D1E2F3...) por estudiante y grupo.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_SolicitudIngresoGrupo_Abierta' AND object_id = OBJECT_ID('dbo.SolicitudIngresoGrupo'))
    CREATE UNIQUE NONCLUSTERED INDEX [UX_SolicitudIngresoGrupo_Abierta]
        ON [dbo].[SolicitudIngresoGrupo] ([estudiante], [grupo])
        WHERE [estado] IN ('B4B4D37E-6A8F-4E1D-AF32-0B2C60E2E977', 'C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E');
GO

-- Bandeja del docente por grupo y estado, en orden de llegada.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SolicitudIngresoGrupo_Grupo_Estado_Fecha' AND object_id = OBJECT_ID('dbo.SolicitudIngresoGrupo'))
    CREATE NONCLUSTERED INDEX [IX_SolicitudIngresoGrupo_Grupo_Estado_Fecha]
        ON [dbo].[SolicitudIngresoGrupo] ([grupo], [estado], [fechaSolicitudUtc]);
GO

-- R-5: solicitudes desde el archivo y las 5 FK (WITH NOCHECK si falta una referencia; sin perder datos).
USE [gestionasistenciadb];
GO
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.zz_archivo_SolicitudIngresoGrupo', N'U') IS NOT NULL
BEGIN
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql N'
            INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc, fechaResolucionUtc,
                motivoRechazo, docenteResolutor, estudianteGrupo)
            SELECT a.id, a.estudiante, a.grupo, e.id, a.fechaSolicitudUtc, a.fechaResolucionUtc, a.motivoRechazo,
                   a.docenteResolutor, a.estudianteGrupo
            FROM dbo.zz_archivo_SolicitudIngresoGrupo a
            INNER JOIN dbo.Estado e ON e.codigo = a.codigoEstado
            WHERE NOT EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s WHERE s.id = a.id);';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
    SET XACT_ABORT OFF;
END
GO
DECLARE @fks TABLE (n INT IDENTITY, nombre SYSNAME, columna SYSNAME, referencia SYSNAME);
INSERT @fks (nombre, columna, referencia) VALUES
    (N'FK_SolicitudIngresoGrupo_Estudiante', N'estudiante', N'Estudiante'),
    (N'FK_SolicitudIngresoGrupo_Grupo', N'grupo', N'Grupo'),
    (N'FK_SolicitudIngresoGrupo_Estado', N'estado', N'Estado'),
    (N'FK_SolicitudIngresoGrupo_Docente', N'docenteResolutor', N'Docente'),
    (N'FK_SolicitudIngresoGrupo_EstudianteGrupo', N'estudianteGrupo', N'EstudianteGrupo');
DECLARE @i INT = 1, @nombre SYSNAME, @columna SYSNAME, @referencia SYSNAME, @sql NVARCHAR(MAX);
WHILE @i <= 5
BEGIN
    SELECT @nombre = nombre, @columna = columna, @referencia = referencia FROM @fks WHERE n = @i;
    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = @nombre)
    BEGIN
        SET @sql = CONCAT(N'ALTER TABLE [dbo].[SolicitudIngresoGrupo] ADD CONSTRAINT ', QUOTENAME(@nombre), N' FOREIGN KEY (',
                          QUOTENAME(@columna), N') REFERENCES [dbo].', QUOTENAME(@referencia), N' ([id]);');
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
            SET @sql = REPLACE(@sql, N'ADD CONSTRAINT', N'WITH NOCHECK ADD CONSTRAINT');
            SET @sql = REPLACE(@sql, N'ALTER TABLE [dbo].[SolicitudIngresoGrupo] WITH NOCHECK ADD', N'ALTER TABLE [dbo].[SolicitudIngresoGrupo] WITH NOCHECK ADD');
            EXEC sys.sp_executesql @sql;
            PRINT CONCAT('CULM001_A_DOWN13 AVISO: ', @nombre, ' creada WITH NOCHECK (falta una referencia).');
        END CATCH
    END
    SET @i += 1;
END
GO

-- R-6: los 6 SP de develop y sus GRANT.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_solicitud_ingreso_grupo  (HU053)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE autenticado (Estudiante.usuario = ejecutor) solicita ingresar a un grupo; queda PENDIENTE (P).
-- Codigos: GEN_002 ejecutor nulo, SIG_001 no es estudiante, SIG_002 grupo inexistente, SIG_003 periodo terminado,
-- SIG_004 ya matriculado activo, SIG_005 ya tiene una solicitud abierta (P/E), SIG_006 exito.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @zonaHoraria              NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal                 DATE;
    DECLARE @idEstudiante             UNIQUEIDENTIFIER;
    DECLARE @grupoEncontrado          UNIQUEIDENTIFIER;
    DECLARE @fechaFinPeriodo          DATE;
    DECLARE @estadoPendiente          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
    DECLARE @estadoEspera             UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'E');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @hoyLocal = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar la accion y el motivo (codigo de rechazo)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_registrar_solicitud_ingreso;
                SET @savepointCreado = 1;
            END

            SELECT @idEstudiante = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioEjecutorDefecto;
            SELECT @grupoEncontrado = g.id, @fechaFinPeriodo = pa.fechaFin
            FROM dbo.Grupo g
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto;

            SET @codigoRechazo =
                CASE
                    WHEN @idEstudiante IS NULL THEN 'SIG_001'
                    WHEN @grupoEncontrado IS NULL THEN 'SIG_002'
                    WHEN @fechaFinPeriodo < @hoyLocal THEN 'SIG_003'
                    WHEN EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                                 WHERE eg.grupo = @idGrupoDefecto AND eg.estudiante = @idEstudiante AND est.codigo = 'A') THEN 'SIG_004'
                    WHEN EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s WITH (UPDLOCK, HOLDLOCK)
                                 WHERE s.grupo = @idGrupoDefecto AND s.estudiante = @idEstudiante
                                   AND s.estado IN (@estadoPendiente, @estadoEspera)) THEN 'SIG_005'
                END;

            IF @codigoRechazo IS NULL
            BEGIN
                INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc)
                VALUES (@idSolicitud, @idEstudiante, @idGrupoDefecto, @estadoPendiente, SYSUTCDATETIME());

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SIG_006',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END

        -- PASO 4: Traducir el codigo de rechazo a su mensaje de catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_registrar_solicitud_ingreso;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_resolver_solicitud_ingreso_grupo  (HU053 / HU054 / HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico + 1 columna extra
-- (codigoEstadoResultante CHAR(1): estado final de la solicitud o NULL si no se resolvio).
-- Solo el DOCENTE TITULAR (Grupo.docente -> Docente.usuario = ejecutor) resuelve solicitudes abiertas (P o E):
--   - RECHAZAR: motivo obligatorio (1..500) => R (SIG_014).
--   - ACEPTAR: bajo UPDLOCK, HOLDLOCK de la fila del grupo se recalcula el cupo (capacidad - matriculas activas):
--       con cupo  => matricula con usp_registrar_estudiante_en_grupo_interno y la solicitud pasa a A (SIG_011);
--                    si el estudiante fue retirado del grupo (matricula 'I', HU051), se REACTIVA esa matricula
--                    (I -> A) en lugar de crear otra (INT-HU-01, opcion a de John 2026-10-28);
--       sin cupo  => P pasa a E, lista de espera (SIG_012); una E que sigue sin cupo => SIG_013.
--     El docente puede aceptar a CUALQUIER solicitud en espera (decision de John); el orden de llegada solo se muestra.
-- Codigos: GEN_002, SIG_009 accion invalida, SIG_010 motivo, SIG_007 inexistente o no titular, SIG_008 ya resuelta,
-- SIG_003 periodo terminado, SIG_004 ya matriculado; los rechazos de la matricula interna (p. ej. cruce de horario)
-- se propagan tal cual.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @accion                  NVARCHAR(20),
    @motivo                  NVARCHAR(MAX) = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionNormalizada        NVARCHAR(20) = UPPER(TRIM(@accion));
    DECLARE @motivoNormalizado        NVARCHAR(MAX) = NULLIF(TRIM(@motivo), N'');
    DECLARE @zonaHoraria              NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal                 DATE;
    DECLARE @idGrupo                  UNIQUEIDENTIFIER;
    DECLARE @idEstudiante             UNIQUEIDENTIFIER;
    DECLARE @idDocente                UNIQUEIDENTIFIER;
    DECLARE @estadoActual             UNIQUEIDENTIFIER;
    DECLARE @fechaFinPeriodo          DATE;
    DECLARE @capacidad                INT;
    DECLARE @activos                  INT;
    DECLARE @idEstudianteGrupo        UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoResultante   CHAR(1);
    DECLARE @codigoExito              VARCHAR(100);
    DECLARE @estadoPendiente          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
    DECLARE @estadoAceptada           UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'A');
    DECLARE @estadoRechazada          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'R');
    DECLARE @estadoEspera             UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'E');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @hoyLocal = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar la accion y el motivo (codigo de rechazo)
        IF @estadoResultado = 1
        BEGIN
            SET @codigoRechazo =
                CASE
                    WHEN @accionNormalizada IS NULL OR @accionNormalizada NOT IN (N'ACEPTAR', N'RECHAZAR') THEN 'SIG_009'
                    WHEN @accionNormalizada = N'RECHAZAR' AND (@motivoNormalizado IS NULL OR LEN(@motivoNormalizado) > 500) THEN 'SIG_010'
                END;
        END

        -- PASO 4: Validar la accion y el motivo (codigo de rechazo)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_resolver_solicitud_ingreso;
                SET @savepointCreado = 1;
            END

            -- Titularidad en tablas base; una solicitud de otro grupo es indistinguible de una inexistente (SIG_007).
            SELECT @idGrupo = s.grupo, @idEstudiante = s.estudiante, @estadoActual = s.estado, @idDocente = d.id
            FROM dbo.SolicitudIngresoGrupo s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Grupo g ON g.id = s.grupo
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE s.id = @idSolicitudDefecto AND d.usuario = @idUsuarioEjecutorDefecto;

            -- Bloqueo de la fila del grupo: serializa las aceptaciones concurrentes del mismo grupo (sin sobrecupo).
            IF @idGrupo IS NOT NULL
            BEGIN
                SELECT @capacidad = g.cantidadEstudiantes, @fechaFinPeriodo = pa.fechaFin
                FROM dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                WHERE g.id = @idGrupo;
            END

            SET @codigoRechazo =
                CASE
                    WHEN @idGrupo IS NULL THEN 'SIG_007'
                    WHEN @estadoActual NOT IN (@estadoPendiente, @estadoEspera) THEN 'SIG_008'
                    WHEN @accionNormalizada = N'ACEPTAR' AND @fechaFinPeriodo < @hoyLocal THEN 'SIG_003'
                    WHEN @accionNormalizada = N'ACEPTAR' AND EXISTS (
                        SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                        WHERE eg.grupo = @idGrupo AND eg.estudiante = @idEstudiante AND est.codigo = 'A') THEN 'SIG_004'
                END;

            IF @codigoRechazo IS NULL AND @accionNormalizada = N'RECHAZAR'
            BEGIN
                UPDATE dbo.SolicitudIngresoGrupo
                SET estado = @estadoRechazada, motivoRechazo = @motivoNormalizado,
                    docenteResolutor = @idDocente, fechaResolucionUtc = SYSUTCDATETIME()
                WHERE id = @idSolicitudDefecto;
                SET @codigoEstadoResultante = 'R';
                SET @codigoExito = 'SIG_014';
            END

            IF @codigoRechazo IS NULL AND @accionNormalizada = N'ACEPTAR'
            BEGIN
                SELECT @activos = COUNT(*)
                FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                WHERE eg.grupo = @idGrupo AND est.codigo = 'A';

                IF @capacidad - @activos <= 0
                BEGIN
                    IF @estadoActual = @estadoEspera
                    BEGIN
                        SET @codigoRechazo = 'SIG_013';
                    END
                    ELSE
                    BEGIN
                        UPDATE dbo.SolicitudIngresoGrupo SET estado = @estadoEspera WHERE id = @idSolicitudDefecto;
                        SET @codigoEstadoResultante = 'E';
                        SET @codigoExito = 'SIG_012';
                    END
                END
                ELSE IF EXISTS (
                    SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                    WHERE eg.grupo = @idGrupo AND eg.estudiante = @idEstudiante AND est.codigo = 'I')
                BEGIN
                    -- INT-HU-01 (decision de John 2026-10-28, opcion a): el estudiante fue retirado del grupo (HU051,
                    -- matricula 'I') y vuelve a solicitar el ingreso. Se REACTIVA su matricula (I -> A) en lugar de
                    -- crear otra (la validacion de duplicado del interno la rechazaria con 409). El cupo ya se verifico
                    -- arriba bajo UPDLOCK; las asistencias historicas de la matricula se conservan.
                    SELECT TOP 1 @idEstudianteGrupo = eg.id
                    FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                    WHERE eg.grupo = @idGrupo AND eg.estudiante = @idEstudiante AND est.codigo = 'I'
                    ORDER BY eg.id;

                    UPDATE dbo.EstudianteGrupo
                    SET estado = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A')
                    WHERE id = @idEstudianteGrupo;

                    -- Regla HU008: solo una asignatura ESPECIFICA inscribe al estudiante en el programa.
                    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                    SELECT NEWID(), @idEstudiante, pe.programa
                    FROM dbo.Grupo g
                    INNER JOIN dbo.Asignatura a ON a.id = g.asignatura
                    INNER JOIN dbo.Componente comp ON comp.id = a.componente AND comp.codigo = 'ESP'
                    INNER JOIN dbo.SemestrePlanEstudio spe ON spe.id = a.semestrePlanEstudio
                    INNER JOIN dbo.PlanEstudio pe ON pe.id = spe.planEstudio
                    WHERE g.id = @idGrupo
                      AND NOT EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep WHERE ep.estudiante = @idEstudiante AND ep.programa = pe.programa);

                    UPDATE dbo.SolicitudIngresoGrupo
                    SET estado = @estadoAceptada, docenteResolutor = @idDocente,
                        fechaResolucionUtc = SYSUTCDATETIME(), estudianteGrupo = @idEstudianteGrupo
                    WHERE id = @idSolicitudDefecto;
                    SET @codigoEstadoResultante = 'A';
                    SET @codigoExito = 'SIG_011';
                END
                ELSE
                BEGIN
                    EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                        @idEstudiante = @idEstudiante,
                        @idGrupo = @idGrupo,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @codigoEstado = 'A',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                    BEGIN
                        SELECT TOP 1 @idEstudianteGrupo = eg.id
                        FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                        WHERE eg.grupo = @idGrupo AND eg.estudiante = @idEstudiante AND est.codigo = 'A';

                        UPDATE dbo.SolicitudIngresoGrupo
                        SET estado = @estadoAceptada, docenteResolutor = @idDocente,
                            fechaResolucionUtc = SYSUTCDATETIME(), estudianteGrupo = @idEstudianteGrupo
                        WHERE id = @idSolicitudDefecto;
                        SET @codigoEstadoResultante = 'A';
                        SET @codigoExito = 'SIG_011';
                    END
                END
            END

            IF @codigoExito IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoExito,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF @estadoResultado = 0 AND XACT_STATE() = 1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
            ELSE IF @savepointCreado = 1 AND @estadoResultado = 0 AND XACT_STATE() = 1
            BEGIN
                ROLLBACK TRANSACTION sp_resolver_solicitud_ingreso;
            END
        END

        -- PASO 5: Traducir el codigo de rechazo a su mensaje de catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            SET @codigoEstadoResultante = NULL;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_resolver_solicitud_ingreso;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @codigoEstadoResultante = NULL;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        codigoEstadoResultante  = @codigoEstadoResultante;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_solicitud_ingreso_grupo  (HU053/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE propietario (Estudiante.usuario = ejecutor) retira su solicitud abierta (P o E): pasa a X (retirada)
-- y puede volver a solicitar. Codigos: GEN_002, SIG_007 inexistente o ajena, SIG_008 ya resuelta/retirada, SIG_015.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @solicitudEncontrada      UNIQUEIDENTIFIER;
    DECLARE @estadoActual             UNIQUEIDENTIFIER;
    DECLARE @estadoPendiente          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
    DECLARE @estadoEspera             UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'E');
    DECLARE @estadoRetirada           UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'X');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @estadoTransaccionCatch INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Validar la accion y el motivo (codigo de rechazo)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_retirar_solicitud_ingreso;
                SET @savepointCreado = 1;
            END

            SELECT @solicitudEncontrada = s.id, @estadoActual = s.estado
            FROM dbo.SolicitudIngresoGrupo s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estudiante e ON e.id = s.estudiante
            WHERE s.id = @idSolicitudDefecto AND e.usuario = @idUsuarioEjecutorDefecto;

            SET @codigoRechazo =
                CASE
                    WHEN @solicitudEncontrada IS NULL THEN 'SIG_007'
                    WHEN @estadoActual NOT IN (@estadoPendiente, @estadoEspera) THEN 'SIG_008'
                END;

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.SolicitudIngresoGrupo
                SET estado = @estadoRetirada, fechaResolucionUtc = SYSUTCDATETIME()
                WHERE id = @idSolicitudDefecto;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SIG_015',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    COMMIT TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                BEGIN
                    ROLLBACK TRANSACTION;
                END
            END
        END

        -- PASO 4: Traducir el codigo de rechazo a su mensaje de catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_retirar_solicitud_ingreso;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_ingreso_grupo_docente  (HU053/HU054/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- Bandeja de solicitudes de ingreso de UN grupo para su DOCENTE TITULAR (otro ejecutor => 0 filas), en orden de
-- llegada (fechaSolicitudUtc). posicionEspera numera las solicitudes EN ESPERA por llegada (informativo: el docente
-- puede aceptar a cualquiera). capacidadGrupo/cuposDisponibles = capacidad - matriculas activas.
-- Paginacion acotada como R2 (pagina >= 1, tamano 1..100).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_grupo_docente]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

-- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    -- PASO 3: Validacion de entrada
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Consulta y retorno de resultados
    ;WITH grupoTitular AS (
        SELECT g.id, g.cantidadEstudiantes AS capacidad,
               (SELECT COUNT(*) FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo ee ON ee.id = eg.estado
                WHERE eg.grupo = g.id AND ee.codigo = 'A') AS activos
        FROM dbo.Grupo g
        INNER JOIN dbo.Docente d ON d.id = g.docente
        WHERE g.id = @idGrupo AND d.usuario = @idUsuarioDefecto
    ),
    solicitudes AS (
        SELECT s.id, s.estudiante, s.fechaSolicitudUtc, s.fechaResolucionUtc, s.motivoRechazo,
               est.codigo AS codigoEstado, est.nombre AS nombreEstado, gt.capacidad, gt.activos,
               posicionEspera = CASE WHEN est.codigo = 'E'
                                     THEN ROW_NUMBER() OVER (PARTITION BY CASE WHEN est.codigo = 'E' THEN 1 ELSE 0 END
                                                             ORDER BY s.fechaSolicitudUtc, s.id) END
        FROM dbo.SolicitudIngresoGrupo s
        INNER JOIN grupoTitular gt ON gt.id = s.grupo
        INNER JOIN dbo.Estado est ON est.id = s.estado
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idSolicitud          = sol.id,
        idEstudiante         = estu.id,
        nombreEstudiante     = CAST(CONCAT_WS(N' ',
                                   NULLIF(TRIM(u.primerNombre), N''),
                                   NULLIF(TRIM(u.segundoNombre), N''),
                                   NULLIF(TRIM(u.primerApellido), N''),
                                   NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        numeroIdentificacion = u.numeroIdentificacion,
        codigoEstado         = CAST(sol.codigoEstado AS CHAR(1)),
        nombreEstado         = sol.nombreEstado,
        fechaSolicitudUtc    = sol.fechaSolicitudUtc,
        fechaResolucionUtc   = sol.fechaResolucionUtc,
        motivoRechazo        = sol.motivoRechazo,
        posicionEspera       = CAST(sol.posicionEspera AS INT),
        capacidadGrupo       = sol.capacidad,
        cuposDisponibles     = IIF(sol.capacidad - sol.activos < 0, 0, sol.capacidad - sol.activos),
        totalRegistros       = COUNT(*) OVER()
    FROM solicitudes sol
    INNER JOIN dbo.Estudiante estu ON estu.id = sol.estudiante
    INNER JOIN dbo.Usuario u       ON u.id = estu.usuario
    WHERE (@estadoFiltro IS NULL OR sol.codigoEstado = @estadoFiltro)
    ORDER BY sol.fechaSolicitudUtc ASC, sol.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_solicitudes_ingreso_estudiante  (HU053/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET + totalRegistros (THROW ante ejecutor nulo).
-- "Mis solicitudes de ingreso": SOLO las del estudiante autenticado (Estudiante.usuario = ejecutor), la mas reciente
-- primero, con grupo, asignatura, docente, estado y motivo de rechazo. Paginacion acotada (1..100).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_estudiante]
(
    @codigoEstado       NVARCHAR(5) = NULL,
    @numeroPagina       INT         = 1,
    @tamanoPagina       INT         = 10,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER
)
AS

    -- REC4 (estilo): variables declaradas en la cabecera; las que dependen de un paso previo se asignan con SET en ese paso.
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;
    DECLARE @estadoFiltro NVARCHAR(5) = NULLIF(TRIM(@codigoEstado), '');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

-- PASO 1: Validar el identificador de correlacion
    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    -- PASO 2: Ejecutor obligatorio (GEN_002)
    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001', @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    -- PASO 3: Validacion de entrada
    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idSolicitud        = s.id,
        idGrupo            = g.id,
        codigoGrupo        = g.codigo,
        nombreGrupo        = g.nombre,
        idAsignatura       = asg.id,
        nombreAsignatura   = asg.nombre,
        nombreDocente      = CAST(CONCAT_WS(N' ',
                                 NULLIF(TRIM(ud.primerNombre), N''),
                                 NULLIF(TRIM(ud.primerApellido), N''),
                                 NULLIF(TRIM(ud.segundoApellido), N'')) AS NVARCHAR(400)),
        codigoEstado       = CAST(est.codigo AS CHAR(1)),
        nombreEstado       = est.nombre,
        fechaSolicitudUtc  = s.fechaSolicitudUtc,
        fechaResolucionUtc = s.fechaResolucionUtc,
        motivoRechazo      = s.motivoRechazo,
        totalRegistros     = COUNT(*) OVER()
    FROM dbo.SolicitudIngresoGrupo s
    INNER JOIN dbo.Estudiante estu ON estu.id = s.estudiante
    INNER JOIN dbo.Estado est      ON est.id = s.estado
    INNER JOIN dbo.Grupo g         ON g.id = s.grupo
    INNER JOIN dbo.Asignatura asg  ON asg.id = g.asignatura
    INNER JOIN dbo.Docente d       ON d.id = g.docente
    INNER JOIN dbo.Usuario ud      ON ud.id = d.usuario
    WHERE estu.usuario = @idUsuarioDefecto
      AND (@estadoFiltro IS NULL OR est.codigo = @estadoFiltro)
    ORDER BY s.fechaSolicitudUtc DESC, s.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_destinatarios_solicitud_ingreso_grupo  (HU053/HU054/HU055)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW ante ejecutor nulo).
-- Destinatarios de los avisos de una solicitud de ingreso: el ESTUDIANTE solicitante y el DOCENTE titular del grupo,
-- con el contexto del grupo. Solo los ve el propio estudiante o el docente titular (otro ejecutor => 0 filas).
-- El correo es dato de uso interno del NotificacionPort; el backend no lo expone por HTTP ni lo escribe en logs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

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

    ;WITH contexto AS (
        SELECT g.id AS idGrupo, g.codigo AS codigoGrupo, g.nombre AS nombreGrupo, asg.nombre AS nombreAsignatura,
               e.usuario AS usuarioEstudiante, d.usuario AS usuarioDocente
        FROM dbo.SolicitudIngresoGrupo s
        INNER JOIN dbo.Estudiante e   ON e.id = s.estudiante
        INNER JOIN dbo.Grupo g        ON g.id = s.grupo
        INNER JOIN dbo.Docente d      ON d.id = g.docente
        INNER JOIN dbo.Asignatura asg ON asg.id = g.asignatura
        WHERE s.id = @idSolicitud AND @idUsuarioDefecto IN (e.usuario, d.usuario)
    ),
    destinatarios AS (
        SELECT orden = 1, rolDestinatario = 'ESTUDIANTE', idUsuario = usuarioEstudiante, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
        UNION ALL
        SELECT 2, 'DOCENTE', usuarioDocente, idGrupo, codigoGrupo, nombreGrupo, nombreAsignatura FROM contexto
    )
    SELECT
        rolDestinatario  = CAST(dst.rolDestinatario AS VARCHAR(20)),
        idUsuario        = dst.idUsuario,
        nombreCompleto   = CAST(CONCAT_WS(N' ',
                               NULLIF(TRIM(u.primerNombre), N''),
                               NULLIF(TRIM(u.segundoNombre), N''),
                               NULLIF(TRIM(u.primerApellido), N''),
                               NULLIF(TRIM(u.segundoApellido), N'')) AS NVARCHAR(400)),
        correo           = u.correo,
        idGrupo          = dst.idGrupo,
        codigoGrupo      = dst.codigoGrupo,
        nombreGrupo      = dst.nombreGrupo,
        nombreAsignatura = dst.nombreAsignatura
    FROM destinatarios dst
    INNER JOIN dbo.Usuario u ON u.id = dst.idUsuario
    ORDER BY dst.orden;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: permisos del runtime para las solicitudes de ingreso a grupo. Cada SP valida el ambito en
-- tablas base (estudiante propietario o docente titular). Script aditivo e idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_registrar_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52183, 'HU053_HU055_RUNTIME_GRANT: usp_registrar_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_resolver_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52184, 'HU053_HU055_RUNTIME_GRANT: usp_resolver_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52185, 'HU053_HU055_RUNTIME_GRANT: usp_retirar_solicitud_ingreso_grupo requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_grupo_docente', N'P') IS NULL
    THROW 52186, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_solicitudes_ingreso_grupo_docente requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_estudiante', N'P') IS NULL
    THROW 52187, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_solicitudes_ingreso_estudiante requerido ausente.', 1;
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo', N'P') IS NULL
    THROW 52188, 'HU053_HU055_RUNTIME_GRANT: usp_consultar_destinatarios_solicitud_ingreso_grupo requerido ausente.', 1;
GO

GRANT EXECUTE ON [dbo].[usp_registrar_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_resolver_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_retirar_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_ingreso_grupo_docente] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_solicitudes_ingreso_estudiante] TO [rol_asistencias_runtime];
GRANT EXECUTE ON [dbo].[usp_consultar_destinatarios_solicitud_ingreso_grupo] TO [rol_asistencias_runtime];
GO

-- R-7: mensajes (MERGE de develop) y plantillas/marcadores desde el archivo (o v1 del seed si no hay archivo).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU053/HU054/HU055: mensajes de catalogo de las solicitudes de ingreso a un grupo (usuario).
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('SIG_001', 'BUSINESS_ERROR', 'MEDIO', N'Solo un estudiante puede solicitar el ingreso a un grupo.'),
    ('SIG_002', 'BUSINESS_ERROR', 'MEDIO', N'El grupo indicado no existe.'),
    ('SIG_003', 'BUSINESS_ERROR', 'MEDIO', N'El período académico del grupo ya terminó.'),
    ('SIG_004', 'BUSINESS_ERROR', 'MEDIO', N'El estudiante ya está matriculado en este grupo.'),
    ('SIG_005', 'BUSINESS_ERROR', 'MEDIO', N'Ya existe una solicitud abierta para este grupo.'),
    ('SIG_006', 'SUCCESS', 'BAJO', N'La solicitud de ingreso al grupo fue registrada.'),
    ('SIG_007', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud indicada no existe o no está a su cargo.'),
    ('SIG_008', 'BUSINESS_ERROR', 'MEDIO', N'La solicitud ya fue resuelta o retirada.'),
    ('SIG_009', 'BUSINESS_ERROR', 'MEDIO', N'La acción indicada no es válida; use ACEPTAR o RECHAZAR.'),
    ('SIG_010', 'BUSINESS_ERROR', 'MEDIO', N'El motivo del rechazo es obligatorio y no puede superar 500 caracteres.'),
    ('SIG_011', 'SUCCESS', 'BAJO', N'La solicitud fue aceptada y el estudiante quedó matriculado en el grupo.'),
    ('SIG_012', 'SUCCESS', 'BAJO', N'El grupo no tiene cupo: la solicitud quedó en lista de espera.'),
    ('SIG_013', 'BUSINESS_ERROR', 'MEDIO', N'El grupo sigue sin cupo; la solicitud permanece en lista de espera.'),
    ('SIG_014', 'SUCCESS', 'BAJO', N'La solicitud fue rechazada.'),
    ('SIG_015', 'SUCCESS', 'BAJO', N'La solicitud fue retirada.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

-- Mensajes tecnicos (el backend clasifica por el codigo via DbTechnicalError).
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('SIG_001', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: el ejecutor no tiene dbo.Estudiante.'),
    ('SIG_002', 'BUSINESS_ERROR', 'MEDIO', N'Existencia: no hay dbo.Grupo con el id indicado.'),
    ('SIG_003', 'BUSINESS_ERROR', 'MEDIO', N'Regla: PeriodoAcademico.fechaFin es anterior a la fecha local (TIEMPO.ZONA_HORARIA_SQLSERVER).'),
    ('SIG_004', 'BUSINESS_ERROR', 'MEDIO', N'Regla: existe dbo.EstudianteGrupo activo (A) del estudiante en el grupo.'),
    ('SIG_005', 'BUSINESS_ERROR', 'MEDIO', N'Unicidad: existe dbo.SolicitudIngresoGrupo en estado P o E para el estudiante y el grupo.'),
    ('SIG_006', 'SUCCESS', 'BAJO', N'Insercion: dbo.SolicitudIngresoGrupo en estado P.'),
    ('SIG_007', 'BUSINESS_ERROR', 'MEDIO', N'Ambito: la solicitud no existe o el ejecutor no es el docente titular del grupo / el estudiante propietario.'),
    ('SIG_008', 'BUSINESS_ERROR', 'MEDIO', N'Regla: la solicitud no esta en estado P o E.'),
    ('SIG_009', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @accion distinta de ACEPTAR o RECHAZAR.'),
    ('SIG_010', 'BUSINESS_ERROR', 'MEDIO', N'Validacion: @motivo nulo, vacio o de mas de 500 caracteres al rechazar.'),
    ('SIG_011', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud A y dbo.EstudianteGrupo activo creado (usp_registrar_estudiante_en_grupo_interno).'),
    ('SIG_012', 'SUCCESS', 'BAJO', N'Actualizacion: sin cupo (capacidad - activos <= 0) bajo UPDLOCK; solicitud P pasa a E.'),
    ('SIG_013', 'BUSINESS_ERROR', 'MEDIO', N'Regla: solicitud E sin cupo disponible bajo UPDLOCK.'),
    ('SIG_014', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud R con motivoRechazo.'),
    ('SIG_015', 'SUCCESS', 'BAJO', N'Actualizacion: solicitud X retirada por el estudiante propietario.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
USE [gestionasistenciadb];
GO
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES ('ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA', 'BUSINESS_ERROR', 'MEDIO', 'La gestión de solicitudes de matrícula aún no se encuentra disponible.'))
    AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES ('ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA', 'BUSINESS_ERROR', 'MEDIO', 'Capability SolicitudMatricula is not implemented in the current schema.'))
    AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaSolicitudIngreso', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.PlantillaNotificacion (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
        SELECT a.id, a.tipo, a.idioma, a.version, a.asunto, a.cuerpo, a.activa, a.creadoPor, a.creadoEn
        FROM dbo.zz_archivo_PlantillaSolicitudIngreso a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion p WHERE p.id = a.id
                          OR (p.tipo = a.tipo AND p.idioma = a.idioma AND p.version = a.version));';
END
ELSE
BEGIN
    MERGE INTO [dbo].[PlantillaNotificacion] AS Target
    USING (VALUES
        ('SOLICITUD_INGRESO_REGISTRADA', 'es', 1, N'Nueva solicitud de ingreso al grupo {grupo}', N'{estudiante} solicitó ingresar al grupo {grupo}. Revísala en la plataforma.', 1),
        ('SOLICITUD_INGRESO_RESUELTA', 'es', 1, N'Respuesta a tu solicitud de ingreso al grupo {grupo}', N'Tu solicitud de ingreso al grupo {grupo} fue {resultado}. Consulta el detalle en la plataforma.', 1),
        ('SOLICITUD_INGRESO_RETIRADA', 'es', 1, N'Solicitud de ingreso retirada del grupo {grupo}', N'{estudiante} retiró su solicitud de ingreso al grupo {grupo}.', 1)
    ) AS Source (tipo, idioma, version, asunto, cuerpo, activa)
    ON (Target.tipo = Source.tipo AND Target.idioma = Source.idioma AND Target.version = Source.version)
    WHEN NOT MATCHED THEN
        INSERT (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
        VALUES (NEWID(), Source.tipo, Source.idioma, Source.version, Source.asunto, Source.cuerpo, Source.activa, NULL, SYSUTCDATETIME());
END
GO
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.PlantillaNotificacionMarcador (id, tipo, marcador, descripcion, ejemplo, obligatorio)
        SELECT a.id, a.tipo, a.marcador, a.descripcion, a.ejemplo, a.obligatorio
        FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador m WHERE m.id = a.id
                          OR (m.tipo = a.tipo AND m.marcador = a.marcador));';
END
ELSE
BEGIN
    MERGE INTO [dbo].[PlantillaNotificacionMarcador] AS Target
    USING (VALUES
        ('SOLICITUD_INGRESO_REGISTRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
        ('SOLICITUD_INGRESO_REGISTRADA', 'estudiante', N'Nombre completo del estudiante solicitante', N'Juan Pérez', 1),
        ('SOLICITUD_INGRESO_RESUELTA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
        ('SOLICITUD_INGRESO_RESUELTA', 'resultado', N'Resultado de la solicitud (aceptada, puesta en espera o rechazada)', N'aceptada', 1),
        ('SOLICITUD_INGRESO_RETIRADA', 'grupo', N'Nombre del grupo y asignatura', N'G01 de Ingeniería de Software', 1),
        ('SOLICITUD_INGRESO_RETIRADA', 'estudiante', N'Nombre completo del estudiante que retiró la solicitud', N'Juan Pérez', 1)
    ) AS Source (tipo, marcador, descripcion, ejemplo, obligatorio)
    ON (Target.tipo = Source.tipo AND Target.marcador = Source.marcador)
    WHEN NOT MATCHED THEN
        INSERT (id, tipo, marcador, descripcion, ejemplo, obligatorio)
        VALUES (NEWID(), Source.tipo, Source.marcador, Source.descripcion, Source.ejemplo, Source.obligatorio);
END
GO

-- R-8: notificaciones canceladas. Depuradas o reintentadas despues del up = resueltas (no se tocan). Las que siguen
-- canceladas recuperan su estado; una RESERVADA vuelve como PENDIENTE con proximoIntentoEn = ahora (bloqueante 3b).
IF OBJECT_ID(N'dbo.zz_archivo_NotificacionSolicitudIngreso', N'U') IS NOT NULL
BEGIN
    DECLARE @depuradas INT, @reintentadas INT, @restauradas INT;
    EXEC sys.sp_executesql N'
        SELECT @d = COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.NotificacionSaliente n WHERE n.id = a.idNotificacion);
        SELECT @r = COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso a
        INNER JOIN dbo.NotificacionSaliente n ON n.id = a.idNotificacion
        WHERE n.codigoError IS NULL OR n.codigoError <> ''TIPO_NOTIFICACION_RETIRADO'';
        UPDATE n
        SET idEstado = en.id,
            codigoError = a.codigoErrorAnterior,
            detalleError = a.detalleErrorAnterior,
            proximoIntentoEn = IIF(a.codigoEstadoAnterior = ''RESERVADA'', SYSDATETIMEOFFSET(), a.proximoIntentoEnAnterior),
            reservadoHasta = NULL,
            reservadoPor = NULL
        FROM dbo.NotificacionSaliente n
        INNER JOIN dbo.zz_archivo_NotificacionSolicitudIngreso a ON a.idNotificacion = n.id
        INNER JOIN dbo.EstadoNotificacion en ON en.codigo = IIF(a.codigoEstadoAnterior = ''RESERVADA'', ''PENDIENTE'', a.codigoEstadoAnterior)
        WHERE n.codigoError = ''TIPO_NOTIFICACION_RETIRADO'';
        SET @u = @@ROWCOUNT;',
        N'@d INT OUTPUT, @r INT OUTPUT, @u INT OUTPUT', @d = @depuradas OUTPUT, @r = @reintentadas OUTPUT, @u = @restauradas OUTPUT;
    PRINT CONCAT('CULM001_A_DOWN13 notificaciones resueltas: depuradas=', @depuradas, ' reintentadas=', @reintentadas);
    PRINT CONCAT('CULM001_A_DOWN13 notificaciones restauradas=', @restauradas);
END
GO

-- R-9: tablas de archivo. La de solicitudes solo si todas sus filas volvieron (unico THROW del down).
IF OBJECT_ID(N'dbo.zz_archivo_NotificacionSolicitudIngreso', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_NotificacionSolicitudIngreso;
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaSolicitudIngreso', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_PlantillaSolicitudIngreso;
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso', N'U') IS NOT NULL DROP TABLE dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso;
GO
IF OBJECT_ID(N'dbo.zz_archivo_SolicitudIngresoGrupo', N'U') IS NOT NULL
BEGIN
    DECLARE @faltantes INT;
    EXEC sys.sp_executesql N'SELECT @n = COUNT(*) FROM dbo.zz_archivo_SolicitudIngresoGrupo a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s WHERE s.id = a.id);', N'@n INT OUTPUT', @n = @faltantes OUTPUT;
    IF @faltantes > 0
        THROW 53310, 'CULM001_A: hay solicitudes archivadas sin restaurar.', 1;
    DROP TABLE dbo.zz_archivo_SolicitudIngresoGrupo;
END
GO
PRINT CONCAT('CULM001_A_DOWN13 SolicitudIngresoGrupo=', IIF(OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NULL, 'AUSENTE', 'restaurada'));
GO
