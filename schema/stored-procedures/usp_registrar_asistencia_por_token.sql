USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_asistencia_por_token (CULM-001 B.2, HU176; CONTRACT §2.8.3, DEC-015, NB-4)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idToma, idSesion, idGrupo, nombreAsignatura,
-- nombreGrupo, numeroSesion, numeroToma, yaRegistrado, fechaRegistroUtc (NULL si estadoResultado = 0).
--
-- El estudiante autenticado (@idUsuarioEjecutor = Usuario.id) registra su asistencia (AN) en la toma del token o del PIN:
--   correlacion -> GEN_002 sin ejecutor -> RBAC ESTUDIANTE -> estudiante del usuario -> resolucion del token/PIN (AQR_007 /
--   AQR_001) -> transaccion -> ventana con ASISTENCIA/TOLERANCIA_MINUTOS y MARGEN_RETARDO_MINUTOS (bloquea Sesion; cancelada
--   SES_010) -> toma abierta (AQR_005) -> matricula A en el grupo de la toma (AQR_004: un estudiante de otro grupo nunca
--   escribe) -> usp_sincronizar_asistencia_estudiante_interno(@idToma, @registradoPorEstudiante = 1, @soloSiNoExiste = 1).
-- Idempotente por (estudiante, toma): si ya habia detalle responde AQR_008 con yaRegistrado = 1 y no cambia una marca previa
-- del docente. Exito AQR_009. La red del campus (CIDR), el interruptor y los limites los aplica el backend antes de llamar.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencia_por_token]
(
    @tokenHash         VARBINARY(32) = NULL,
    @pin               NCHAR(6) = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @toleranciaMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS');
    DECLARE @margenMinutos     INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @codigoPresente    NVARCHAR(5) = CAST(dbo.ufn_obtener_parametro('ASISTENCIA', 'CODIGO_RAZON_PRESENTE') AS NVARCHAR(5));
    DECLARE @codigoActiva      NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_INSCRITA') AS NVARCHAR(10));
    DECLARE @idEstudiante      UNIQUEIDENTIFIER;
    DECLARE @idTokenAsistencia UNIQUEIDENTIFIER;
    DECLARE @idToma            UNIQUEIDENTIFIER;
    DECLARE @idSesion          UNIQUEIDENTIFIER;
    DECLARE @idGrupo           UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo     VARCHAR(20);
    DECLARE @tomaAbierta       BIT;
    DECLARE @detalleCreado     BIT;
    DECLARE @yaRegistrado      BIT;
    DECLARE @fechaRegistro     DATETIME2(0);
    DECLARE @nombreAsignatura  NVARCHAR(200);
    DECLARE @nombreGrupo       NVARCHAR(300);
    DECLARE @numeroSesion      INT;
    DECLARE @numeroToma        SMALLINT;
    DECLARE @codigoMensaje     VARCHAR(20);
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'ESTUDIANTE', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstudiante = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioEjecutorDefecto;

            EXEC dbo.usp_internal_resolver_token_asistencia
                @tokenHash = @tokenHash, @pin = @pin,
                @idTokenAsistencia = @idTokenAsistencia OUTPUT, @idToma = @idToma OUTPUT, @idSesion = @idSesion OUTPUT,
                @idGrupo = @idGrupo OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT;

            IF @codigoRechazo IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoRechazo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_asistencia_por_token;
                SET @savepointCreado = 1;
            END

            -- Ventana con tolerancia y margen (bloquea Sesion; sesion cancelada SES_010)
            EXEC dbo.usp_validar_sesion_ventana_registro_interno
                @idSesion = @idSesion, @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT,
                @toleranciaMinutos = @toleranciaMinutos, @margenMinutos = @margenMinutos;

            IF @estadoResultado = 1
            BEGIN
                SELECT @tomaAbierta = IIF(t.fechaCierreUtc IS NULL, 1, 0), @numeroToma = t.numero
                FROM dbo.TomaAsistencia t WHERE t.id = @idToma;
                IF @tomaAbierta = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_005', @p_param1 = @idToma,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- Matricula A del estudiante en el grupo de la toma: un estudiante de otro grupo nunca escribe
            IF @estadoResultado = 1
               AND (@idEstudiante IS NULL
                    OR NOT EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo e ON e.id = eg.estado
                                   WHERE eg.estudiante = @idEstudiante AND eg.grupo = @idGrupo AND e.codigo = @codigoActiva))
            BEGIN
                SET @p1 = CONVERT(NVARCHAR(36), @idEstudiante);
                SET @p2 = CONVERT(NVARCHAR(36), @idGrupo);
                EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_004', @p_param1 = @p1, @p_param2 = @p2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                    @idEstudiante = @idEstudiante, @idSesion = @idSesion, @codigoEstado = @codigoPresente,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT,
                    @idToma = @idToma, @registradoPorEstudiante = 1, @soloSiNoExiste = 1, @idUsuarioEjecutor = @idUsuarioEjecutorDefecto,
                    @detalleCreado = @detalleCreado OUTPUT;

                IF @estadoResultado = 1
                BEGIN
                    SET @yaRegistrado = IIF(@detalleCreado = 1, 0, 1);
                    SELECT @fechaRegistro = da.fechaRegistroUtc
                    FROM dbo.DetalleAsistencia da
                    INNER JOIN dbo.Asistencia a ON a.id = da.asistencia
                    INNER JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
                    WHERE da.toma = @idToma AND eg.estudiante = @idEstudiante AND a.sesion = @idSesion;
                    SELECT @nombreAsignatura = g.nombreAsignatura, @nombreGrupo = g.nombre, @numeroSesion = s.numero
                    FROM dbo.Sesion s INNER JOIN dbo.uv_grupo g ON g.id = s.grupo
                    WHERE s.id = @idSesion;

                    SET @p1 = CONVERT(NVARCHAR(36), @idEstudiante);
                    SET @p2 = CONVERT(NVARCHAR(36), @idToma);
                    SET @codigoMensaje = IIF(@yaRegistrado = 1, 'AQR_008', 'AQR_009');
                    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = @codigoMensaje, @p_param1 = @p1, @p_param2 = @p2,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0 AND @detalleCreado = 1
                    ROLLBACK TRANSACTION;
                ELSE IF XACT_STATE() = 1
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
            ROLLBACK TRANSACTION sp_asistencia_por_token;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idToma                  = IIF(@estadoResultado = 1, @idToma, NULL),
        idSesion                = IIF(@estadoResultado = 1, @idSesion, NULL),
        idGrupo                 = IIF(@estadoResultado = 1, @idGrupo, NULL),
        nombreAsignatura        = IIF(@estadoResultado = 1, @nombreAsignatura, NULL),
        nombreGrupo             = IIF(@estadoResultado = 1, @nombreGrupo, NULL),
        numeroSesion            = IIF(@estadoResultado = 1, @numeroSesion, NULL),
        numeroToma              = IIF(@estadoResultado = 1, @numeroToma, NULL),
        yaRegistrado            = IIF(@estadoResultado = 1, @yaRegistrado, NULL),
        fechaRegistroUtc        = IIF(@estadoResultado = 1, @fechaRegistro, NULL);
END;
GO
