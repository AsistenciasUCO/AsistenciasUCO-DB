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
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @hoyLocal = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

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

        IF @estadoResultado = 1
            SET @codigoRechazo =
                CASE
                    WHEN @accionNormalizada IS NULL OR @accionNormalizada NOT IN (N'ACEPTAR', N'RECHAZAR') THEN 'SIG_009'
                    WHEN @accionNormalizada = N'RECHAZAR' AND (@motivoNormalizado IS NULL OR LEN(@motivoNormalizado) > 500) THEN 'SIG_010'
                END;

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
                SELECT @capacidad = g.cantidadEstudiantes, @fechaFinPeriodo = pa.fechaFin
                FROM dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
                WHERE g.id = @idGrupo;

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
                        SET @codigoRechazo = 'SIG_013';
                    ELSE
                    BEGIN
                        UPDATE dbo.SolicitudIngresoGrupo SET estado = @estadoEspera WHERE id = @idSolicitudDefecto;
                        SET @codigoEstadoResultante = 'E';
                        SET @codigoExito = 'SIG_012';
                    END
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
                IF @estadoResultado = 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION;
                ELSE IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1 AND @estadoResultado = 0 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_resolver_solicitud_ingreso;
        END

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
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0 ROLLBACK TRANSACTION;
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
