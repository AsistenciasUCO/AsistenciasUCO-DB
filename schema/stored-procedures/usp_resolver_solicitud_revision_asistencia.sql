USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

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

    DECLARE @docenteTitularGrupo UNIQUEIDENTIFIER;
    DECLARE @idAsistencia        UNIQUEIDENTIFIER;
    DECLARE @codigoEstadoNuevo   NVARCHAR(5);
    DECLARE @idEstadoNuevo       UNIQUEIDENTIFIER;
    DECLARE @transaccionPropia   BIT = 0;
    DECLARE @savepointCreado     BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
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
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de existencia de la solicitud y recuperación de docente titular
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @docenteTitularGrupo = g.docente,
                @idAsistencia = sra.asistencia
            FROM dbo.SolicitudRevisionAsistencia sra
            INNER JOIN dbo.Asistencia ast ON sra.asistencia = ast.id
            INNER JOIN dbo.Sesion s ON ast.sesion = s.id
            INNER JOIN dbo.Grupo g ON s.grupo = g.id
            WHERE sra.id = @idSolicitudDefecto;

            IF @docenteTitularGrupo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002',
                    @p_param1 = 'SolicitudRevisionAsistencia',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
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
        END

        -- PASO 3: Mapeo estricto de accion a estado del catalogo (APROBADA -> A, RECHAZADA -> R). Sin fallback (TD-057).
        IF @estadoResultado = 1 AND @accionDefecto NOT IN ('APROBADA', 'RECHAZADA')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'accion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            SET @codigoEstadoNuevo = CASE WHEN @accionDefecto = 'APROBADA' THEN 'A' ELSE 'R' END;

            SELECT TOP 1 @idEstadoNuevo = id
            FROM dbo.Estado
            WHERE codigo = @codigoEstadoNuevo;

            IF @idEstadoNuevo IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'CAT_001',
                    @p_param1 = @codigoEstadoNuevo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            -- Ownership transaccional: propia si no hay transaccion externa; savepoint si la hay (nunca commit ajeno).
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_resolver_solicitud_revision;
                SET @savepointCreado = 1;
            END

            UPDATE dbo.SolicitudRevisionAsistencia
            SET estado = @idEstadoNuevo,
                justificacionRespuesta = CASE WHEN @respuestaDefecto IS NOT NULL THEN @respuestaDefecto ELSE '' END
            WHERE id = @idSolicitudDefecto;

            IF @accionDefecto = 'APROBADA'
            BEGIN
                UPDATE dbo.DetalleAsistencia
                SET asistio = 1
                WHERE asistencia = @idAsistencia;
            END

            IF @transaccionPropia = 1 AND XACT_STATE() = 1
            BEGIN
                COMMIT TRANSACTION;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- Rollback solo de lo que este SP posee: su transaccion o su savepoint (nunca la transaccion externa).
        SET @estadoTransaccionCatch = XACT_STATE();

        IF @transaccionPropia = 1 AND @estadoTransaccionCatch <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_resolver_solicitud_revision;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar al propietario.
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
