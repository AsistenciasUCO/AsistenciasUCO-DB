USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.8.1, DEC-013, [SUPUESTO-B-04], [SUPUESTO-B-14]): toma vigente.
--   * @idToma (opcional): toma explicita (lote por toma, QR, cierre); debe pertenecer a @idSesion (TOM_001).
--   * @idToma NULL (lote congelado y llamadores de 7 parametros): la toma ABIERTA de la sesion; si no hay, la de mayor numero;
--     si la sesion no tiene tomas, crea la toma 1 implicita y CERRADA (MANUAL, docente del ejecutor o del grupo).
--   * Detalle unico por (asistencia, toma); codigo desde dbo.seq_detalle_asistencia_codigo; registradoPorEstudiante y
--     fechaRegistroUtc. @soloSiNoExiste = 1 no sobrescribe un detalle existente (QR idempotente y cierre): @detalleCreado = 0.
--   * Orden de bloqueos: Sesion (lo toma el llamador) -> EstudianteGrupo -> TomaAsistencia -> Asistencia -> DetalleAsistencia.
CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_asistencia_estudiante_interno]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idSesion                UNIQUEIDENTIFIER,
    @codigoEstado            NVARCHAR(5),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idToma                  UNIQUEIDENTIFIER = NULL,
    @registradoPorEstudiante BIT = 0,
    @soloSiNoExiste          BIT = 0,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL,
    @detalleCreado           BIT = NULL OUTPUT
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
    DECLARE @idTomaResuelta          UNIQUEIDENTIFIER;
    DECLARE @idDocenteApertura       UNIQUEIDENTIFIER;
    DECLARE @registradoPorEstudianteDefecto BIT = IIF(@registradoPorEstudiante IS NULL, 0, @registradoPorEstudiante);
    DECLARE @soloSiNoExisteDefecto   BIT = IIF(@soloSiNoExiste IS NULL, 0, @soloSiNoExiste);
    DECLARE @ahoraUtc                DATETIME2(0) = SYSUTCDATETIME();

    -- Inicialización de respuesta desde parámetros del catálogo
    SELECT 
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1,
        @detalleCreado = 0;

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

        -- PASO 4.5 (CULM-001 B.2): toma explicita o toma vigente de la sesion
        IF @estadoResultado = 1
        BEGIN
            -- Registro del estudiante (QR): bloqueo compartido de la toma (NB-4); el cierre (U/X) sigue serializado
            IF @idToma IS NOT NULL AND @registradoPorEstudianteDefecto = 1 AND @soloSiNoExisteDefecto = 1
                SELECT @idTomaResuelta = t.id
                FROM dbo.TomaAsistencia t WITH (HOLDLOCK)
                WHERE t.id = @idToma AND t.sesion = @idSesionDefecto;
            ELSE IF @idToma IS NOT NULL
                SELECT @idTomaResuelta = t.id
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.id = @idToma AND t.sesion = @idSesionDefecto;

            IF @idToma IS NOT NULL
            BEGIN

                IF @idTomaResuelta IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'TOM_001',
                        @p_param1 = @idToma,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idTomaResuelta = t.id
                FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.sesion = @idSesionDefecto
                ORDER BY IIF(t.fechaCierreUtc IS NULL, 0, 1), t.numero DESC;

                IF @idTomaResuelta IS NULL
                BEGIN
                    SELECT @idDocenteApertura = d.id FROM dbo.Docente d WHERE d.usuario = @idUsuarioEjecutor;
                    IF @idDocenteApertura IS NULL
                        SELECT @idDocenteApertura = g.docente FROM dbo.Grupo g WHERE g.id = @idGrupo;

                    SET @idTomaResuelta = NEWID();
                    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc,
                                                    fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
                    SELECT @idTomaResuelta, @idSesionDefecto, 1, m.id, e.id, 1, @idDocenteApertura, @ahoraUtc, @ahoraUtc, 0,
                           @idCorrelacionDefecto, @idCorrelacionDefecto
                    FROM dbo.ModoTomaAsistencia m
                    CROSS JOIN dbo.EstadoTomaAsistencia e
                    WHERE m.usaCodigoQr = 0 AND e.estaAbierta = 0;

                    IF @@ROWCOUNT <> 1
                        THROW 52501, 'CULM001_B2_CATALOGO_INCONSISTENTE: faltan ModoTomaAsistencia(usaCodigoQr = 0) o EstadoTomaAsistencia(estaAbierta = 0).', 1;
                END
            END
        END

        -- PASO 5: Sincronización de cabecera y detalle de asistencia (por toma)
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
            WHERE asistencia = @idAsistencia
              AND toma = @idTomaResuelta;

            IF @idDetalleAsistencia IS NULL
            BEGIN
                SET @idDetalleAsistencia = NEWID();

                INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin,
                                                   toma, registradoPorEstudiante, fechaRegistroUtc)
                VALUES (@idDetalleAsistencia, NEXT VALUE FOR dbo.seq_detalle_asistencia_codigo, @idAsistencia, @asistio, @idRazonCausa,
                        @fechaInicioSesion, @fechaFinSesion, @idTomaResuelta, @registradoPorEstudianteDefecto, @ahoraUtc);
                SET @detalleCreado = 1;
            END
            ELSE IF @soloSiNoExisteDefecto = 0
            BEGIN
                UPDATE dbo.DetalleAsistencia
                SET asistio = @asistio,
                    razonCausa = @idRazonCausa,
                    fechaHoraInicio = @fechaInicioSesion,
                    fechaHoraFin = @fechaFinSesion,
                    fechaRegistroUtc = @ahoraUtc
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
