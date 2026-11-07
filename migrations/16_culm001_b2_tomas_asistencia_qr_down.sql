-- ============================================================================
-- CULM-001 B.2 - Migracion 16 DOWN (CONTRACT §2.14, DEC-011): colapsa las asistencias a una toma y retira B.2.
-- Requiere la variable sqlcmd CONFIRMAR_COLAPSO (-v CONFIRMAR_COLAPSO=0|1 o :setvar antes de :r). Sin ella sqlcmd se detiene
-- antes de cambiar nada (:on error exit).
--   1. Si alguna asistencia tiene detalles en tomas con numero > 1 y CONFIRMAR_COLAPSO <> 1: THROW 50011 (sin cambios).
--      Con confirmacion: por cada asistencia conserva un solo detalle (el de la toma de menor numero con SJC si existe, si no
--      el de menor numero) y archiva los descartados en zz_archivo_DetalleAsistencia_culm001_b2 (sin FKs, patron DEC-010).
--   2. Restaura el texto anterior a B.2 (version B.1) de usp_sincronizar_asistencia_estudiante_interno, de las vistas
--      uv_sesion_estado / uv_cumplimiento_sesion_grupo / uv_resumen_asistencia_estudiante_grupo y de los consumidores de §2.9
--      (incluido usp_ejecutar_cierre_masivo_periodo con COUNT(da.id)); DROP de los SP, funciones y vistas de B.2.
--   3. DROP TokenAsistenciaToma; FK, UX e IX de toma; recrea UX_DetalleAsistencia_Asistencia; DROP de las columnas toma,
--      registradoPorEstudiante y fechaRegistroUtc; DROP SEQUENCE; DROP TomaAsistencia, EstadoTomaAsistencia, ModoTomaAsistencia.
--   4. Borra parametros (solo si valor = valorDefecto) y mensajes de B.2. ASISTENCIA_QR/LIMITE_ESTUDIANTE_POR_MINUTO pertenece a la
--      semilla 29: vuelve a 5 si no fue administrado.
-- No toca los permisos de usp_registrar_asistencia_estudiante_autonomo (B no los cambia). Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Colapso a una toma por asistencia
-- ---------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.DetalleAsistencia', N'toma') IS NOT NULL
BEGIN
    DECLARE @confirmar NVARCHAR(10) = N'$(CONFIRMAR_COLAPSO)';
    DECLARE @hayVarias BIT = 0;
    EXEC sys.sp_executesql N'SELECT @r = IIF(EXISTS (SELECT 1 FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma WHERE t.numero > 1
                                                    AND EXISTS (SELECT 1 FROM dbo.DetalleAsistencia d2 WHERE d2.asistencia = da.asistencia AND d2.id <> da.id)), 1, 0);',
        N'@r BIT OUTPUT', @r = @hayVarias OUTPUT;
    IF @hayVarias = 1 AND @confirmar <> N'1'
        THROW 50011, 'CULM001_B2_DOWN: hay asistencias con detalles en varias tomas; ejecute con CONFIRMAR_COLAPSO = 1 para colapsar a una toma.', 1;
    IF @hayVarias = 1
    BEGIN
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql N'
            ;WITH orden AS (
                SELECT da.id, n = ROW_NUMBER() OVER (PARTITION BY da.asistencia ORDER BY IIF(rc.codigo = N''SJC'', 0, 1), t.numero, da.id)
                FROM dbo.DetalleAsistencia da
                INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma
                INNER JOIN dbo.RazonCausa rc ON rc.id = da.razonCausa
            )
            SELECT da.id, da.codigo, da.asistencia, da.asistio, da.razonCausa, da.fechaHoraInicio, da.fechaHoraFin, da.toma,
                   da.registradoPorEstudiante, da.fechaRegistroUtc, fechaArchivoUtc = SYSUTCDATETIME()
            INTO #descartados
            FROM dbo.DetalleAsistencia da INNER JOIN orden o ON o.id = da.id
            WHERE o.n > 1;
            IF OBJECT_ID(N''dbo.zz_archivo_DetalleAsistencia_culm001_b2'', N''U'') IS NULL
                SELECT * INTO dbo.zz_archivo_DetalleAsistencia_culm001_b2 FROM #descartados WHERE 1 = 0;
            INSERT INTO dbo.zz_archivo_DetalleAsistencia_culm001_b2 SELECT * FROM #descartados;
            DELETE da FROM dbo.DetalleAsistencia da INNER JOIN #descartados d ON d.id = da.id;';
        COMMIT TRANSACTION;
    END
END
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Texto anterior a B.2 (version B.1) de los objetos modificados y retiro de los programables de B.2
-- ---------------------------------------------------------------------------------------------------------------
-- schema/stored-procedures/usp_sincronizar_asistencia_estudiante_interno.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_asistencia_estudiante_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(5),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    -- 1. Estandarización e inicialización de variables utilizando funciones de catálogo (Sin ISNULL)
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoEstadoDefecto     NVARCHAR(5) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstado, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @codigoCanonico          NVARCHAR(5);

    DECLARE @idGrupo                 UNIQUEIDENTIFIER;
    DECLARE @fechaInicioSesion       DATETIME2;
    DECLARE @fechaFinSesion          DATETIME2;
    DECLARE @idEstudianteGrupo        UNIQUEIDENTIFIER;
    DECLARE @idRazonCausa            UNIQUEIDENTIFIER;
    DECLARE @asistio                 BIT;
    DECLARE @idAsistencia            UNIQUEIDENTIFIER;
    DECLARE @idDetalleAsistencia     UNIQUEIDENTIFIER;
    DECLARE @nuevoCodigo             INT;

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

        -- PASO 2: Verificación de la sesión de clase y obtención de franja horaria
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idGrupo = grupo,
                @fechaInicioSesion = fechaHoraInicio,
                @fechaFinSesion = fechaHoraFin
            FROM dbo.Sesion
            WHERE id = @idSesionDefecto;

            IF @idGrupo IS NULL
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

        -- PASO 3: Verificación de la matrícula activa del estudiante en el grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @idEstudianteGrupo = eg.id
            FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.EstadoEstudianteGrupo eeg ON eeg.id = eg.estado
            WHERE eg.estudiante = @idEstudianteDefecto 
              AND eg.grupo = @idGrupo
              AND eeg.codigo = 'A';

            IF @idEstudianteGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'EST_004',
                    @p_param1 = @idEstudianteDefecto,
                    @p_param2 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Resolución de la razón de causa/asistencia en dbo.RazonCausa.
        -- RazonCausa es un CATALOGO CERRADO: un código desconocido NO crea filas (RC_001, sin escritura).
        IF @estadoResultado = 1
        BEGIN
            SET @codigoCanonico = @codigoEstadoDefecto;

            SELECT TOP 1 @idRazonCausa = id
            FROM dbo.RazonCausa
            WHERE codigo = @codigoCanonico
              AND codigo IN ('AN', 'SJC', 'EX');

            IF @idRazonCausa IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'RC_001',
                    @p_param1 = @codigoEstadoDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @asistio = CASE WHEN @codigoCanonico = 'AN' THEN 1 ELSE 0 END;
            END
        END

        -- PASO 5: Sincronización de cabecera y detalle de asistencia
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia WITH (UPDLOCK, HOLDLOCK)
            WHERE estudianteGrupo = @idEstudianteGrupo 
              AND sesion = @idSesionDefecto;

            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            SELECT TOP 1 @idDetalleAsistencia = id
            FROM dbo.DetalleAsistencia WITH (UPDLOCK, HOLDLOCK)
            WHERE asistencia = @idAsistencia;

            IF @idDetalleAsistencia IS NULL
            BEGIN
                SELECT @nuevoCodigo = dbo.ufn_obtener_parametro_int(MAX(codigo), 'GENERAL', 'ENTERO_CERO') + 1
                FROM dbo.DetalleAsistencia WITH (UPDLOCK, HOLDLOCK);
                SET @idDetalleAsistencia = NEWID();

                INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
                VALUES (@idDetalleAsistencia, @nuevoCodigo, @idAsistencia, @asistio, @idRazonCausa, @fechaInicioSesion, @fechaFinSesion);
            END
            ELSE
            BEGIN
                UPDATE dbo.DetalleAsistencia
                SET asistio = @asistio,
                    razonCausa = @idRazonCausa,
                    fechaHoraInicio = @fechaInicioSesion,
                    fechaHoraFin = @fechaFinSesion
                WHERE id = @idDetalleAsistencia;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asistencia Estudiante',
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

-- schema/stored-procedures/usp_validar_sesion_ventana_registro_interno.sql (version anterior a B.2)
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
-- CULM-001 B.1 (CONTRACT §2.7.1):
--   * @toleranciaMinutos / @margenMinutos (opcionales): ventana [inicio - tolerancia, fin + margen). NULL o negativos = 0,
--     es decir, la regla estricta de SES-01; los llamadores de 5 parametros (lote congelado, autonomo) no cambian.
--     Los valores los lee el LLAMADOR (ASISTENCIA/TOLERANCIA_MINUTOS y ASISTENCIA/MARGEN_RETARDO_MINUTOS).
--   * PASO 2.5 (todos los llamadores): una sesion con dbo.SesionCancelacion se rechaza con SES_010. Se lee despues del
--     UPDLOCK + HOLDLOCK sobre dbo.Sesion, el mismo bloqueo que toma usp_cancelar_sesion: registro y cancelacion se
--     serializan.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_sesion_ventana_registro_interno]
(
    @idSesion                UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @toleranciaMinutos       INT = NULL,
    @margenMinutos           INT = NULL
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
    DECLARE @toleranciaAplicada  INT = IIF(@toleranciaMinutos IS NULL OR @toleranciaMinutos < 0, 0, @toleranciaMinutos);
    DECLARE @margenAplicado      INT = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    DECLARE @aperturaUtc         DATETIME2;
    DECLARE @cierreUtc           DATETIME2;
    DECLARE @detalleVentana      NVARCHAR(200) = IIF(@toleranciaMinutos IS NULL AND @margenMinutos IS NULL,
                                                     dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
                                                     CONCAT(' Tolerancia: ', @toleranciaAplicada, ' min; margen: ', @margenAplicado, ' min.'));

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

        -- PASO 2.5 (CULM-001 B.1): sesion cancelada => SES_010 (lectura despues del bloqueo de la fila de dbo.Sesion)
        IF @estadoResultado = 1
           AND EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_010',
                @p_param1 = @idSesionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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

        -- PASO 4: Ventana [inicio - tolerancia, fin + margen) contra el reloj UTC del motor, leído después de obtener
        --         el bloqueo. Sin tolerancia ni margen es la ventana estricta [inicio, fin) de SES-01.
        IF @estadoResultado = 1
        BEGIN
            SET @instanteActualUtc = SYSUTCDATETIME();
            SET @aperturaUtc = DATEADD(MINUTE, -@toleranciaAplicada, @fechaHoraInicio);
            SET @cierreUtc = DATEADD(MINUTE, @margenAplicado, @fechaHoraFin);

            IF @instanteActualUtc < @aperturaUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_007',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE IF @instanteActualUtc >= @cierreUtc
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_008',
                    @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, @detalleVentana, ' Correlacion: ', @idCorrelacionDefecto);
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

-- schema/stored-procedures/usp_cancelar_sesion.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cancelar_sesion (CULM-001 B.1, HU047; CONTRACT §2.7.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idSesion, idGrupo, fechaCancelacionUtc,
-- totalEstudiantesActivos (NULL si estadoResultado = 0).
--
-- El docente titular cancela una sesion con justificacion. Se puede cancelar una sesion futura o una sin asistencia
-- registrada (tambien pasada) ([SUPUESTO-B-10]). Con asistencia: SES_012 si la ventana [.., fin + MARGEN) no ha
-- terminado; SES_016 si ya termino (la correccion se hace por reclamo). Doble cancelacion: SES_011 (no idempotente,
-- se conserva el motivo original). Motivo recortado fuera de SESION/MOTIVO_CANCELACION_LONGITUD_MINIMA..MAXIMA: SES_013.
-- El tipo de cancelacion se resuelve por la bandera TipoCancelacionSesion.esAutomatica = 0 (sin literales).
-- Transaccion propia o SAVE TRANSACTION; la fila de dbo.Sesion se bloquea (UPDLOCK, HOLDLOCK) antes de leer la
-- cancelacion y la asistencia, el mismo bloqueo que toma la ventana de registro: registro y cancelacion se serializan.
-- Las ramas de rechazo no escriben: solo confirman la transaccion propia (sin ROLLBACK, compatible con INSERT ... EXEC).
-- @motivo se declara NVARCHAR(4000) (no 500) para que un motivo de mas de 500 caracteres llegue entero y se rechace con
-- SES_013 en lugar de truncarse en silencio (B1-CAN-03); la columna SesionCancelacion.motivo sigue siendo NVARCHAR(500).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cancelar_sesion]
(
    @idSesion          UNIQUEIDENTIFIER,
    @motivo            NVARCHAR(4000),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @motivoLimpio      NVARCHAR(MAX) = LTRIM(RTRIM(@motivo));
    DECLARE @longitudMinima    INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MINIMA');
    DECLARE @longitudMaxima    INT = dbo.ufn_obtener_parametro_int(NULL, 'SESION', 'MOTIVO_CANCELACION_LONGITUD_MAXIMA');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoMatriculaActiva NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idTipoManual      UNIQUEIDENTIFIER;
    DECLARE @codigoTipoManual  NVARCHAR(20);
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @fechaHoraFin      DATETIME2;
    DECLARE @fechaCancelacion  DATETIME2(0) = NULL;
    DECLARE @totalActivos      INT = NULL;
    DECLARE @codigoRechazo     VARCHAR(20) = NULL;
    DECLARE @longitudMinimaTexto NVARCHAR(20);
    DECLARE @longitudMaximaTexto NVARCHAR(20);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE)
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

        -- PASO 3: sesion existente (SES_001)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: titularidad del docente sobre la sesion (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idSesionDefecto,
                @tipoEntidadPadre = 'SESION',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: motivo recortado dentro de los limites parametrizados (SES_013)
        IF @estadoResultado = 1
           AND (@motivoLimpio IS NULL OR @longitudMinima IS NULL OR @longitudMaxima IS NULL
                OR LEN(@motivoLimpio) < @longitudMinima OR LEN(@motivoLimpio) > @longitudMaxima)
        BEGIN
            SET @longitudMinimaTexto = CONVERT(NVARCHAR(20), @longitudMinima);
            SET @longitudMaximaTexto = CONVERT(NVARCHAR(20), @longitudMaxima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_013', @p_param1 = @longitudMinimaTexto, @p_param2 = @longitudMaximaTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: tipo manual de cancelacion por bandera de catalogo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoManual = t.id, @codigoTipoManual = t.codigo
            FROM dbo.uv_tipo_cancelacion_sesion t
            WHERE t.esAutomatica = 0;

            IF @idTipoManual IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 0)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 7: escritura atomica bajo el bloqueo de la sesion
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_cancelar_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @idGrupo = s.grupo, @fechaHoraFin = s.fechaHoraFin
            FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.id = @idSesionDefecto;

            IF EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesionDefecto)
                SET @codigoRechazo = 'SES_011';
            ELSE IF EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = @idSesionDefecto)
                SET @codigoRechazo = IIF(SYSUTCDATETIME() >= DATEADD(MINUTE, IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos), @fechaHoraFin),
                                         'SES_016', 'SES_012');

            IF @codigoRechazo IS NULL
            BEGIN
                SET @fechaCancelacion = SYSUTCDATETIME();

                INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
                VALUES (@idSesionDefecto, @idTipoManual, @motivoLimpio, NULL, @idUsuarioEjecutorDefecto, @fechaCancelacion, @idCorrelacionDefecto);

                SELECT @totalActivos = COUNT(1)
                FROM dbo.uv_estudiante_grupo eg
                WHERE eg.idGrupo = @idGrupo AND eg.codigoEstadoEstudiante = @codigoMatriculaActiva;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_014', @p_param1 = @idSesionDefecto, @p_param2 = @codigoTipoManual,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @idSesionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera el bloqueo).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_cancelar_sesion;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

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
        estadoResultado         = @estadoResultado,
        idSesion                = IIF(@estadoResultado = 1, @idSesionDefecto, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        fechaCancelacionUtc     = IIF(@estadoResultado = 1, @fechaCancelacion, NULL),
        totalEstudiantesActivos = IIF(@estadoResultado = 1, @totalActivos, NULL);
END;
GO

-- schema/stored-procedures/usp_internal_aplicar_festivos_grupo.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_aplicar_festivos_grupo (CULM-001 B.1; CONTRACT §2.7.5) — nucleo, sin EXECUTE para el rol runtime.
--
-- Marca como canceladas por FESTIVO las sesiones del grupo cuya fecha LOCAL (TIEMPO/ZONA_HORARIA_SQLSERVER) es un
-- DiaFestivo activo. No abre transaccion: la controla el llamador (publico, generacion v2 o precarga).
--   * Solo sesiones con procedencia temporal confirmada y sin SesionCancelacion (idempotente).
--   * @soloFuturas = 1 (mantenimiento de grupos ya creados): solo fechaHoraInicio > SYSUTCDATETIME();
--     @soloFuturas = 0 (generacion y precarga): toda sesion nueva en festivo nace cancelada ([SUPUESTO-B-11]).
--   * Una candidata con Asistencia no se toca ([SUPUESTO-B-10]): se cuenta en @sesionesConAsistencia y se reporta con
--     usp_consultar_sesiones_festivo_con_asistencia_paginado. No se usa la tabla temporal opcional
--     #sesionesFestivoConAsistencia del contrato: sus SP publicos (que tambien llaman a este nucleo) deben seguir siendo
--     describibles por sp_describe_first_result_set (PUBLIC_CANONICAL_RESULTSET). B.2 agrega la condicion sobre TomaAsistencia.
--   * Tipo por bandera TipoCancelacionSesion.esAutomatica = 1; motivo = FESTIVOS/PREFIJO_MOTIVO_CANCELACION + nombre.
-- Bloqueo: dbo.Sesion WITH (UPDLOCK, HOLDLOCK) sobre las candidatas antes de escribir (mismo orden que la ventana).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupo]
(
    @idGrupo                  UNIQUEIDENTIFIER,
    @soloFuturas              BIT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @prefijoMotivo        NVARCHAR(200)    = dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION');
    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @idTipoAutomatico     UNIQUEIDENTIFIER;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
    DECLARE @mensajeUsuarioExito  NVARCHAR(4000);

    DECLARE @candidatas TABLE (
        idSesion        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        idDiaFestivo    UNIQUEIDENTIFIER NOT NULL,
        fecha           DATE             NOT NULL,
        nombreFestivo   NVARCHAR(120)    NOT NULL,
        tieneAsistencia BIT              NOT NULL
    );

    SELECT
        @sesionesCanceladas = 0,
        @sesionesConAsistencia = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: zona horaria institucional valida (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, p.valor)
            FROM dbo.uv_parametro p
            WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER' AND p.estaActivo = 1;

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

        -- PASO 3: tipo automatico por bandera de catalogo (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoAutomatico = t.id FROM dbo.uv_tipo_cancelacion_sesion t WHERE t.esAutomatica = 1;

            IF @idTipoAutomatico IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 1)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: candidatas bloqueadas (fecha local en un festivo activo, sin cancelacion previa)
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @candidatas (idSesion, idDiaFestivo, fecha, nombreFestivo, tieneAsistencia)
            SELECT  s.id, df.id, df.fecha, df.nombre,
                    CAST(IIF(EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id), 1, 0) AS BIT)
            FROM    dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.DiaFestivo df
            ON      df.estaActivo = 1
            AND     df.fecha = CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)
            WHERE   s.grupo = @idGrupoDefecto
              AND   s.procedenciaTemporal IS NOT NULL
              AND   (@soloFuturas = 0 OR s.fechaHoraInicio > @ahoraUtc)
              AND   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id);

            SET @sesionesConAsistencia = (SELECT COUNT(1) FROM @candidatas WHERE tieneAsistencia = 1);

            INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
            SELECT  c.idSesion, @idTipoAutomatico, LEFT(CONCAT(@prefijoMotivo, c.nombreFestivo), 500), c.idDiaFestivo,
                    @idUsuarioEjecutor, SYSUTCDATETIME(), @idCorrelacionDefecto
            FROM    @candidatas c
            WHERE   c.tieneAsistencia = 0;
            SET @sesionesCanceladas = @@ROWCOUNT;

            -- FES_008: usuario (canceladas, con asistencia); tecnico (grupo)
            SELECT @p1 = CONVERT(NVARCHAR(20), @sesionesCanceladas), @p2 = CONVERT(NVARCHAR(20), @sesionesConAsistencia);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioExito OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @p1 = CONVERT(NVARCHAR(36), @idGrupoDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, N' Canceladas: ', @sesionesCanceladas,
                                                  N'. Con asistencia: ', @sesionesConAsistencia, N'. Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SELECT @estadoResultado = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0;
    END CATCH
END;
GO

-- schema/stored-procedures/usp_precargar_sesiones_grupo_interno.sql (version anterior a B.2)
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
-- CULM-001 B.1 (CONTRACT §2.7.6): al final aplica los festivos (usp_internal_aplicar_festivos_grupo, @soloFuturas = 0)
-- en la misma transaccion del llamador: toda sesion creada en un dia festivo nace cancelada. Una sesion futura que se
-- borra porque ya no encaja en el horario pierde antes su SesionCancelacion. Las canceladas que siguen encajando no se
-- borran ni se recrean (idempotencia por grupo, inicio y fin). B.2 agrega la condicion NOT EXISTS TomaAsistencia.
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
    DECLARE @sesionesCanceladasFestivo INT = 0;
    DECLARE @sesionesFestivoConAsistencia INT = 0;
    DECLARE @sesionesEliminables TABLE (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

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

            -- PASO 4: Sesiones futuras generadas que ya no encajan en el horario y no tienen asistencia ni clasificacion.
            --         CULM-001 B.1: antes se borra su SesionCancelacion (una sesion que deja de existir pierde su cancelacion).
            INSERT INTO @sesionesEliminables (id)
            SELECT s.id
            FROM dbo.Sesion s
            WHERE s.grupo = @idGrupoDefecto
              AND s.fechaHoraInicio > @ahoraUtc
              AND s.procedenciaTemporal = N'UTC_GENERADOR'
              AND NOT EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin)
              AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion c WHERE c.sesion = s.id);

            DELETE sc
            FROM dbo.SesionCancelacion sc
            INNER JOIN @sesionesEliminables e ON e.id = sc.sesion;

            DELETE s
            FROM dbo.Sesion s
            INNER JOIN @sesionesEliminables e ON e.id = s.id;
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

            -- PASO 6 (CULM-001 B.1): festivos de las sesiones del grupo, en la misma transaccion del llamador
            EXEC dbo.usp_internal_aplicar_festivos_grupo
                @idGrupo = @idGrupoDefecto,
                @soloFuturas = 0,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = NULL,
                @sesionesCanceladas = @sesionesCanceladasFestivo OUTPUT,
                @sesionesConAsistencia = @sesionesFestivoConAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
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

-- schema/stored-procedures/usp_consultar_sesiones_festivo_con_asistencia_paginado.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_sesiones_festivo_con_asistencia_paginado (CULM-001 B.1; CONTRACT §2.7.5, §3.2.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, READ_QUERY_RESULTSET (THROW 51000 ante validacion fallida).
-- Sesiones de la institucion del ADMINISTRADOR cuya fecha local cae en un festivo activo del anio y que NO se
-- cancelaron porque tienen asistencia registrada ("se reportan", §3.7 del prompt).
-- Filas: idSesion, idGrupo, nombreGrupo, nombreAsignatura, nombreDocente, fechaHoraInicio, fecha, nombreFestivo,
-- totalTomas (0 en B.1: B.2 cuenta TomaAsistencia), totalRegistrosAsistencia (cabeceras de asistencia de la sesion)
-- y totalRegistros (COUNT(1) OVER(), total de la consulta para la paginacion).
-- Paginacion: @numeroPagina >= 1 y @tamanoPagina entre 1 y PAGINACION/TAMANO_MAXIMO (PAG_001).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_sesiones_festivo_con_asistencia_paginado]
(
    @idUsuarioEjecutor UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @anio              INT,
    @numeroPagina      INT = 1,
    @tamanoPagina      INT = 20
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @tamanoMaximo         INT = dbo.ufn_obtener_parametro_int(NULL, 'PAGINACION', 'TAMANO_MAXIMO');
    DECLARE @zonaHorariaSqlServer SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
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

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @anio IS NULL)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor/anio',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'ADMINISTRADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1
       AND (@numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1
            OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo)
    BEGIN
        SELECT @p1 = CONVERT(NVARCHAR(20), @numeroPagina), @p2 = CONVERT(NVARCHAR(20), @tamanoPagina);
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
        THROW 51000, @mensajeTecnicoResultado, 1;

    SET @offset = (@numeroPagina - 1) * @tamanoPagina;

    SELECT
        idSesion                 = se.idSesion,
        idGrupo                  = se.idGrupo,
        nombreGrupo              = CAST(CONCAT(N'G', FORMAT(g.codigo, '00'), N' de ', g.nombreAsignatura) AS NVARCHAR(300)),
        nombreAsignatura         = g.nombreAsignatura,
        nombreDocente            = CAST(di.nombreCompleto AS NVARCHAR(400)),
        fechaHoraInicio          = se.fechaHoraInicio,
        fecha                    = df.fecha,
        nombreFestivo            = df.nombre,
        totalTomas               = CAST(0 AS INT),
        totalRegistrosAsistencia = asis.total,
        totalRegistros           = COUNT(1) OVER()
    FROM dbo.uv_sesion_estado se
    INNER JOIN dbo.uv_dia_festivo df
    ON      df.estaActivo = 1 AND df.anio = @anio
    AND     df.fecha = CAST((se.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)
    INNER JOIN dbo.uv_grupo g               ON g.id = se.idGrupo
    INNER JOIN dbo.uv_periodo_academico pa  ON pa.id = g.idPeriodoAcademico
    INNER JOIN dbo.uv_docente_identidad di  ON di.id = g.idDocente
    CROSS APPLY (SELECT total = COUNT(1) FROM dbo.uv_asistencia a WHERE a.idSesion = se.idSesion) asis
    WHERE se.estaCancelada = 0
      AND se.procedenciaTemporal IS NOT NULL
      AND asis.total > 0
      AND pa.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioDefecto)
    ORDER BY se.fechaHoraInicio ASC, se.idSesion ASC
    OFFSET @offset ROWS
    FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- schema/stored-procedures/usp_resolver_solicitud_revision_asistencia.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- SES-04: resolucion del reclamo de inasistencia por el docente titular (flujo formal posterior al cierre).
--   * @accion: exactamente APROBADA o RECHAZADA (TRIM + UPPER). Cualquier otro valor => REV_001, sin escrituras.
--   * APROBADA: la asistencia queda JUSTIFICADA = RazonCausa EX con asistio = 0 (no es presencia AN). La solicitud pasa
--     a A. Si la asistencia ya era EX solo se resuelve la solicitud. Una asistencia AN no es justificable => REV_003.
--   * RECHAZADA: la solicitud pasa a R y DetalleAsistencia NO se modifica.
--   * Concurrencia: la solicitud se lee con UPDLOCK/HOLDLOCK dentro de la transaccion; dos resoluciones simultaneas se
--     serializan. Reintento con la misma decision ya aplicada => exito idempotente sin nuevas escrituras ni auditoria;
--     decision contradictoria sobre una solicitud ya resuelta => REV_002.
--   * Solicitud inexistente => REV_005; docente no titular => VAL_007 (contrato previo); sin detalle de asistencia
--     => REV_004 (no se simula una justificacion ni se crean filas).
--   * Auditoria oficial (dbo.AuditoriaEvento) en la MISMA transaccion: actor, accion, estado previo y nuevo de la
--     solicitud y del detalle, respuesta y correlacion.
--   * No usa la ventana de registro ordinario (SES-01): la rectificacion por reclamo es valida despues del cierre.
--   * Firma y resultset canonico de 4 columnas sin cambio.
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_solicitud_revision_asistencia]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idDocente          UNIQUEIDENTIFIER,
    @accion             NVARCHAR(20),
    @respuestaDocente   NVARCHAR(MAX),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @accionDefecto            NVARCHAR(20)     = UPPER(TRIM(@accion));
    DECLARE @respuestaDefecto         NVARCHAR(MAX)    = TRIM(@respuestaDocente);

    DECLARE @docenteTitularGrupo   UNIQUEIDENTIFIER;
    DECLARE @idAsistencia          UNIQUEIDENTIFIER;
    DECLARE @idDetalle             UNIQUEIDENTIFIER;
    DECLARE @asistioAnterior       BIT;
    DECLARE @codigoCausaAnterior   NVARCHAR(5);
    DECLARE @codigoEstadoActual    CHAR(1);
    DECLARE @codigoEstadoNuevo     CHAR(1);
    DECLARE @idEstadoNuevo         UNIQUEIDENTIFIER;
    DECLARE @idRazonJustificada    UNIQUEIDENTIFIER;
    DECLARE @modificaDetalle       BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: El ejecutor es obligatorio y debe tener perfil DOCENTE
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

        -- PASO 1.6 (SES-04): solo las acciones contractuales; ningun otro valor se interpreta como rechazo
        IF @estadoResultado = 1 AND (@accionDefecto IS NULL OR @accionDefecto NOT IN (N'APROBADA', N'RECHAZADA'))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'REV_001',
                @p_param1 = @accion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: Resolución atómica. La solicitud, su estado y su detalle se leen bajo bloqueo dentro de la
        --         transacción; los rechazos de negocio confirman una transacción sin escrituras (así no hay ROLLBACK
        --         dentro de un INSERT ... EXEC del llamador).
        IF @estadoResultado = 1
        BEGIN
            BEGIN TRANSACTION;

            SELECT TOP 1
                @docenteTitularGrupo = g.docente,
                @idAsistencia = sra.asistencia,
                @codigoEstadoActual = e.codigo
            FROM dbo.SolicitudRevisionAsistencia sra WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Estado e ON e.id = sra.estado
            INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
            INNER JOIN dbo.Sesion s ON ast.sesion = s.id
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE sra.id = @idSolicitudDefecto;

            -- 2.1: solicitud existente con relacion solicitud -> asistencia -> sesion -> grupo
            IF @docenteTitularGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'REV_005',
                    @p_param1 = @idSolicitudDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            -- 2.2: titularidad del docente sobre el grupo de la sesion
            ELSE IF @docenteTitularGrupo <> @idDocenteDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'DocenteAmbitoRevision',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                SET @codigoEstadoNuevo = CASE WHEN @accionDefecto = N'APROBADA' THEN 'A' ELSE 'R' END;

                -- 2.3: solo una solicitud pendiente se resuelve. La misma decision ya aplicada es un reintento
                --      idempotente (sin escrituras); una decision distinta es un conflicto.
                IF @codigoEstadoActual <> 'P'
                BEGIN
                    IF @codigoEstadoActual <> @codigoEstadoNuevo
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_002',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                END
                ELSE
                BEGIN
                    -- 2.4: detalle de la asistencia (bloqueado). Sin detalle no se simula una justificacion.
                    SELECT TOP 1
                        @idDetalle = d.id,
                        @asistioAnterior = d.asistio,
                        @codigoCausaAnterior = rc.codigo
                    FROM dbo.DetalleAsistencia d WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.RazonCausa rc ON rc.id = d.razonCausa
                    WHERE d.asistencia = @idAsistencia;

                    IF @idDetalle IS NULL
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_004',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END
                    -- 2.5: solo una ausencia es justificable; una presencia (AN / asistio = 1) no se aprueba
                    ELSE IF @codigoEstadoNuevo = 'A' AND (@asistioAnterior = 1 OR @codigoCausaAnterior = N'AN')
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'REV_003',
                            @p_param1 = @idSolicitudDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                        SET @estadoResultado = 0;
                    END

                    -- 2.6: catalogos cerrados (Estado A/R, RazonCausa EX); nunca se elige otra fila
                    IF @estadoResultado = 1
                    BEGIN
                        SELECT @idEstadoNuevo = id FROM dbo.Estado WHERE codigo = @codigoEstadoNuevo;
                        SELECT @idRazonJustificada = id FROM dbo.RazonCausa WHERE codigo = N'EX';
                        IF @idEstadoNuevo IS NULL OR (@codigoEstadoNuevo = 'A' AND @idRazonJustificada IS NULL)
                            THROW 52401, 'SES04_CATALOGO_INCONSISTENTE: falta Estado A/R o RazonCausa EX.', 1;

                        SET @modificaDetalle = CASE WHEN @codigoEstadoNuevo = 'A' AND @codigoCausaAnterior <> N'EX' THEN 1 ELSE 0 END;

                        -- 2.7: la solicitud queda resuelta con la respuesta del docente
                        UPDATE dbo.SolicitudRevisionAsistencia
                        SET estado = @idEstadoNuevo,
                            justificacionRespuesta = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END
                        WHERE id = @idSolicitudDefecto;

                        -- 2.8: aprobacion => JUSTIFICADA (EX, asistio = 0). El rechazo no toca DetalleAsistencia.
                        IF @modificaDetalle = 1
                        BEGIN
                            UPDATE dbo.DetalleAsistencia
                            SET razonCausa = @idRazonJustificada,
                                asistio = 0
                            WHERE id = @idDetalle;
                        END

                        -- 2.9: auditoria oficial con estado previo y nuevo, en la misma transaccion
                        INSERT INTO dbo.AuditoriaEvento (
                            id, occurredAt, actorId, actorType, action,
                            resourceType, resourceId, result, correlationId,
                            httpMethod, path, httpStatus, metadata
                        ) VALUES (
                            NEWID(),
                            SYSDATETIMEOFFSET(),
                            CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)),
                            'USER',
                            'RESOLVER_SOLICITUD_REVISION_ASISTENCIA',
                            'SolicitudRevisionAsistencia',
                            CAST(@idSolicitudDefecto AS NVARCHAR(120)),
                            'SUCCESS',
                            @idCorrelacionDefecto,
                            'PATCH',
                            N'/api/v1/docente/reclamos/{id}',
                            200,
                            (SELECT accion = @accionDefecto,
                                    estadoSolicitudAnterior = @codigoEstadoActual,
                                    estadoSolicitudNuevo = @codigoEstadoNuevo,
                                    idAsistencia = CAST(@idAsistencia AS NVARCHAR(36)),
                                    idDetalleAsistencia = CAST(@idDetalle AS NVARCHAR(36)),
                                    razonCausaAnterior = @codigoCausaAnterior,
                                    asistioAnterior = @asistioAnterior,
                                    razonCausaNueva = CASE WHEN @modificaDetalle = 1 THEN N'EX' ELSE @codigoCausaAnterior END,
                                    asistioNuevo = CASE WHEN @modificaDetalle = 1 THEN CAST(0 AS BIT) ELSE @asistioAnterior END,
                                    respuestaDocente = @respuestaDefecto
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                        );
                    END
                END
            END

            COMMIT TRANSACTION;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'SolicitudRevisionAsistencia',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

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

-- schema/stored-procedures/usp_consultar_detalle_solicitud_revision_docente.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_detalle_solicitud_revision_docente  (HU035/HU036)
--
-- Clasificacion (DB-GP-001C):
--   NON_GOLDEN_PATH_EXTENSION   no forma parte de docs/contracts/DB_BASELINE_CONTRACT.md
--
-- Resultset: READ_QUERY_RESULTSET (0..1 fila con el detalle y la causal de una solicitud de revision).
-- Los parametros invalidos se propagan con THROW (como usp_consultar_solicitudes_revision_docente, R2).
--
-- Alcance: SOLO solicitudes de grupos cuyo Grupo.docente pertenece a Docente.usuario = ejecutor
-- (titularidad institucional, no solo el rol). Solicitud inexistente o ajena => 0 filas (no distingue
-- ambos casos para no revelar existencia). Solo lectura: sin transaccion explicita.
--
-- Causal: DetalleAsistencia y RazonCausa se unen con LEFT JOIN (la solicitud existe aunque falte el detalle).
-- Soporte: ArchivoSoporte se une con LEFT JOIN y solo en el estado definido por el parametro
-- ARCHIVO.ESTADO_ADJUNTO (sin literales quemados).
--
-- Semantica temporal: igual que R2. fechaSolicitud es DATE de calendario; fechaHoraInicioSesion es el
-- DATETIME2(7) de dbo.Sesion TAL CUAL con procedenciaTemporalSesion (NULL = INDETERMINADA, historica);
-- fechaRegistroSoporteUtc es un instante UTC DATETIME2(7). Datos personales minimos: sin correo.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_detalle_solicitud_revision_docente]
(
    @idSolicitud        UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSolicitudDefecto   UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSolicitud, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @estadoAdjunto        VARCHAR(10)      = CAST(dbo.ufn_obtener_parametro('ARCHIVO', 'ESTADO_ADJUNTO') AS VARCHAR(10));

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1 AND (@idSolicitud IS NULL OR @idSolicitudDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'Solicitud',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioDefecto = @guidVacio)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'VAL_001',
            @p_param1 = 'UsuarioEjecutor',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT
        idSolicitudRevisionAsistencia = sra.id,
        nombreSolicitud               = sra.nombre,
        fechaSolicitud                = sra.fecha,
        codigoEstado                  = est.codigo,
        nombreEstado                  = est.nombre,
        justificacionSolicitud        = CAST(sra.justificacionSolicitud AS NVARCHAR(MAX)),
        justificacionRespuesta        = CAST(sra.justificacionRespuesta AS NVARCHAR(MAX)),
        idEstudiante                  = estu.id,
        nombreEstudiante              = CAST(CONCAT_WS(N' ',
                                            NULLIF(TRIM(usu.primerNombre), N''),
                                            NULLIF(TRIM(usu.segundoNombre), N''),
                                            NULLIF(TRIM(usu.primerApellido), N''),
                                            NULLIF(TRIM(usu.segundoApellido), N'')) AS NVARCHAR(400)),
        idSesion                      = ses.id,
        numeroSesion                  = ses.numero,
        fechaHoraInicioSesion         = ses.fechaHoraInicio,
        procedenciaTemporalSesion     = ses.procedenciaTemporal,
        idGrupo                       = gru.id,
        codigoGrupo                   = gru.codigo,
        nombreGrupo                   = gru.nombre,
        idAsignatura                  = asg.id,
        codigoAsignatura              = asg.codigo,
        nombreAsignatura              = asg.nombre,
        asistio                       = det.asistio,
        codigoRazonCausa              = rzc.codigo,
        nombreRazonCausa              = rzc.nombre,
        idArchivoSoporte              = arc.id,
        nombreSoporte                 = arc.nombreOriginal,
        tipoContenidoSoporte          = arc.tipoContenido,
        tamanioSoporteBytes           = arc.tamanioBytes,
        fechaRegistroSoporteUtc       = arc.fechaRegistroUtc
    FROM dbo.SolicitudRevisionAsistencia sra
    INNER JOIN dbo.Estado est             ON est.id = sra.estado
    INNER JOIN dbo.Asistencia asi         ON asi.id = sra.asistencia
    INNER JOIN dbo.EstudianteGrupo eg     ON eg.id = asi.estudianteGrupo
    INNER JOIN dbo.Estudiante estu        ON estu.id = eg.estudiante
    INNER JOIN dbo.Usuario usu            ON usu.id = estu.usuario
    INNER JOIN dbo.Sesion ses             ON ses.id = asi.sesion
    INNER JOIN dbo.Grupo gru              ON gru.id = ses.grupo
    INNER JOIN dbo.Docente doc            ON doc.id = gru.docente
    INNER JOIN dbo.Asignatura asg         ON asg.id = gru.asignatura
    LEFT  JOIN dbo.DetalleAsistencia det  ON det.asistencia = asi.id
    LEFT  JOIN dbo.RazonCausa rzc         ON rzc.id = det.razonCausa
    LEFT  JOIN dbo.ArchivoSoporte arc     ON arc.solicitudRevisionAsistencia = sra.id
                                         AND arc.estado = @estadoAdjunto
    WHERE sra.id = @idSolicitudDefecto
      AND doc.usuario = @idUsuarioDefecto;
END;
GO

-- schema/stored-procedures/usp_consultar_bitacora_estudiante_programa.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_bitacora_estudiante_programa (HU067). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Sesiones vencidas de los grupos del programa en los que el estudiante esta (o estuvo) matriculado, la mas reciente primero.
-- asistio = NULL cuando la sesion vencida no tiene registro de ese estudiante.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_bitacora_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idPrograma = @idPrograma OUTPUT;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 3: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;
    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    SELECT
        idSesion = s.id,
        numeroSesion = s.numero,
        nombreSesion = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        asistio = d.asistio,
        codigoRazonCausa = d.codigoRazonCausa,
        nombreRazonCausa = d.nombreRazonCausa,
        totalRegistros = COUNT(*) OVER()
    FROM dbo.uv_estudiante_grupo eg
    INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idGrupo = eg.idGrupo AND c.estaVencida = 1
    INNER JOIN dbo.uv_sesion_v2 s ON s.id = c.idSesion
    INNER JOIN dbo.uv_grupo g ON g.id = eg.idGrupo
    OUTER APPLY (
        SELECT TOP 1 da.asistio, da.codigoRazonCausa, da.nombreRazonCausa
        FROM dbo.uv_asistencia a
        INNER JOIN dbo.uv_detalle_asistencia da ON da.idAsistencia = a.id
        WHERE a.idEstudianteGrupo = eg.id AND a.idSesion = s.id
        ORDER BY da.fechaHoraInicio DESC, da.id ASC
    ) d
    WHERE eg.idEstudiante = @idEstudiante
      AND c.idPrograma = @idPrograma
      AND c.idPeriodoAcademico = @idPeriodo
    ORDER BY s.fechaHoraInicio DESC, s.id DESC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- schema/stored-procedures/usp_consultar_tendencia_ausentismo.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_tendencia_ausentismo (HU134). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Serie temporal del ausentismo del periodo por SEMANA (calendario, inicia el lunes) o MES, segun la hora local institucional
-- (parametro TIEMPO/ZONA_HORARIA_SQLSERVER) del inicio de la sesion. Solo sesiones vencidas con registro; solo intervalos con datos.
-- Ausentismo del intervalo = faltas SJC / sesiones-estudiante (matriculas activas de cada sesion ejecutada), igual que los KPIs.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_tendencia_ausentismo]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @granularidad       NVARCHAR(6)      = N'SEMANA'
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 0, @idInstitucion = @idInstitucion OUTPUT;

    DECLARE @g NVARCHAR(6) = UPPER(TRIM(ISNULL(@granularidad, N'SEMANA')));
    -- PASO 2: Validacion de negocio (GEN_002)
    IF @g NOT IN (N'SEMANA', N'MES')
    BEGIN
        SET @msgP1 = CAST(N'granularidad' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @zona NVARCHAR(100) = COALESCE(
        (SELECT TOP 1 valor FROM dbo.CatalogoParametro WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1),
        'SA Pacific Standard Time');

    -- PASO 4: Consulta y retorno de resultados
    WITH ejecutadas AS (
        SELECT  c.idSesion, c.idGrupo,
                fechaLocal = CAST(c.fechaHoraInicio AT TIME ZONE 'UTC' AT TIME ZONE @zona AS DATE)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        INNER JOIN dbo.uv_programa p ON p.id = c.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND c.idPeriodoAcademico = @idPeriodo
          AND   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
    ),
    activos AS (
        SELECT idGrupo, n = COUNT(*) FROM dbo.uv_estudiante_grupo WHERE codigoEstadoEstudiante = N'A' GROUP BY idGrupo
    ),
    faltas AS (
        SELECT  a.idSesion, f = SUM(IIF(da.asistio = 0 AND da.codigoRazonCausa = N'SJC', 1, 0))
        FROM    dbo.uv_asistencia a
        INNER JOIN dbo.uv_detalle_asistencia da ON da.idAsistencia = a.id
        INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = a.idEstudianteGrupo AND eg.codigoEstadoEstudiante = N'A'
        GROUP BY a.idSesion
    ),
    intervalo AS (
        SELECT  e.idSesion,
                inicio = CASE @g WHEN N'MES' THEN DATEFROMPARTS(YEAR(e.fechaLocal), MONTH(e.fechaLocal), 1)
                                 ELSE DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal) END,
                fin = CASE @g WHEN N'MES' THEN EOMONTH(e.fechaLocal)
                              ELSE DATEADD(DAY, 6, DATEADD(DAY, -(DATEDIFF(DAY, '19000101', e.fechaLocal) % 7), e.fechaLocal)) END,
                sesionesEstudiante = ISNULL(ac.n, 0),
                faltas = ISNULL(fa.f, 0)
        FROM    ejecutadas e
        LEFT JOIN activos ac ON ac.idGrupo = e.idGrupo
        LEFT JOIN faltas fa ON fa.idSesion = e.idSesion
    )
    -- PASO 5: Consulta y retorno de resultados
    SELECT
        inicioIntervalo = inicio,
        finIntervalo = fin,
        sesionesEjecutadas = SUM(sesionesEstudiante),
        faltasSinJustaCausa = SUM(faltas),
        porcentajeAusentismo = CAST(IIF(SUM(sesionesEstudiante) = 0, NULL, 100.0 * SUM(faltas) / SUM(sesionesEstudiante)) AS DECIMAL(5,2))
    FROM intervalo
    GROUP BY inicio, fin
    ORDER BY inicio ASC;
END;
GO

-- schema/stored-procedures/usp_consultar_comparativa_facultades.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_facultades (HU139). READ_QUERY_RESULTSET sin paginar. Solo lectura.
-- Una fila por facultad de la institucion (activas e inactivas, D4). Mismas definiciones que usp_consultar_kpis_institucion.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_facultades]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  p.idFacultad, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY p.idFacultad, r.idEstudiante
    ),
    conteo AS (
        SELECT  idFacultad,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idFacultad
    ),
    asistencia AS (
        SELECT  p.idFacultad,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.faltasSinJustaCausa)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY p.idFacultad
    ),
    programas AS (
        SELECT idFacultad, total = COUNT(*) FROM dbo.uv_programa WHERE idInstitucion = @idInstitucion GROUP BY idFacultad
    ),
    resultado AS (
        SELECT
            idFacultad = f.id,
            nombreFacultad = f.nombreFacultad,
            estaActivaFacultad = CAST(f.estaActivaFacultad AS BIT),
            totalProgramas = ISNULL(pr.total, 0),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.sesiones, 0) = 0, NULL, 100.0 * a.faltas / a.sesiones) AS DECIMAL(5,2))
        FROM dbo.uv_facultad f
        LEFT JOIN programas pr ON pr.idFacultad = f.id
        LEFT JOIN conteo c ON c.idFacultad = f.id
        LEFT JOIN asistencia a ON a.idFacultad = f.id
        WHERE f.idInstitucion = @idInstitucion
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idFacultad, nombreFacultad, estaActivaFacultad, totalProgramas, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombreFacultad ASC, idFacultad ASC;
END;
GO

-- schema/stored-procedures/usp_consultar_comparativa_programas_facultad.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_comparativa_programas_facultad (HU103). READ_QUERY_RESULTSET sin paginar (D6). Solo lectura.
-- Una fila por programa de la facultad (activos e inactivos, D5). Mismas definiciones que usp_consultar_kpis_decano.
-- Orden: ausentismo descendente (NULL al final), luego nombre.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_comparativa_programas_facultad]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 3: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  r.idPrograma, r.idEstudiante,
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma, r.idEstudiante
    ),
    conteo AS (
        SELECT  idPrograma,
                total = COUNT(*),
                regulares = SUM(IIF(peor = 1, 1, 0)),
                riesgo = SUM(IIF(peor = 2, 1, 0)),
                perdida = SUM(IIF(peor = 3, 1, 0))
        FROM    persona
        GROUP BY idPrograma
    ),
    asistencia AS (
        SELECT  r.idPrograma,
                sesiones = SUM(r.sesionesEjecutadas),
                faltas = SUM(r.faltasSinJustaCausa)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idPrograma
    ),
    resultado AS (
        SELECT
            idPrograma = p.id,
            nombrePrograma = p.nombrePrograma,
            estaActivoPrograma = CAST(p.estaActivoPrograma AS BIT),
            totalEstudiantes = ISNULL(c.total, 0),
            estudiantesRiesgo = ISNULL(c.riesgo, 0),
            estudiantesPerdida = ISNULL(c.perdida, 0),
            tasaRetencion = CAST(IIF(ISNULL(c.total, 0) = 0, NULL, 100.0 * (c.regulares + c.riesgo) / c.total) AS DECIMAL(5,2)),
            sesionesEjecutadas = ISNULL(a.sesiones, 0),
            faltasSinJustaCausa = ISNULL(a.faltas, 0),
            porcentajeAusentismo = CAST(IIF(ISNULL(a.sesiones, 0) = 0, NULL, 100.0 * a.faltas / a.sesiones) AS DECIMAL(5,2))
        FROM dbo.uv_programa p
        LEFT JOIN conteo c ON c.idPrograma = p.id
        LEFT JOIN asistencia a ON a.idPrograma = p.id
        WHERE p.idFacultad = @idFacultad
    )
    -- PASO 4: Consulta y retorno de resultados
    SELECT idPrograma, nombrePrograma, estaActivoPrograma, totalEstudiantes, estudiantesRiesgo, estudiantesPerdida,
           tasaRetencion, sesionesEjecutadas, faltasSinJustaCausa, porcentajeAusentismo
    FROM resultado
    ORDER BY IIF(porcentajeAusentismo IS NULL, 1, 0) ASC, porcentajeAusentismo DESC, nombrePrograma ASC, idPrograma ASC;
END;
GO

-- schema/stored-procedures/usp_consultar_consolidado_asistencia_grupos_paginado.sql (version anterior a B.2)
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

-- schema/stored-procedures/usp_consultar_kpis_decano.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_decano (HU102, HU106, HU144). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Estudiante = persona con la peor clasificacion de sus matriculas activas de la facultad (D3).
-- Retencion = (regular + riesgo) / total (D2). Ausentismo = faltas / sesiones ejecutadas, ponderado por matricula activa (D1).
-- sesionesEjecutadas = suma por matricula activa (denominador del ausentismo). Aforo = matriculados activos / cupo de los grupos habilitados (D4).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_decano]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idFacultad UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_facultad_decano_interno)
    EXEC dbo.usp_resolver_facultad_decano_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idFacultad = @idFacultad OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_facultad_interno)
    EXEC dbo.usp_resolver_periodo_kpi_facultad_interno @idFacultad = @idFacultad, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idFacultad = @idFacultad);
    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @grupos INT = 0, @cupo INT = 0, @matriculados INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
                WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idFacultad = @idFacultad AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @grupos = COUNT(*),
                @cupo = ISNULL(SUM(g.capacidadMaximaPermitida), 0),
                @matriculados = ISNULL(SUM(g.estudiantesActivos), 0)
        FROM    dbo.uv_grupo_programa gp
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_grupo g ON g.id = gp.idGrupo
        WHERE   p.idFacultad = @idFacultad AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1;
    END

    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@sesiones = 0, NULL, 100.0 * @faltas / @sesiones) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idFacultad = f.id,
        nombreFacultad = f.nombreFacultad,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        gruposActivos = @grupos,
        cupoTotal = @cupo,
        matriculadosActivos = @matriculados,
        tasaAforo = CAST(IIF(@cupo = 0, NULL, 100.0 * @matriculados / @cupo) AS DECIMAL(7,2)),
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_facultad f
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE f.id = @idFacultad;
END;
GO

-- schema/stored-procedures/usp_consultar_kpis_institucion.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_kpis_institucion (HU133, HU135, HU136, HU138). READ_QUERY_RESULTSET de una fila. Solo lectura.
-- Mismas definiciones que las olas 1 y 2: persona = peor clasificacion de sus matriculas activas; ausentismo ponderado por
-- matricula activa (sesionesEjecutadas = suma por matricula); retencion = (regular + riesgo) / total.
-- Cumplimiento (HU138) = sesiones vencidas con registro / sesiones vencidas. Censo (HU135/HU136): con matricula o grupo activo
-- en el periodo y registrados (usuario activo; docentes = titulares de al menos un grupo de la institucion, sin depender del periodo).
-- Lo que no puede calcularse es NULL; nunca un valor por defecto.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_kpis_institucion]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idInstitucion UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_institucion_administrador_interno)
    EXEC dbo.usp_resolver_institucion_administrador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idInstitucion = @idInstitucion OUTPUT;
    -- PASO 2: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_institucion_interno)
    EXEC dbo.usp_resolver_periodo_kpi_institucion_interno @idInstitucion = @idInstitucion, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    DECLARE @facultades INT = (SELECT COUNT(*) FROM dbo.uv_facultad f WHERE f.idInstitucion = @idInstitucion);
    DECLARE @programas INT = (SELECT COUNT(*) FROM dbo.uv_programa p WHERE p.idInstitucion = @idInstitucion);
    DECLARE @estudiantesRegistrados INT = (
        SELECT COUNT(DISTINCT ep.idEstudiante)
        FROM dbo.uv_estudiante_programa ep
        INNER JOIN dbo.uv_programa p ON p.id = ep.idPrograma
        INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = ep.idEstudiante
        WHERE p.idInstitucion = @idInstitucion AND ei.estaActivoUsuario = 1);
    DECLARE @docentesRegistrados INT = (
        SELECT COUNT(DISTINCT g.idDocente)
        FROM dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE p.idInstitucion = @idInstitucion AND di.estaActivoUsuario = 1);

    DECLARE @total INT = 0, @regulares INT = 0, @riesgo INT = 0, @perdida INT = 0;
    DECLARE @sesiones INT = 0, @faltas INT = 0;
    DECLARE @vencidas INT = 0, @conRegistro INT = 0;
    DECLARE @docentesActivos INT = 0;

    -- PASO 3: Calcular los indicadores del periodo
    IF @idPeriodo IS NOT NULL
    BEGIN
        SELECT  @total = COUNT(*),
                @regulares = ISNULL(SUM(IIF(x.peor = 1, 1, 0)), 0),
                @riesgo = ISNULL(SUM(IIF(x.peor = 2, 1, 0)), 0),
                @perdida = ISNULL(SUM(IIF(x.peor = 3, 1, 0)), 0)
        FROM (
                SELECT  r.idEstudiante,
                        peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
                FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
                INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
                WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
                GROUP BY r.idEstudiante
             ) x;

        SELECT  @sesiones = ISNULL(SUM(r.sesionesEjecutadas), 0),
                @faltas = ISNULL(SUM(r.faltasSinJustaCausa), 0)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        INNER JOIN dbo.uv_programa p ON p.id = r.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A';

        SELECT  @vencidas = ISNULL(SUM(IIF(c.estaVencida = 1, 1, 0)), 0),
                @conRegistro = ISNULL(SUM(IIF(c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1, 1, 0)), 0)
        FROM    dbo.uv_cumplimiento_sesion_grupo c
        INNER JOIN dbo.uv_programa p ON p.id = c.idPrograma
        WHERE   p.idInstitucion = @idInstitucion AND c.idPeriodoAcademico = @idPeriodo;

        SELECT  @docentesActivos = COUNT(DISTINCT g.idDocente)
        FROM    dbo.uv_grupo g
        INNER JOIN dbo.uv_grupo_programa gp ON gp.idGrupo = g.id
        INNER JOIN dbo.uv_programa p ON p.id = gp.idPrograma
        INNER JOIN dbo.uv_docente_identidad di ON di.id = g.idDocente
        WHERE   p.idInstitucion = @idInstitucion AND gp.idPeriodoAcademico = @idPeriodo AND gp.grupoEstaHablitado = 1 AND di.estaActivoUsuario = 1;
    END

    DECLARE @ausentismo DECIMAL(5,2) = CAST(IIF(@sesiones = 0, NULL, 100.0 * @faltas / @sesiones) AS DECIMAL(5,2));

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idInstitucion = i.id,
        nombreInstitucion = i.nombre,
        idPeriodoAcademico = pa.id,
        nombrePeriodoAcademico = pa.nombre,
        totalFacultades = @facultades,
        totalProgramas = @programas,
        totalEstudiantes = @total,
        estudiantesRegulares = @regulares,
        estudiantesRiesgo = @riesgo,
        estudiantesPerdida = @perdida,
        tasaRetencion = CAST(IIF(@total = 0, NULL, 100.0 * (@regulares + @riesgo) / @total) AS DECIMAL(5,2)),
        sesionesEjecutadas = @sesiones,
        faltasSinJustaCausa = @faltas,
        porcentajeAusentismo = @ausentismo,
        porcentajeAsistencia = CAST(IIF(@ausentismo IS NULL, NULL, 100.0 - @ausentismo) AS DECIMAL(5,2)),
        sesionesVencidas = @vencidas,
        sesionesConRegistro = @conRegistro,
        porcentajeCumplimiento = CAST(IIF(@vencidas = 0, NULL, 100.0 * @conRegistro / @vencidas) AS DECIMAL(5,2)),
        estudiantesConMatriculaActiva = @total,
        estudiantesRegistrados = @estudiantesRegistrados,
        docentesConGrupoActivo = @docentesActivos,
        docentesRegistrados = @docentesRegistrados,
        umbralAdvertencia = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_ADVERTENCIA')), '') AS DECIMAL(5,2)),
        umbralPerdida = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA')), '') AS DECIMAL(5,2))
    FROM dbo.uv_institucion i
    LEFT JOIN dbo.uv_periodo_academico pa ON pa.id = @idPeriodo
    WHERE i.id = @idInstitucion;
END;
GO

-- schema/stored-procedures/usp_consultar_historial_estudiante.sql (version anterior a B.2)
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

-- schema/stored-procedures/usp_consultar_resumen_asistencia_estudiante_programa.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_resumen_asistencia_estudiante_programa (HU069). READ_QUERY_RESULTSET (una fila por matricula). Solo lectura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_resumen_asistencia_estudiante_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idEstudiante       UNIQUEIDENTIFIER,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT;
    -- PASO 2: Validacion de negocio (usp_validar_estudiante_en_programa_interno)
    EXEC dbo.usp_validar_estudiante_en_programa_interno @idEstudiante = @idEstudiante, @idPrograma = @idPrograma;
    -- PASO 3: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 4: Consulta y retorno de resultados
    SELECT
        idGrupo = g.id,
        codigoGrupo = g.codigo,
        idAsignatura = g.idAsignatura,
        nombreAsignatura = g.nombreAsignatura,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        nombreEstadoEstudiante = eg.nombreEstadoEstudiante,
        sesionesEjecutadas = r.sesionesEjecutadas,
        asistencias = r.asistencias,
        faltasSinJustaCausa = r.faltasSinJustaCausa,
        excusas = r.excusas,
        porcentajeInasistencia = r.porcentajeInasistencia,
        codigoPermanencia = r.codigoPermanencia
    FROM dbo.uv_resumen_asistencia_estudiante_grupo r
    INNER JOIN dbo.uv_estudiante_grupo eg ON eg.id = r.idEstudianteGrupo
    INNER JOIN dbo.uv_grupo g ON g.id = r.idGrupo
    WHERE r.idEstudiante = @idEstudiante AND r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo
    ORDER BY g.nombreAsignatura ASC, g.codigo ASC, g.id ASC;
END;
GO

-- schema/stored-procedures/usp_consultar_alerta_temprana_programa.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_alerta_temprana_programa (HU066, HU070). READ_QUERY_RESULTSET paginado. Solo lectura.
-- Una fila por persona: % = el mayor de sus matriculas activas, faltas = suma, clasificacion = la peor (D6).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_alerta_temprana_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @idPeriodoAcademico UNIQUEIDENTIFIER = NULL,
    @semaforo           NVARCHAR(5)      = NULL,
    @filtroTexto        NVARCHAR(100)    = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @msgP1 NVARCHAR(500);
    DECLARE @idPrograma UNIQUEIDENTIFIER, @idPeriodo UNIQUEIDENTIFIER;
    DECLARE @filtro NVARCHAR(100) = NULLIF(TRIM(@filtroTexto), '');

    -- PASO 1: Resolver ambito del ejecutor (usp_resolver_programa_coordinador_interno)
    EXEC dbo.usp_resolver_programa_coordinador_interno @idUsuarioEjecutor = @idUsuarioEjecutor, @idCorrelacion = @idCorrelacion, @validarUmbrales = 1, @idPrograma = @idPrograma OUTPUT;
    DECLARE @tamanoMaximo INT = TRY_CAST(NULLIF(TRIM(dbo.ufn_obtener_parametro('PAGINACION', 'TAMANO_MAXIMO')), '') AS INT);
    -- PASO 2: Validacion de negocio (PAG_001)
    IF @numeroPagina IS NULL OR @numeroPagina < 1 OR @tamanoPagina IS NULL OR @tamanoPagina < 1 OR @tamanoMaximo IS NULL OR @tamanoPagina > @tamanoMaximo
    BEGIN
        SET @msgP1 = CAST(@numeroPagina AS NVARCHAR(500));
        DECLARE @msgP2 NVARCHAR(500) = CAST(@tamanoPagina AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'PAG_001',
            @p_param1 = @msgP1,
            @p_param2 = @msgP2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END
    DECLARE @offset INT = (@numeroPagina - 1) * @tamanoPagina;
    -- PASO 3: Validacion de negocio (GEN_002)
    IF @semaforo IS NOT NULL AND @semaforo NOT IN (N'VERDE', N'AMBAR', N'ROJO')
    BEGIN
        SET @msgP1 = CAST(N'semaforo' AS NVARCHAR(500));
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'GEN_002',
            @p_param1 = @msgP1,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    -- PASO 4: Resolver ambito del ejecutor (usp_resolver_periodo_kpi_interno)
    EXEC dbo.usp_resolver_periodo_kpi_interno @idPrograma = @idPrograma, @idPeriodoSolicitado = @idPeriodoAcademico, @idPeriodo = @idPeriodo OUTPUT;

    -- PASO 5: Consulta y retorno de resultados
    WITH persona AS (
        SELECT  r.idEstudiante,
                totalMatriculasActivas = COUNT(*),
                porcentajeInasistencia = MAX(r.porcentajeInasistencia),
                faltasSinJustaCausa = SUM(r.faltasSinJustaCausa),
                peor = MAX(CASE r.codigoPermanencia WHEN N'PERDIDA' THEN 3 WHEN N'RIESGO' THEN 2 ELSE 1 END)
        FROM    dbo.uv_resumen_asistencia_estudiante_grupo r
        WHERE   r.idPrograma = @idPrograma AND r.idPeriodoAcademico = @idPeriodo AND r.codigoEstadoEstudiante = N'A'
        GROUP BY r.idEstudiante
    )
    -- PASO 6: Consulta y retorno de resultados
    SELECT
        idEstudiante = pe.idEstudiante,
        nombreCompleto = u.nombreCompleto,
        numeroIdentificacion = u.numeroIdentificacion,
        correo = u.correo,
        totalMatriculasActivas = pe.totalMatriculasActivas,
        porcentajeInasistencia = pe.porcentajeInasistencia,
        faltasSinJustaCausa = pe.faltasSinJustaCausa,
        codigoPermanencia = CASE pe.peor WHEN 3 THEN N'PERDIDA' WHEN 2 THEN N'RIESGO' ELSE N'REGULAR' END,
        semaforo = CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END,
        totalRegistros = COUNT(*) OVER()
    FROM persona pe
    INNER JOIN dbo.uv_estudiante_identidad ei ON ei.id = pe.idEstudiante
    INNER JOIN dbo.uv_usuario u ON u.id = ei.idUsuario
    WHERE (@semaforo IS NULL OR (CASE pe.peor WHEN 3 THEN N'ROJO' WHEN 2 THEN N'AMBAR' ELSE N'VERDE' END) = @semaforo)
      AND (@filtro IS NULL
           OR CHARINDEX(@filtro, u.nombreCompleto) > 0
           OR CHARINDEX(@filtro, CONVERT(NVARCHAR(20), u.numeroIdentificacion)) > 0
           OR CHARINDEX(@filtro, u.correo) > 0)
    ORDER BY pe.porcentajeInasistencia DESC, u.nombreCompleto ASC, pe.idEstudiante ASC
    OFFSET @offset ROWS FETCH NEXT @tamanoPagina ROWS ONLY;
END;
GO

-- schema/stored-procedures/usp_ejecutar_cierre_masivo_periodo.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_ejecutar_cierre_masivo_periodo]
(
    @codigoPeriodo          NVARCHAR(50),
    @idActor                NVARCHAR(100),
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoPeriodoDefecto     NVARCHAR(50)     = TRIM(@codigoPeriodo);
    DECLARE @idActorDefecto           NVARCHAR(100)    = TRIM(@idActor);

    DECLARE @idPeriodoTarget               UNIQUEIDENTIFIER;
    DECLARE @idEstadoFinalizado            UNIQUEIDENTIFIER;
    DECLARE @idEstadoCanceladoInasistencia UNIQUEIDENTIFIER;
    DECLARE @totalEstudiantes              INT = 0;
    DECLARE @totalReprobados               INT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    -- REC3 (auditoria BD 2026-10-28): cualquier error o cancelacion del cliente revierte la transaccion completa.
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
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
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Buscar período académico objetivo consultando uv_periodo_academico
        IF @estadoResultado = 1
        BEGIN
            IF @codigoPeriodoDefecto IS NOT NULL AND @codigoPeriodoDefecto <> ''
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                WHERE nombre = @codigoPeriodoDefecto 
                   OR CAST(codigo AS NVARCHAR(50)) = @codigoPeriodoDefecto
                ORDER BY anio DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                SELECT TOP 1 @idPeriodoTarget = id
                FROM [dbo].[uv_periodo_academico]
                ORDER BY anio DESC, codigo DESC;
            END

            IF @idPeriodoTarget IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'PeriodoAcademico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: Ejecución transaccional de Cierre Masivo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstadoFinalizado = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'F' ORDER BY id ASC;
            SELECT TOP 1 @idEstadoCanceladoInasistencia = id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'CI' ORDER BY id ASC;

            BEGIN TRANSACTION;

            -- 1. Conteo de estudiantes procesados
            SELECT @totalEstudiantes = COUNT(eg.id)
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 3. Actualizar estudiantes con fallas críticas (>= 3 inasistencias en DetalleAsistencia) a Cancelado por Inasistencia
            ;WITH InasistenciasPorEstudiante AS (
                SELECT 
                    eg.estudiante,
                    eg.grupo,
                    COUNT(da.id) AS totalFallas
                FROM dbo.DetalleAsistencia da
                INNER JOIN dbo.Asistencia a ON da.asistencia = a.id
                INNER JOIN dbo.EstudianteGrupo eg ON a.estudianteGrupo = eg.id
                INNER JOIN dbo.Sesion s ON a.sesion = s.id
                INNER JOIN dbo.Grupo g ON s.grupo = g.id
                WHERE g.periodoAcademico = @idPeriodoTarget
                  AND da.asistio = 0
                GROUP BY eg.estudiante, eg.grupo
                HAVING COUNT(da.id) >= 3
            )
            UPDATE eg
            SET eg.estado = @idEstadoCanceladoInasistencia
            FROM dbo.EstudianteGrupo eg
            INNER JOIN InasistenciasPorEstudiante ipe 
                ON eg.estudiante = ipe.estudiante AND eg.grupo = ipe.grupo
            WHERE eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            SET @totalReprobados = @@ROWCOUNT;

            -- 4. Actualizar resto de estudiantes activos a Finalizado
            UPDATE eg
            SET eg.estado = @idEstadoFinalizado
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.Grupo g ON eg.grupo = g.id
            WHERE g.periodoAcademico = @idPeriodoTarget
              AND eg.estado = (SELECT TOP 1 id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');

            -- 5. Actualizar contadores en tabla Grupo
            UPDATE g
            SET 
                cantidadEstudiantesFinalizaron = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoFinalizado
                ),
                cantidadEstudiantesCancelaronAutomaticamente = (
                    SELECT COUNT(1) FROM dbo.EstudianteGrupo eg 
                    WHERE eg.grupo = g.id AND eg.estado = @idEstadoCanceladoInasistencia
                )
            FROM dbo.Grupo g
            WHERE g.periodoAcademico = @idPeriodoTarget;

            -- 6. Auditoría de evento
            INSERT INTO dbo.AuditoriaEvento (
                id, occurredAt, actorId, actorType, action,
                resourceType, resourceId, result, correlationId,
                httpMethod, path, httpStatus, metadata
            ) VALUES (
                NEWID(),
                SYSDATETIMEOFFSET(),
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN @idActorDefecto ELSE 'ADMIN_SISTEMA' END,
                CASE WHEN @idActorDefecto IS NOT NULL AND @idActorDefecto <> '' THEN 'USER' ELSE 'SYSTEM' END,
                'CIERRE_MASIVO_PERIODO',
                'PeriodoAcademico',
                CAST(@idPeriodoTarget AS NVARCHAR(50)),
                'SUCCESS',
                @idCorrelacionDefecto,
                'POST',
                '/api/v1/admin/cierre-masivo',
                200,
                CONCAT('{"procesados":', @totalEstudiantes, ',"reprobadosPorFallas":', @totalReprobados, '}')
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'CierreMasivoPeriodo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- REC3: solo se revierte si hay una transaccion viva (XACT_STATE <> 0); evita un segundo error en el CATCH.
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

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

-- schema/stored-procedures/usp_consultar_asistencias_sesion_paginado.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_asistencias_sesion_paginado
--
-- Clasificacion:
--   NON_GOLDEN_PATH_EXTENSION        Consulta paginada institucional
--   READ_QUERY_RESULTSET             Retorna conjunto de filas + totalRegistros
--
-- Proposito:
--   Listar la planilla de asistencia detallada por estudiante para una sesión
--   específica consumiendo uv_auth_sesion, uv_asistencia, uv_detalle_asistencia,
--   uv_estudiante_grupo, uv_estudiante_identidad y uv_usuario.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_asistencias_sesion_paginado]
(
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @idRazonCausa            UNIQUEIDENTIFIER = NULL,
    @asistio                 BIT              = NULL,
    @numeroPagina            INT              = 1,
    @tamanoPagina            INT              = 10
)
AS
    -- 1. Declaraciones previas (AS ... BEGIN)
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio            UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    -- Paginación normalizada
    DECLARE @pagina INT = IIF(@numeroPagina IS NULL OR @numeroPagina < 1, 1, @numeroPagina);
    DECLARE @tamano INT = IIF(@tamanoPagina IS NULL OR @tamanoPagina < 1, 10, IIF(@tamanoPagina > 100, 100, @tamanoPagina));
    DECLARE @offset INT = (@pagina - 1) * @tamano;

    -- Filtros normalizados
    DECLARE @filtroRazonCausaId UNIQUEIDENTIFIER = @idRazonCausa;
    DECLARE @filtroAsistio BIT = @asistio;

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

        -- Paso 3: Validación obligatoria de idSesion
        IF @estadoResultado = 1 AND (@idSesionDefecto IS NULL OR @idSesionDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @p_param1 = 'Sesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END

        -- Paso 4: Establecer identidad temporal en contexto
        EXEC dbo.usp_establecer_contexto_usuario_ejecutor @p_idUsuario = @idUsuarioDefecto;

        -- Paso 5: Consulta optimizada de asistencia de la sesión
        SELECT
            da.id                       AS idDetalleAsistencia,
            da.codigo                   AS codigoDetalleAsistencia,
            asi.id                      AS idAsistencia,
            se.id                       AS idSesion,
            se.nombre                   AS nombreSesion,
            se.codigo                   AS codigoSesion,
            se.numeroSemana             AS numeroSemana,
            eg.id                       AS idEstudianteGrupo,
            ei.id                       AS idEstudiante,
            u.id                        AS idUsuario,
            u.numeroIdentificacion      AS numeroIdentificacion,
            u.primerApellido            AS primerApellido,
            u.segundoApellido           AS segundoApellido,
            u.primerNombre              AS primerNombre,
            u.segundoNombre             AS segundoNombre,
            u.nombreCompleto            AS nombreCompleto,
            da.asistio                  AS asistio,
            da.idRazonCausa             AS idRazonCausa,
            da.codigoRazonCausa         AS codigoRazonCausa,
            da.nombreRazonCausa         AS nombreRazonCausa,
            da.fechaHoraInicio          AS fechaHoraInicio,
            da.fechaHoraFin             AS fechaHoraFin,
            COUNT(1) OVER()             AS totalRegistros
        FROM dbo.uv_auth_sesion se
        INNER JOIN dbo.uv_asistencia asi ON se.id = asi.idSesion
        INNER JOIN dbo.uv_detalle_asistencia da ON asi.id = da.idAsistencia
        INNER JOIN dbo.uv_estudiante_grupo eg ON asi.idEstudianteGrupo = eg.id
        INNER JOIN dbo.uv_estudiante_identidad ei ON eg.idEstudiante = ei.id
        INNER JOIN dbo.uv_usuario u ON ei.idUsuario = u.id
        WHERE se.id = @idSesionDefecto
          AND (@filtroRazonCausaId IS NULL OR da.idRazonCausa = @filtroRazonCausaId)
          AND (@filtroAsistio IS NULL OR da.asistio = @filtroAsistio)
        ORDER BY u.primerApellido ASC, u.primerNombre ASC, u.numeroIdentificacion ASC, da.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamano ROWS ONLY;

        -- Paso 6: Restaurar contexto previo
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

-- schema/views/uv_sesion_estado.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio). B.2 agrega totalTomas, tieneTomaAbierta, idTomaAbierta.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6))
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo;
GO

-- schema/views/uv_cumplimiento_sesion_grupo.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
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
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO

-- schema/views/uv_resumen_asistencia_estudiante_grupo.sql (version anterior a B.2)
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU066/HU067/HU069/HU070: una fila por matricula (EstudianteGrupo) con sus cifras de asistencia.
-- Denominador (D1): sesiones vencidas CON registro del grupo. Falta (D2): asistio = 0 con razon SJC; la excusa (EX) no cuenta.
CREATE OR ALTER VIEW [dbo].[uv_resumen_asistencia_estudiante_grupo]
AS
SELECT  idEstudianteGrupo = eg.id,
        idEstudiante = eg.idEstudiante,
        idGrupo = eg.idGrupo,
        idAsignatura = g.idAsignatura,
        idPrograma = gp.idPrograma,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        codigoEstadoEstudiante = eg.codigoEstadoEstudiante,
        sesionesEjecutadas = ISNULL(se.sesionesEjecutadas, 0),
        asistencias = ISNULL(de.asistencias, 0),
        faltasSinJustaCausa = ISNULL(de.faltas, 0),
        excusas = ISNULL(de.excusas, 0),
        porcentajeInasistencia = p.porcentaje,
        codigoPermanencia = dbo.ufn_clasificar_permanencia(p.porcentaje, eg.codigoEstadoEstudiante)
FROM    dbo.uv_estudiante_grupo eg
INNER JOIN dbo.uv_grupo g
ON      g.id = eg.idGrupo
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  c.idGrupo, sesionesEjecutadas = COUNT(*)
            FROM    dbo.uv_cumplimiento_sesion_grupo c
            WHERE   c.estaVencida = 1 AND c.tieneRegistroAsistencia = 1
            GROUP BY c.idGrupo
          ) se
ON      se.idGrupo = eg.idGrupo
LEFT JOIN (
            SELECT  a.idEstudianteGrupo,
                    asistencias = SUM(IIF(da.asistio = 1, 1, 0)),
                    faltas = SUM(IIF(da.asistio = 0 AND da.codigoRazonCausa = N'SJC', 1, 0)),
                    excusas = SUM(IIF(da.codigoRazonCausa = N'EX', 1, 0))
            FROM    dbo.uv_asistencia a
            INNER JOIN dbo.uv_detalle_asistencia da ON da.idAsistencia = a.id
            INNER JOIN dbo.uv_cumplimiento_sesion_grupo c ON c.idSesion = a.idSesion AND c.estaVencida = 1
            GROUP BY a.idEstudianteGrupo
          ) de
ON      de.idEstudianteGrupo = eg.id
CROSS APPLY (
            SELECT porcentaje = CAST(IIF(ISNULL(se.sesionesEjecutadas, 0) = 0, 0, 100.0 * ISNULL(de.faltas, 0) / se.sesionesEjecutadas) AS DECIMAL(5,2))
          ) p
GO

IF OBJECT_ID(N'dbo.usp_abrir_toma_asistencia', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_abrir_toma_asistencia;
IF OBJECT_ID(N'dbo.usp_cerrar_toma_asistencia', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_cerrar_toma_asistencia;
IF OBJECT_ID(N'dbo.usp_cerrar_tomas_vencidas', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_cerrar_tomas_vencidas;
IF OBJECT_ID(N'dbo.usp_registrar_asistencias_toma', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_registrar_asistencias_toma;
IF OBJECT_ID(N'dbo.usp_internal_marcar_ausentes_toma', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_marcar_ausentes_toma;
IF OBJECT_ID(N'dbo.usp_abrir_qr_toma', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_abrir_qr_toma;
IF OBJECT_ID(N'dbo.usp_internal_rotar_token_asistencia', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_rotar_token_asistencia;
IF OBJECT_ID(N'dbo.usp_rotar_token_asistencia_toma', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_rotar_token_asistencia_toma;
IF OBJECT_ID(N'dbo.usp_rotar_token_asistencia_automatico', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_rotar_token_asistencia_automatico;
IF OBJECT_ID(N'dbo.usp_consultar_tomas_qr_por_rotar', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_tomas_qr_por_rotar;
IF OBJECT_ID(N'dbo.usp_cerrar_qr_toma', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_cerrar_qr_toma;
IF OBJECT_ID(N'dbo.usp_internal_resolver_token_asistencia', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_internal_resolver_token_asistencia;
IF OBJECT_ID(N'dbo.usp_registrar_asistencia_por_token', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_registrar_asistencia_por_token;
IF OBJECT_ID(N'dbo.usp_consultar_tomas_sesion', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_tomas_sesion;
IF OBJECT_ID(N'dbo.usp_consultar_faltantes_toma_paginado', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_faltantes_toma_paginado;
IF OBJECT_ID(N'dbo.usp_consultar_asistencias_toma_paginado', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_asistencias_toma_paginado;
IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_resumen_asistencia_grupo_docente_paginado;
IF OBJECT_ID(N'dbo.usp_consultar_resumen_asistencia_estudiante', N'P') IS NOT NULL DROP PROCEDURE dbo.usp_consultar_resumen_asistencia_estudiante;
GO
IF OBJECT_ID(N'dbo.uv_modo_toma_asistencia', N'V') IS NOT NULL DROP VIEW dbo.uv_modo_toma_asistencia;
IF OBJECT_ID(N'dbo.uv_estado_toma_asistencia', N'V') IS NOT NULL DROP VIEW dbo.uv_estado_toma_asistencia;
IF OBJECT_ID(N'dbo.uv_toma_asistencia', N'V') IS NOT NULL DROP VIEW dbo.uv_toma_asistencia;
IF OBJECT_ID(N'dbo.uv_token_asistencia_toma', N'V') IS NOT NULL DROP VIEW dbo.uv_token_asistencia_toma;
IF OBJECT_ID(N'dbo.uv_detalle_asistencia_v2', N'V') IS NOT NULL DROP VIEW dbo.uv_detalle_asistencia_v2;
IF OBJECT_ID(N'dbo.uv_asistencia_sesion_horas', N'V') IS NOT NULL DROP VIEW dbo.uv_asistencia_sesion_horas;
IF OBJECT_ID(N'dbo.uv_faltantes_toma', N'V') IS NOT NULL DROP VIEW dbo.uv_faltantes_toma;
GO
IF OBJECT_ID(N'dbo.ufn_horas_toma', N'FN') IS NOT NULL DROP FUNCTION dbo.ufn_horas_toma;
IF OBJECT_ID(N'dbo.ufn_calcular_porcentaje_inasistencia_horas', N'FN') IS NOT NULL DROP FUNCTION dbo.ufn_calcular_porcentaje_inasistencia_horas;
IF OBJECT_ID(N'dbo.ufn_horas_sesion', N'FN') IS NOT NULL DROP FUNCTION dbo.ufn_horas_sesion;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Estructura
-- ---------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF OBJECT_ID(N'dbo.TokenAsistenciaToma', N'U') IS NOT NULL DROP TABLE dbo.TokenAsistenciaToma;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_DetalleAsistencia_TomaAsistencia')
    ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT FK_DetalleAsistencia_TomaAsistencia;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_DetalleAsistencia_Asistencia_Toma' AND object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
    DROP INDEX UX_DetalleAsistencia_Asistencia_Toma ON dbo.DetalleAsistencia;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_DetalleAsistencia_Toma' AND object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
    DROP INDEX IX_DetalleAsistencia_Toma ON dbo.DetalleAsistencia;
IF EXISTS (SELECT asistencia FROM dbo.DetalleAsistencia GROUP BY asistencia HAVING COUNT(1) > 1)
    THROW 50013, 'CULM001_B2_DOWN: quedan asistencias con mas de un detalle; no se puede recrear UX_DetalleAsistencia_Asistencia.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_DetalleAsistencia_Asistencia' AND object_id = OBJECT_ID(N'dbo.DetalleAsistencia'))
    CREATE UNIQUE INDEX UX_DetalleAsistencia_Asistencia ON dbo.DetalleAsistencia (asistencia);
IF COL_LENGTH(N'dbo.DetalleAsistencia', N'toma') IS NOT NULL
    ALTER TABLE dbo.DetalleAsistencia DROP COLUMN toma;
IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_DetalleAsistencia_registradoPorEstudiante')
    ALTER TABLE dbo.DetalleAsistencia DROP CONSTRAINT DF_DetalleAsistencia_registradoPorEstudiante;
IF COL_LENGTH(N'dbo.DetalleAsistencia', N'registradoPorEstudiante') IS NOT NULL
    ALTER TABLE dbo.DetalleAsistencia DROP COLUMN registradoPorEstudiante;
IF COL_LENGTH(N'dbo.DetalleAsistencia', N'fechaRegistroUtc') IS NOT NULL
    ALTER TABLE dbo.DetalleAsistencia DROP COLUMN fechaRegistroUtc;
IF OBJECT_ID(N'dbo.seq_detalle_asistencia_codigo', N'SO') IS NOT NULL DROP SEQUENCE dbo.seq_detalle_asistencia_codigo;
IF OBJECT_ID(N'dbo.TomaAsistencia', N'U') IS NOT NULL DROP TABLE dbo.TomaAsistencia;
IF OBJECT_ID(N'dbo.EstadoTomaAsistencia', N'U') IS NOT NULL DROP TABLE dbo.EstadoTomaAsistencia;
IF OBJECT_ID(N'dbo.ModoTomaAsistencia', N'U') IS NOT NULL DROP TABLE dbo.ModoTomaAsistencia;
COMMIT TRANSACTION;
GO

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Semillas de B.2 (parametros solo si no fueron administrados; mensajes TOM_* y AQR_*)
-- ---------------------------------------------------------------------------------------------------------------
SET NOCOUNT ON;
DELETE FROM dbo.CatalogoParametro
WHERE ((grupo = 'TOMA_ASISTENCIA' AND clave IN ('MAXIMO_TOMAS_POR_SESION', 'LOTE_CIERRE_AUTOMATICO'))
       OR (grupo = 'ASISTENCIA' AND clave IN ('CODIGO_RAZON_PRESENTE', 'CODIGO_RAZON_SIN_JUSTA_CAUSA', 'CODIGO_RAZON_EXCUSA'))
       OR (grupo = 'ASISTENCIA_QR' AND clave IN ('HABILITADA', 'ROTACION_SEGUNDOS', 'TOLERANCIA_SEGUNDOS', 'LOTE_ROTACION',
                                                 'LIMITE_FALLIDOS_IP_POR_MINUTO', 'LIMITE_TOKEN_POR_MINUTO', 'URL_BASE_FRONTEND')))
  AND ISNULL(valor, N'') = ISNULL(valorDefecto, N'');
UPDATE dbo.CatalogoParametro SET valor = N'5', valorDefecto = N'5', fechaModificacion = SYSUTCDATETIME()
WHERE grupo = 'ASISTENCIA_QR' AND clave = 'LIMITE_ESTUDIANTE_POR_MINUTO' AND valor = N'6' AND valorDefecto = N'6';
DELETE FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('TOM_001', 'TOM_002', 'TOM_003', 'TOM_004', 'TOM_008', 'TOM_009', 'TOM_010', 'TOM_011')
   OR codigo LIKE 'AQR[_]0%';
DELETE FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('TOM_001', 'TOM_002', 'TOM_003', 'TOM_004', 'TOM_008', 'TOM_009', 'TOM_010', 'TOM_011')
   OR codigo LIKE 'AQR[_]0%';
GO
