USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- 13_culm001_a_retiro_solicitudes_up.sql (CULM-001 paquete A.1, CONTRACT §2.4)
-- Decision del responsable (2026-11-06): la matricula solo se hace por QR/PIN (HU176B) o manualmente por el docente
-- titular (HU050); HU026, HU053, HU054 y HU055 pasan a DESCARTADA. DEC-009: la reactivacion I -> A pasa al interno de
-- matricula. DEC-010: antes de borrar, el historial de solicitudes, las notificaciones pendientes y las plantillas de los
-- tipos SOLICITUD_INGRESO_* se copian a tablas de archivo zz_archivo_* (solo lectura, sin FK ni GRANT); las
-- notificaciones no terminales de esos tipos se cancelan (FALLIDA_DEFINITIVA, TIPO_NOTIFICACION_RETIRADO; A-C1).
-- F-COO-004: la matricula manual exige el docente titular. deploy_schema.ps1 no borra objetos. Idempotente.
-- Aplicar con el backend detenido (U-0 aborta si hay notificaciones de solicitud reservadas vigentes).
-- Rollback: 13_culm001_a_retiro_solicitudes_down.sql (si se aplico 14, primero su down).
-- ============================================================================

-- U-0: notificaciones de solicitud reservadas por el despachador (reserva vigente) => abortar.
IF OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.NotificacionSaliente n
               INNER JOIN dbo.EstadoNotificacion en ON en.id = n.idEstado
               WHERE n.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
                 AND en.codigo = 'RESERVADA'
                 AND n.reservadoHasta > SYSDATETIMEOFFSET())
    THROW 53300, 'CULM001_A: hay notificaciones de solicitud reservadas por el despachador; detener el backend y reintentar.', 1;
GO

-- U-1: tablas de archivo (sin FK y sin GRANT).
IF OBJECT_ID(N'dbo.zz_archivo_SolicitudIngresoGrupo', N'U') IS NULL
    CREATE TABLE dbo.zz_archivo_SolicitudIngresoGrupo (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_zz_archivo_SolicitudIngresoGrupo PRIMARY KEY,
        estudiante         UNIQUEIDENTIFIER NOT NULL,
        grupo              UNIQUEIDENTIFIER NOT NULL,
        codigoEstado       CHAR(1)          NOT NULL,
        fechaSolicitudUtc  DATETIME2(7)     NOT NULL,
        fechaResolucionUtc DATETIME2(7)     NULL,
        motivoRechazo      NVARCHAR(500)    NULL,
        docenteResolutor   UNIQUEIDENTIFIER NULL,
        estudianteGrupo    UNIQUEIDENTIFIER NULL,
        fechaArchivoUtc    DATETIME2(7)     NOT NULL CONSTRAINT DF_zz_archivo_SolicitudIngresoGrupo_fecha DEFAULT SYSUTCDATETIME(),
        origen             VARCHAR(20)      NOT NULL CONSTRAINT DF_zz_archivo_SolicitudIngresoGrupo_origen DEFAULT 'CULM-001-A'
    );
IF OBJECT_ID(N'dbo.zz_archivo_NotificacionSolicitudIngreso', N'U') IS NULL
    CREATE TABLE dbo.zz_archivo_NotificacionSolicitudIngreso (
        idNotificacion           UNIQUEIDENTIFIER  NOT NULL CONSTRAINT PK_zz_archivo_NotificacionSolicitudIngreso PRIMARY KEY,
        codigoEstadoAnterior     VARCHAR(30)       NOT NULL,
        codigoErrorAnterior      VARCHAR(40)       NULL,
        detalleErrorAnterior     NVARCHAR(300)     NULL,
        proximoIntentoEnAnterior DATETIMEOFFSET(7) NULL,
        fechaCancelacionUtc      DATETIME2(7)      NOT NULL CONSTRAINT DF_zz_archivo_NotificacionSolicitudIngreso_fecha DEFAULT SYSUTCDATETIME()
    );
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaSolicitudIngreso', N'U') IS NULL
    CREATE TABLE dbo.zz_archivo_PlantillaSolicitudIngreso (
        id        UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_zz_archivo_PlantillaSolicitudIngreso PRIMARY KEY,
        tipo      VARCHAR(60)      NOT NULL,
        idioma    CHAR(2)          NOT NULL,
        version   INT              NOT NULL,
        asunto    NVARCHAR(200)    NOT NULL,
        cuerpo    NVARCHAR(4000)   NOT NULL,
        activa    BIT              NOT NULL,
        creadoPor UNIQUEIDENTIFIER NULL,
        creadoEn  DATETIME2(3)     NOT NULL
    );
IF OBJECT_ID(N'dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso', N'U') IS NULL
    CREATE TABLE dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso (
        id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_zz_archivo_PlantillaMarcadorSolicitudIngreso PRIMARY KEY,
        tipo        VARCHAR(60)      NOT NULL,
        marcador    VARCHAR(40)      NOT NULL,
        descripcion NVARCHAR(200)    NOT NULL,
        ejemplo     NVARCHAR(100)    NOT NULL,
        obligatorio BIT              NOT NULL
    );
GO

-- U-2: archivo, cancelacion del outbox, plantillas, mensajes y catalogos de A.1 en UNA transaccion.
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    -- (a) historial de solicitudes (sp_executesql: el lote compila aunque la tabla ya no exista)
    IF OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NOT NULL
        EXEC sys.sp_executesql N'
            INSERT INTO dbo.zz_archivo_SolicitudIngresoGrupo (id, estudiante, grupo, codigoEstado, fechaSolicitudUtc,
                fechaResolucionUtc, motivoRechazo, docenteResolutor, estudianteGrupo)
            SELECT s.id, s.estudiante, s.grupo, e.codigo, s.fechaSolicitudUtc, s.fechaResolucionUtc, s.motivoRechazo,
                   s.docenteResolutor, s.estudianteGrupo
            FROM dbo.SolicitudIngresoGrupo s
            INNER JOIN dbo.Estado e ON e.id = s.estado
            WHERE NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_SolicitudIngresoGrupo a WHERE a.id = s.id);';

    -- (b) estado previo de las notificaciones no terminales de los 3 tipos (A-C2)
    INSERT INTO dbo.zz_archivo_NotificacionSolicitudIngreso (idNotificacion, codigoEstadoAnterior, codigoErrorAnterior,
        detalleErrorAnterior, proximoIntentoEnAnterior)
    SELECT n.id, en.codigo, n.codigoError, n.detalleError, n.proximoIntentoEn
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion en ON en.id = n.idEstado
    WHERE n.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND en.esTerminal = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_NotificacionSolicitudIngreso a WHERE a.idNotificacion = n.id);

    -- (c) cancelacion (A-C1): FALLIDA_DEFINITIVA es terminal; el despachador no la toma
    UPDATE n
    SET idEstado = (SELECT id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA'),
        codigoError = 'TIPO_NOTIFICACION_RETIRADO',
        detalleError = N'CULM-001 A: el tipo de notificacion fue retirado con las solicitudes de ingreso.',
        proximoIntentoEn = NULL,
        reservadoHasta = NULL,
        reservadoPor = NULL
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion en ON en.id = n.idEstado
    WHERE n.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND en.esTerminal = 0;

    -- (d) plantillas (todas las versiones) y marcadores: copia y borrado
    INSERT INTO dbo.zz_archivo_PlantillaSolicitudIngreso (id, tipo, idioma, version, asunto, cuerpo, activa, creadoPor, creadoEn)
    SELECT p.id, p.tipo, p.idioma, p.version, p.asunto, p.cuerpo, p.activa, p.creadoPor, p.creadoEn
    FROM dbo.PlantillaNotificacion p
    WHERE p.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaSolicitudIngreso a WHERE a.id = p.id);
    INSERT INTO dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso (id, tipo, marcador, descripcion, ejemplo, obligatorio)
    SELECT m.id, m.tipo, m.marcador, m.descripcion, m.ejemplo, m.obligatorio
    FROM dbo.PlantillaNotificacionMarcador m
    WHERE m.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso a WHERE a.id = m.id);
    DELETE m FROM dbo.PlantillaNotificacionMarcador m
    WHERE m.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso a WHERE a.id = m.id);
    DELETE p FROM dbo.PlantillaNotificacion p
    WHERE p.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
      AND EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaSolicitudIngreso a WHERE a.id = p.id);

    -- (e) mensajes SIG_* y ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA
    DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SIG_001', 'SIG_002', 'SIG_003', 'SIG_004', 'SIG_005', 'SIG_006', 'SIG_007', 'SIG_008', 'SIG_009', 'SIG_010', 'SIG_011', 'SIG_012', 'SIG_013', 'SIG_014', 'SIG_015', 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA');
    DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SIG_001', 'SIG_002', 'SIG_003', 'SIG_004', 'SIG_005', 'SIG_006', 'SIG_007', 'SIG_008', 'SIG_009', 'SIG_010', 'SIG_011', 'SIG_012', 'SIG_013', 'SIG_014', 'SIG_015', 'ERR_SOLICITUD_MATRICULA_NO_IMPLEMENTADA');

    -- (f) catalogos de A.1 (E-08): parametros MATRICULA/* y estado X
        MERGE INTO [dbo].[CatalogoParametro] AS Target
        USING (VALUES
            ('MATRICULA', 'ESTADO_RETIRADA', N'I', 'STRING', N'I'),
            ('MATRICULA', 'ESTADO_INSCRITA', N'A', 'STRING', N'A')
        ) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
        ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
        WHEN MATCHED THEN
            UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN
            INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
            VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
        MERGE INTO [dbo].[Estado] AS Target
        USING (VALUES ('D6E2F3A4-5B6C-4D7E-9F80-A12B3C4D5E6F', 'retirada', 'X')) AS Source (id, nombre, codigo)
        ON (Target.id = TRY_CAST(Source.id AS UNIQUEIDENTIFIER) OR Target.codigo = Source.codigo)
        WHEN MATCHED THEN
            UPDATE SET Target.nombre = Source.nombre, Target.codigo = Source.codigo
        WHEN NOT MATCHED THEN
            INSERT (id, nombre, codigo) VALUES (TRY_CAST(Source.id AS UNIQUEIDENTIFIER), Source.nombre, Source.codigo);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
SET XACT_ABORT OFF;
GO

-- U-3: guardias antes de eliminar.
IF OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NOT NULL
BEGIN
    DECLARE @sinArchivo INT;
    EXEC sys.sp_executesql N'SELECT @n = COUNT(*) FROM dbo.SolicitudIngresoGrupo s
        WHERE NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_SolicitudIngresoGrupo a WHERE a.id = s.id);',
        N'@n INT OUTPUT', @n = @sinArchivo OUTPUT;
    IF @sinArchivo > 0
        THROW 53301, 'CULM001_A: archivo incompleto; no se elimina SolicitudIngresoGrupo.', 1;
END;
IF EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion p WHERE p.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
           AND NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaSolicitudIngreso a WHERE a.id = p.id))
   OR EXISTS (SELECT 1 FROM dbo.PlantillaNotificacionMarcador m WHERE m.tipo IN ('SOLICITUD_INGRESO_REGISTRADA', 'SOLICITUD_INGRESO_RESUELTA', 'SOLICITUD_INGRESO_RETIRADA')
           AND NOT EXISTS (SELECT 1 FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso a WHERE a.id = m.id))
    THROW 53303, 'CULM001_A: quedan plantillas o marcadores de solicitud sin archivo.', 1;
GO

-- U-4: SP de las solicitudes (sus GRANT caen con el DROP).
IF OBJECT_ID(N'dbo.usp_registrar_solicitud_ingreso_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_registrar_solicitud_ingreso_grupo];
GO
IF OBJECT_ID(N'dbo.usp_resolver_solicitud_ingreso_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_resolver_solicitud_ingreso_grupo];
GO
IF OBJECT_ID(N'dbo.usp_retirar_solicitud_ingreso_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_retirar_solicitud_ingreso_grupo];
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_grupo_docente', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_grupo_docente];
GO
IF OBJECT_ID(N'dbo.usp_consultar_solicitudes_ingreso_estudiante', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_solicitudes_ingreso_estudiante];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_solicitud_ingreso_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_destinatarios_solicitud_ingreso_grupo];
GO

-- U-5: tabla (FK, indices y default incluidos).
IF OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NOT NULL
    DROP TABLE dbo.SolicitudIngresoGrupo;
GO

-- U-6: estado E (en espera). La unica FK restante hacia dbo.Estado es la de los reclamos; X se conserva (A-C3).
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID(N'dbo.Estado')
           AND name <> N'FK_SolicitudRevisionAsistencia_Estado')
    THROW 53302, 'CULM001_A: existe otra FK hacia dbo.Estado; revisar antes de borrar el estado E.', 1;
DELETE FROM dbo.Estado
WHERE id = 'C5D1E2F3-4A5B-4C6D-8E7F-901A2B3C4D5E' AND codigo = 'E'
  AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r WHERE r.estado = Estado.id);
GO

-- U-7: usp_consultar_oferta_grupos_estudiante (E-01), copia exacta de schema/ (conserva su GRANT).
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
--     la(s) institucion(es) de sus programas. Con 0 no se muestran transversales (solo se ingresa con el QR/PIN del
--     docente, HU176B, o por matricula manual del docente, HU050).
-- Cada fila trae docente, horario, capacidad y cupos (capacidad - matriculas inscritas, minimo 0), el componente de la
-- asignatura y si el estudiante esta matriculado. Solo la matricula con el codigo del parametro MATRICULA/ESTADO_INSCRITA
-- cuenta como inscrita (CULM-001 A, N10). CULM-001 A.1: sin columnas de solicitud de ingreso (19 columnas).
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
    DECLARE @codigoInscrita NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));

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
                       WHERE eg.grupo = g.id AND ee.codigo = @codigoInscrita)
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
                                     WHERE eg.grupo = o.id AND eg.estudiante = @idEstudiante AND ee.codigo = @codigoInscrita), 1, 0) AS BIT),
        codigoComponente       = CAST(o.codigoComponente AS NVARCHAR(3)),
        totalRegistros         = COUNT(*) OVER()
    FROM oferta o
    INNER JOIN dbo.Docente doc ON doc.id = o.docente
    INNER JOIN dbo.Usuario ud  ON ud.id = doc.usuario
    ORDER BY o.nombreAsignatura ASC, o.fechaInicio ASC, o.codigo ASC, o.id ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamano ROWS ONLY;
END;
GO

-- U-8: usp_internal_reactivar_matricula_retirada (CONTRACT §2.3), copia exacta de schema/.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_reactivar_matricula_retirada (CULM-001 A.1, DEC-009; CONTRACT §2.3)
--
-- Interno (sin GRANT al runtime). Lo llama usp_registrar_estudiante_en_grupo_interno (PASO 3.8), al que llegan las dos
-- vias de matricula que quedan: la manual del docente titular (HU050) y la de QR/PIN (HU176B). Regla INT-HU-01: si el
-- estudiante tiene en el grupo una matricula RETIRADA (codigo del parametro MATRICULA/ESTADO_RETIRADA), se reactiva la
-- MISMA fila al estado destino (se conservan sus asistencias historicas). Sin matricula retirada no escribe nada
-- (@reactivada = 0, exito) y el interno sigue con el alta normal.
--   * La busqueda inicial no toma bloqueos: la matricula nueva normal no paga el costo del bloqueo.
--   * Solo con matricula retirada se bloquea el Grupo (UPDLOCK, HOLDLOCK), se relee la fila por su id y se cuentan las
--     matriculas en el estado destino bajo bloqueo: sin cupo => ERR_CUPO_SUPERADO, sin escrituras.
--   * No inscribe en el programa: esa regla la aplica una sola vez el bloque comun del interno.
--   * Transaccion propia si @@TRANCOUNT = 0; si no, savepoint sp_reactivar_matricula. @@TRANCOUNT sale igual que entra.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_reactivar_matricula_retirada]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoEstadoDestino     NVARCHAR(10),
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @reactivada              BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDestino        NVARCHAR(10)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstadoDestino, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @codigoRetirada       NVARCHAR(10)     = UPPER(TRIM(CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_RETIRADA') AS NVARCHAR(10))));
    DECLARE @idEstadoDestino      UNIQUEIDENTIFIER;
    DECLARE @idEstadoRetirada     UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupoBloqueado UNIQUEIDENTIFIER;
    DECLARE @capacidad            INT;
    DECLARE @activos              INT;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @reactivada = 0;

    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_reactivar_matricula;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: codigos por catalogo (parametro MATRICULA/ESTADO_RETIRADA y estado destino del interno)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoRetirada = es.id FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = @codigoRetirada;
            SELECT @idEstadoDestino = es.id FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = @codigoDestino;

            IF @idEstadoRetirada IS NULL OR @idEstadoDestino IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Estado Estudiante Grupo (reactivacion)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: busqueda sin bloqueo de una matricula retirada del estudiante en el grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
            WHERE eg.grupo = @idGrupoDefecto
              AND eg.estudiante = @idEstudianteDefecto
              AND es.codigo = @codigoRetirada
            ORDER BY eg.id;
        END

        -- PASO 4: solo con matricula retirada: bloqueo del grupo, relectura de la fila y cupo bajo bloqueo
        IF @estadoResultado = 1 AND @idEstudianteGrupo IS NOT NULL
        BEGIN
            SELECT @capacidad = g.cantidadEstudiantes
            FROM dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)
            WHERE g.id = @idGrupoDefecto;

            SELECT @idEstudianteGrupoBloqueado = eg.id
            FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
            WHERE eg.id = @idEstudianteGrupo
              AND eg.estado = @idEstadoRetirada;

            IF @idEstudianteGrupoBloqueado IS NOT NULL
            BEGIN
                SELECT @activos = COUNT(*)
                FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                WHERE eg.grupo = @idGrupoDefecto
                  AND es.codigo = @codigoDestino;

                IF @capacidad IS NULL OR @capacidad - @activos <= 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ERR_CUPO_SUPERADO',
                        @p_param1 = @idGrupoDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    -- PASO 5: misma fila, nuevo estado (INT-HU-01); el mensaje de exito lo pone el interno
                    UPDATE dbo.EstudianteGrupo
                    SET estado = @idEstadoDestino
                    WHERE id = @idEstudianteGrupoBloqueado;

                    SET @reactivada = 1;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END
        END

        IF @estadoResultado = 1 AND @reactivada = 0 AND @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA')
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

        -- PASO 6: cierre de la transaccion propia (las ramas de rechazo no escriben)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_reactivar_matricula;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @reactivada = 0;
    END CATCH
END;
GO

-- U-9: usp_registrar_estudiante_en_grupo_interno (E-03), copia exacta de schema/.
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_estudiante_en_grupo_interno (HU050 manual y HU176B QR/PIN)
--
-- Requiere transaccion del llamador; no la abre ni la confirma. Sus dos llamadores publicos la abren
-- (usp_registrar_estudiante_en_grupo y usp_internal_matricular_por_token) y revierten su savepoint de negocio ante un
-- rechazo posterior a la escritura (docs/arquitectura/transaccion-procedimiento.md, internos compuestos).
-- CULM-001 A.1 (DEC-009): PASO 3.8 reactiva la matricula RETIRADA del estudiante en el grupo (misma fila, I -> estado
-- destino) mediante usp_internal_reactivar_matricula_retirada; sin matricula retirada sigue el alta normal. La regla de
-- inscripcion en el programa (componente ESP) es comun a los dos caminos y vive solo aqui.
-- El estado por defecto ('' o el parametro) se resuelve con MATRICULA/ESTADO_INSCRITA (sin literal quemado).
-- ============================================================================
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
    DECLARE @reactivada           BIT = 0;

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
            IF @codigoEstadoDefecto = '' SET @codigoEstadoDefecto = UPPER(TRIM(CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10))));

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

        -- PASO 3.8 (CULM-001 A.1, DEC-009): reactivar la matricula retirada (misma fila) si existe.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_reactivar_matricula_retirada
                @idEstudiante = @idEstudianteDefecto,
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @codigoEstadoDestino = @codigoEstadoDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @reactivada = @reactivada OUTPUT;
        END

        IF @estadoResultado = 1 AND @reactivada = 0
        BEGIN
            EXEC dbo.usp_validar_registro_estudiante_en_grupo_interno 
                @idEstudiante = @idEstudianteDefecto, 
                @idGrupo = @idGrupoDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Inscripcion en el programa (comun al alta y a la reactivacion) e insercion del alta en dbo.EstudianteGrupo
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

            IF @reactivada = 0
            BEGIN
                INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
                VALUES (NEWID(), @idEstadoActivo, @idEstudianteDefecto, @idGrupoDefecto);
            END

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

-- U-10: usp_registrar_estudiante_en_grupo (E-04), copia exacta de schema/ (conserva su GRANT).
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_estudiante_en_grupo (HU050, STUDENT-GROUP CANONICAL COMMAND, NON-GOLDEN)
--
-- Matricula manual de un estudiante en un grupo. CULM-001 A.1:
--   * F-COO-004: solo el DOCENTE TITULAR del grupo matricula (perfil DOCENTE y titularidad GRUPO, SEC_001/SEC_002).
--   * DEC-009: una matricula retirada del estudiante en el grupo se reactiva (la misma fila) en el interno.
--   * Atomico (bloqueante 1): SET XACT_ABORT ON; transaccion propia si @@TRANCOUNT = 0, si no savepoint
--     sp_registrar_estudiante_grupo. Las validaciones sin escritura van antes del savepoint de negocio
--     sp_registrar_estudiante_negocio; un rechazo posterior a crear Usuario/Estudiante revierte ese savepoint (sin filas
--     parciales). El resultset canonico va fuera de la transaccion. Firma y resultset sin cambio.
-- ============================================================================
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

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @identidadEscrita           BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_registrar_estudiante_grupo;
            SET @savepointCreado = 1;
        END

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
                @codigoPerfilRequerido = 'DOCENTE',
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

        -- PASO 1.85 (CULM-001 A.1, F-COO-004): el ejecutor debe ser el docente titular del grupo (SEC_002).
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idGrupoDefecto,
                @tipoEntidadPadre = 'GRUPO',
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

        -- PASO 2: Sincronización de identidad (Usuario y Estudiante) e inscripción en grupo, bajo el savepoint de negocio
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_registrar_estudiante_negocio;

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
                SET @identidadEscrita = 1;
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
                    SET @identidadEscrita = 1;
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

            -- Rechazo despues de crear Usuario/Estudiante: se revierte solo el trabajo de negocio. Sin identidad escrita
            -- no hay nada que revertir (el interno no deja escrituras en sus rechazos de negocio), y se evita un
            -- ROLLBACK innecesario, que SQL Server prohibe bajo INSERT ... EXEC.
            IF @estadoResultado = 0 AND @identidadEscrita = 1 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_registrar_estudiante_negocio;
        END

        -- Cierre de la transaccion propia
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END

    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_registrar_estudiante_grupo;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

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

-- U-11: verificacion final.
USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
DECLARE @spPresentes INT = (SELECT COUNT(*) FROM sys.procedures WHERE name IN (N'usp_registrar_solicitud_ingreso_grupo', N'usp_resolver_solicitud_ingreso_grupo', N'usp_retirar_solicitud_ingreso_grupo', N'usp_consultar_solicitudes_ingreso_grupo_docente', N'usp_consultar_solicitudes_ingreso_estudiante', N'usp_consultar_destinatarios_solicitud_ingreso_grupo'));
DECLARE @aSol INT = (SELECT COUNT(*) FROM dbo.zz_archivo_SolicitudIngresoGrupo);
DECLARE @aNot INT = (SELECT COUNT(*) FROM dbo.zz_archivo_NotificacionSolicitudIngreso);
DECLARE @aPla INT = (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaSolicitudIngreso);
DECLARE @aMar INT = (SELECT COUNT(*) FROM dbo.zz_archivo_PlantillaMarcadorSolicitudIngreso);
DECLARE @cancel INT = (SELECT COUNT(*) FROM dbo.NotificacionSaliente WHERE codigoError = 'TIPO_NOTIFICACION_RETIRADO');
PRINT CONCAT('CULM001_A_UP13 SolicitudIngresoGrupo=', IIF(OBJECT_ID(N'dbo.SolicitudIngresoGrupo', N'U') IS NULL, 'retirada', 'PRESENTE'));
PRINT CONCAT('CULM001_A_UP13 SP_solicitud_presentes=', @spPresentes);
PRINT CONCAT('CULM001_A_UP13 archivo_solicitudes=', @aSol, ' archivo_notificaciones=', @aNot, ' archivo_plantillas=', @aPla, ' archivo_marcadores=', @aMar);
PRINT CONCAT('CULM001_A_UP13 notificaciones_canceladas=', @cancel);
GO
