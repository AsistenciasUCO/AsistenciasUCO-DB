USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION DOWN 15: CULM-001 B.1 - revierte la sesion cancelada, los dias festivos y la ventana con tolerancia
-- (CONTRACT §2.14). Idempotente y tolerante (se puede ejecutar dos veces).
--   1. DROP de los SP nuevos de B.1.
--   2. Restaura el texto anterior (copiado literal de la linea base 65a4998) de usp_validar_sesion_ventana_registro_interno,
--      usp_precargar_sesiones_grupo_interno, uv_cumplimiento_sesion_grupo, usp_consultar_sesiones_grupo_paginado y
--      usp_consultar_sesiones_facultad_paginado.
--   3. DROP de las vistas nuevas y de SesionCancelacion, CargaDiaFestivo, DiaFestivo y TipoCancelacionSesion (en ese
--      orden). Las sesiones canceladas vuelven a ser sesiones normales (sin registros: nunca pudieron tenerlos).
--   4. Borra los parametros de B.1 solo si valor = valorDefecto (no borra valores administrados), los mensajes de B.1 y
--      la plantilla SESION_CANCELADA del sistema (creadoPor NULL); las notificaciones pendientes de ese tipo pasan a
--      FALLIDA_DEFINITIVA con codigoError TIPO_NOTIFICACION_RETIRADO (patron DEC-010 / A-C1).
-- ============================================================================
PRINT 'MIGRACION 15 DOWN: SP de B.1';
GO
IF OBJECT_ID(N'dbo.usp_generar_sesiones_grupo_v2', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_generar_sesiones_grupo_v2];
GO
IF OBJECT_ID(N'dbo.usp_cancelar_sesion', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cancelar_sesion];
GO
IF OBJECT_ID(N'dbo.usp_consultar_destinatarios_sesion_cancelada', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_destinatarios_sesion_cancelada];
GO
IF OBJECT_ID(N'dbo.usp_cargar_dias_festivos', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cargar_dias_festivos];
GO
IF OBJECT_ID(N'dbo.usp_cargar_dias_festivos_automatico', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_cargar_dias_festivos_automatico];
GO
IF OBJECT_ID(N'dbo.usp_internal_cargar_dias_festivos', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_internal_cargar_dias_festivos];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_aplicar_festivos_grupo];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_periodo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_aplicar_festivos_periodo];
GO
IF OBJECT_ID(N'dbo.usp_aplicar_festivos_automatico', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_aplicar_festivos_automatico];
GO
IF OBJECT_ID(N'dbo.usp_internal_aplicar_festivos_grupos', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupos];
GO
IF OBJECT_ID(N'dbo.usp_internal_aplicar_festivos_grupo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupo];
GO
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_festivo_con_asistencia_paginado', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_sesiones_festivo_con_asistencia_paginado];
GO
IF OBJECT_ID(N'dbo.usp_consultar_dias_festivos', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_dias_festivos];
GO
IF OBJECT_ID(N'dbo.usp_consultar_carga_festivos_anio', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[usp_consultar_carga_festivos_anio];
GO

PRINT 'MIGRACION 15 DOWN: restaura usp_validar_sesion_ventana_registro_interno (linea base)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-01: ventana de registro ordinario de asistencia (cierre estricto, sin tolerancia).
--   * Solo se registra cuando fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin. El reloj autoritativo es el
--     del motor (UTC); nunca el del cliente ni el del backend.
--   * Solo una procedencia confirmada (UTC_V2, UTC_GENERADOR, UTC_OWNER) prueba que los DATETIME2 son instantes
--     UTC. NULL (INDETERMINADA) no permite escribir: no se supone zona horaria alguna.
--   * Lee la fila de dbo.Sesion con UPDLOCK + HOLDLOCK: invocado dentro de la transaccion del llamador, el
--     bloqueo se mantiene hasta su COMMIT/ROLLBACK, de modo que el horario no cambia entre esta validacion y la
--     escritura, y los lotes concurrentes de la misma sesion se serializan y evaluan el reloj despues de
--     obtener el bloqueo (una solicitud iniciada antes del cierre que llega despues del cierre se rechaza).
--   * Codigos: SES_007 (sesion no iniciada), SES_008 (sesion cerrada), SES_009 (horario indeterminado).
--   * No escribe. El llamador decide la reversion y el resultset canonico.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @existe              BIT = 0;
    DECLARE @fechaHoraInicio     DATETIME2;
    DECLARE @fechaHoraFin        DATETIME2;
    DECLARE @procedenciaTemporal NVARCHAR(24);
    DECLARE @instanteActualUtc   DATETIME2;

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

        -- PASO 2: Lectura bloqueada del horario y su procedencia (misma fila, una sola sentencia)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @existe = 1,
                @fechaHoraInicio = s.fechaHoraInicio,
                @fechaHoraFin = s.fechaHoraFin,
                @procedenciaTemporal = s.procedenciaTemporal
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF @existe = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_001',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Procedencia temporal confirmada (NULL o desconocida = INDETERMINADA)
        IF @estadoResultado = 1
           AND (@procedenciaTemporal IS NULL OR @procedenciaTemporal NOT IN (N'UTC_V2', N'UTC_GENERADOR', N'UTC_OWNER'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_009',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: Ventana [inicio, fin) contra el reloj UTC del motor, leído después de obtener el bloqueo
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();

            IF @instanteActualUtc < @fechaHoraInicio
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @fechaHoraFin
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
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
END;
GO

PRINT 'MIGRACION 15 DOWN: restaura usp_precargar_sesiones_grupo_interno (linea base)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F2 (2026-11-02): nucleo atomico de usp_precargar_sesiones_grupo. Alinea las sesiones FUTURAS del grupo con su horario:
--   * crea las sesiones que faltan, desde hoy (hora institucional) o desde el inicio del periodo si aun no empieza,
--     hasta el fin del periodo, sin duplicar las que ya existen (mismo grupo, inicio y fin);
--   * elimina las sesiones futuras GENERADAS (procedenciaTemporal = UTC_GENERADOR) que ya no encajan en el horario y no
--     tienen asistencia ni clasificacion. Nunca toca sesiones del pasado ni las creadas a mano por el docente.
-- No abre transaccion: la controla el SP publico (propia o savepoint). No modifica usp_generar_sesiones_grupo (congelado).
CREATE OR ALTER PROCEDURE [dbo].[usp_precargar_sesiones_grupo_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @sesionesCreadas         INT OUTPUT,
    @sesionesEliminadas      INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @fechaInicio          DATE;
    DECLARE @fechaFin             DATE;
    DECLARE @fechaHoy             DATE;
    DECLARE @fechaDesde           DATE;
    DECLARE @maxNumeroSesion      INT;
    DECLARE @fechaHoraLocalInexistente DATETIME2;

    DECLARE @slots TABLE (
        fecha       DATE      NOT NULL,
        inicioLocal DATETIME2 NOT NULL,
        finLocal    DATETIME2 NOT NULL,
        inicioUtc   DATETIME2 NULL,
        finUtc      DATETIME2 NULL
    );

    SELECT
        @sesionesCreadas = 0,
        @sesionesEliminadas = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validacion del identificador de correlacion obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Zona horaria institucional valida para convertir el horario local a UTC
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, valor)
            FROM dbo.CatalogoParametro
            WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;

            IF @zonaHorariaSqlServer IS NULL
               OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Franjas futuras del horario del grupo, desde hoy (o desde el inicio del periodo) hasta el fin del periodo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @fechaInicio = pa.fechaInicio, @fechaFin = pa.fechaFin
            FROM dbo.Grupo g
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto;

            SET @fechaHoy = CAST(@ahoraUtc AT TIME ZONE 'UTC' AT TIME ZONE @zonaHorariaSqlServer AS DATE);
            SET @fechaDesde = IIF(@fechaHoy > @fechaInicio, @fechaHoy, @fechaInicio);

            -- 1900-01-01 fue lunes: el resto de dividir los dias desde esa fecha entre 7 da el dia de la semana sin depender del idioma
            WITH fechas AS (
                SELECT fecha = @fechaDesde
                WHERE @fechaDesde <= @fechaFin
                UNION ALL
                SELECT DATEADD(DAY, 1, fecha) FROM fechas WHERE fecha < @fechaFin
            )
            INSERT INTO @slots (fecha, inicioLocal, finLocal)
            SELECT f.fecha,
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaInicio, 108)) AS DATETIME2),
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaFin, 108)) AS DATETIME2)
            FROM fechas f
            INNER JOIN dbo.Horario h ON h.grupo = @idGrupoDefecto
            INNER JOIN dbo.Dia d ON d.id = h.dia
            WHERE d.codigo = CASE DATEDIFF(DAY, '19000101', f.fecha) % 7
                                 WHEN 0 THEN 'LU' WHEN 1 THEN 'MA' WHEN 2 THEN 'MI' WHEN 3 THEN 'JU'
                                 WHEN 4 THEN 'VI' WHEN 5 THEN 'SA' ELSE 'DO' END
            OPTION (MAXRECURSION 0);

            -- Una hora local inexistente (salto de horario de verano) se desplaza en silencio: se aborta antes de escribir
            SELECT TOP 1 @fechaHoraLocalInexistente = x.horaLocal
            FROM (SELECT horaLocal = inicioLocal FROM @slots UNION ALL SELECT finLocal FROM @slots) x
            WHERE CAST(x.horaLocal AT TIME ZONE @zonaHorariaSqlServer AS DATETIME2) <> x.horaLocal
            ORDER BY x.horaLocal;

            IF @fechaHoraLocalInexistente IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_005', @p_param1 = @zonaHorariaSqlServer, @p_param2 = @fechaHoraLocalInexistente,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            UPDATE @slots
            SET inicioUtc = CAST(inicioLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2),
                finUtc = CAST(finLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2);

            -- Solo lo que aun no empezo: el pasado no se genera ni se toca
            DELETE FROM @slots WHERE inicioUtc <= @ahoraUtc;

            -- PASO 4: Sesiones futuras generadas que ya no encajan en el horario y no tienen asistencia ni clasificacion
            DELETE s
            FROM dbo.Sesion s
            WHERE s.grupo = @idGrupoDefecto
              AND s.fechaHoraInicio > @ahoraUtc
              AND s.procedenciaTemporal = N'UTC_GENERADOR'
              AND NOT EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin)
              AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion c WHERE c.sesion = s.id);
            SET @sesionesEliminadas = @@ROWCOUNT;

            -- PASO 5: Sesiones que faltan, con correlativo protegido contra carreras con usp_crear_sesion
            SELECT @maxNumeroSesion = MAX(numero) FROM dbo.Sesion WITH (UPDLOCK, HOLDLOCK) WHERE grupo = @idGrupoDefecto;

            INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
            SELECT NEWID(),
                   CONCAT(N'Sesi', NCHAR(243), N'n ', CAST(n.numero AS NVARCHAR(10))),
                   n.numero,
                   UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6)),
                   DATEDIFF(WEEK, @fechaInicio, n.fecha) + 1,
                   @idGrupoDefecto,
                   n.inicioUtc,
                   n.finUtc,
                   N'UTC_GENERADOR'
            FROM (
                SELECT x.fecha, x.inicioUtc, x.finUtc,
                       numero = COALESCE(@maxNumeroSesion, 0) + ROW_NUMBER() OVER (ORDER BY x.inicioUtc)
                FROM @slots x
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.Sesion e
                    WHERE e.grupo = @idGrupoDefecto AND e.fechaHoraInicio = x.inicioUtc AND e.fechaHoraFin = x.finUtc)
            ) n;
            SET @sesionesCreadas = @@ROWCOUNT;
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

PRINT 'MIGRACION 15 DOWN: restaura uv_cumplimiento_sesion_grupo (linea base)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        idPrograma = gp.idPrograma,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id), 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = s.idGrupo
GO

PRINT 'MIGRACION 15 DOWN: restaura usp_consultar_sesiones_grupo_paginado (linea base)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_grupo_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Búsqueda, programación e historial paginado de sesiones de clase para un grupo
--   académico consumiendo uv_auth_sesion. Aplica preservación estricta de SESSION_CONTEXT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_grupo_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @fechaDesde              DATETIME2        = NULL,
    @fechaHasta              DATETIME2        = NULL,
    @numeroSemana            INT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroFechaDesde DATETIME2 = @fechaDesde;
    DECLARE @filtroFechaHasta DATETIME2 = @fechaHasta;
    DECLARE @filtroSemana INT = @numeroSemana;

    -- Control de diagnóstico y contexto
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;
    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- Paso 1: Validación obligatoria de identificador de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- Paso 2: Validación obligatoria de usuario ejecutor
        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        -- Paso 3: Validación obligatoria de idGrupo
        IF @estadoResultado = 1 AND (@idGrupoDefecto IS NULL OR @idGrupoDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Grupo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Establecer identidad temporal en contexto para uv_auth_sesion
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta optimizada de sesiones sobre la vista securizada
        SELECT
            s.id,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            s.nombre,
            s.numero,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            COUNT(1) OVER() AS totalRegistros
        FROM dbo.uv_auth_sesion s
        WHERE s.idGrupo = @idGrupoDefecto
          AND (@filtroFechaDesde IS NULL OR s.fechaHoraInicio >= @filtroFechaDesde)
          AND (@filtroFechaHasta IS NULL OR s.fechaHoraFin <= @filtroFechaHasta)
          AND (@filtroSemana IS NULL OR s.numeroSemana = @filtroSemana)
        ORDER BY s.fechaHoraInicio ASC, s.numero ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar el contexto previo
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

PRINT 'MIGRACION 15 DOWN: restaura usp_consultar_sesiones_facultad_paginado (linea base)';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_facultad_paginado (HU145 cronograma de sesiones de la facultad)
--
-- Sesiones programadas en los grupos de la facultad del decano ejecutor, ordenadas por fecha, con filtro
-- opcional por rango de fechas (dias completos, ambos inclusive) y programa.
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas
-- de los comandos. Las fallas de paginacion se propagan con THROW (DBCODE=PAG_001).
-- Ambito: uv_auth_sesion / uv_auth_grupo (fail-closed) restringidas a los programas de las facultades cuyo
-- decano es el ejecutor.
-- SESSION_CONTEXT: se captura el previo y SIEMPRE se restaura (exito y error).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_facultad_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @fechaDesde         DATE             = NULL,
    @fechaHasta         DATE             = NULL,
    @idPrograma         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = TRY_CAST(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO') AS INT);
    DECLARE @inicio               DATETIME2 = CAST(@fechaDesde AS DATETIME2);
    DECLARE @finExclusivo         DATETIME2 = DATEADD(DAY, 1, CAST(@fechaHasta AS DATETIME2));
    DECLARE @offset               INT;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    DECLARE @contextoPrevio SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (@idUsuarioDefecto IS NULL OR @idUsuarioDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'UsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
           AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
                OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PAG_001',
                @p_param1 = @numeroPagina,
                @p_param2 = @tamanoPagina,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        SET @offset = (@numeroPagina - 1) * @tamanoPagina;

        EXEC dbo.usp_establecer_contexto_usuario_ejecutor
            @p_idUsuario = @idUsuarioDefecto;

        SELECT
            s.id,
            s.nombre,
            s.codigo,
            s.numeroSemana,
            s.fechaHoraInicio,
            s.fechaHoraFin,
            s.idGrupo,
            s.codigoGrupo,
            s.nombreGrupo,
            g.idAsignatura,
            g.nombreAsignatura,
            pr.id                   AS idPrograma,
            pr.nombrePrograma,
            COUNT(*) OVER()         AS totalRegistros
        FROM dbo.uv_auth_sesion s
        INNER JOIN dbo.uv_auth_grupo g ON g.id = s.idGrupo
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = s.idGrupo
        INNER JOIN dbo.uv_programa pr ON pr.id = gp.idPrograma
        WHERE pr.idFacultad IN (
                SELECT f.id FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano
                WHERE d.usuario = @idUsuarioDefecto
              )
          AND (@idPrograma IS NULL OR pr.id = @idPrograma)
          AND (@inicio IS NULL OR s.fechaHoraInicio >= @inicio)
          AND (@finExclusivo IS NULL OR s.fechaHoraInicio < @finExclusivo)
        ORDER BY s.fechaHoraInicio ASC, s.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

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

PRINT 'MIGRACION 15 DOWN: vistas y tablas de B.1';
GO
IF OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NOT NULL DROP VIEW [dbo].[uv_sesion_estado];
GO
IF OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NOT NULL DROP VIEW [dbo].[uv_carga_dia_festivo];
GO
IF OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NOT NULL DROP VIEW [dbo].[uv_dia_festivo];
GO
IF OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NOT NULL DROP VIEW [dbo].[uv_tipo_cancelacion_sesion];
GO
IF OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NOT NULL DROP TABLE [dbo].[SesionCancelacion];
GO
IF OBJECT_ID(N'dbo.CargaDiaFestivo', N'U') IS NOT NULL DROP TABLE [dbo].[CargaDiaFestivo];
GO
IF OBJECT_ID(N'dbo.DiaFestivo', N'U') IS NOT NULL DROP TABLE [dbo].[DiaFestivo];
GO
IF OBJECT_ID(N'dbo.TipoCancelacionSesion', N'U') IS NOT NULL DROP TABLE [dbo].[TipoCancelacionSesion];
GO

PRINT 'MIGRACION 15 DOWN: parametros, mensajes, plantilla y notificaciones de B.1';
GO
SET XACT_ABORT ON;
DELETE FROM dbo.CatalogoParametro
WHERE ((grupo = 'FESTIVOS' AND clave IN ('HABILITADO', 'PROVEEDOR_PRINCIPAL', 'ORDEN_RESPALDO', 'FUENTES_VALIDAS', 'URL_CALENDARIOS_NACIONALES',
                                         'URL_FERIADOS_IO', 'NOMBRE_SECRETO_FERIADOS_IO', 'TIMEOUT_SEGUNDOS', 'ANIOS_ADELANTE', 'ANIO_MINIMO',
                                         'ANIO_MAXIMO', 'MINIMO_POR_ANIO', 'MAXIMO_POR_ANIO', 'PREFIJO_MOTIVO_CANCELACION', 'ATRIBUCION_TEXTO',
                                         'ATRIBUCION_URL'))
       OR (grupo = 'SESION' AND clave IN ('MOTIVO_CANCELACION_LONGITUD_MINIMA', 'MOTIVO_CANCELACION_LONGITUD_MAXIMA')))
  AND ISNULL(valor, N'') = ISNULL(valorDefecto, N'');

DELETE FROM dbo.CatalogoMensajeUsuario
WHERE codigo IN ('SES_010', 'SES_011', 'SES_012', 'SES_013', 'SES_014', 'SES_016', 'FES_001', 'FES_002', 'FES_003', 'FES_004', 'FES_005',
                 'FES_006', 'FES_007', 'FES_008', 'FES_009', 'FES_010');
DELETE FROM dbo.CatalogoMensajeTecnico
WHERE codigo IN ('SES_010', 'SES_011', 'SES_012', 'SES_013', 'SES_014', 'SES_016', 'FES_001', 'FES_002', 'FES_003', 'FES_004', 'FES_005',
                 'FES_006', 'FES_007', 'FES_008', 'FES_009', 'FES_010');

-- Notificaciones pendientes (estado no terminal) del tipo retirado: FALLIDA_DEFINITIVA, nunca DELETE (DEC-010 / A-C1)
DECLARE @idFallidaDefinitiva UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.EstadoNotificacion WHERE codigo = 'FALLIDA_DEFINITIVA');
IF @idFallidaDefinitiva IS NOT NULL
    UPDATE n
    SET n.idEstado = @idFallidaDefinitiva,
        n.codigoError = 'TIPO_NOTIFICACION_RETIRADO',
        n.detalleError = N'CULM-001 B.1 revertido (migracion 15 down): plantilla SESION_CANCELADA retirada.'
    FROM dbo.NotificacionSaliente n
    INNER JOIN dbo.EstadoNotificacion e ON e.id = n.idEstado
    WHERE n.tipo = 'SESION_CANCELADA' AND e.esTerminal = 0;

DELETE FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_CANCELADA' AND creadoPor IS NULL;
IF NOT EXISTS (SELECT 1 FROM dbo.PlantillaNotificacion WHERE tipo = 'SESION_CANCELADA')
    DELETE FROM dbo.PlantillaNotificacionMarcador WHERE tipo = 'SESION_CANCELADA';
GO

DECLARE @parametrosVentana INT = (SELECT COUNT(*) FROM sys.parameters WHERE object_id = OBJECT_ID(N'dbo.usp_validar_sesion_ventana_registro_interno'));
PRINT CONCAT('MIGRACION 15 DOWN OK | SesionCancelacion=', IIF(OBJECT_ID(N'dbo.SesionCancelacion', N'U') IS NULL, 'retirada', 'presente'),
             ' | ventana parametros=', @parametrosVentana, ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
