-- ============================================================================
-- MIGRACION DOWN 20: CULM-001 D.1 - retira el plazo de excusas (CONTRACT D §2.2, §14.2 D-RB-01)
--   1. Si D.2 esta aplicada (existe usp_radicar_solicitud_revision_asistencia_v3 o usp_internal_radicar_solicitud_revision) aborta
--      con THROW 50020 SIN cambiar nada: v2 es un objeto compartido y los down se aplican en orden inverso de mezcla.
--   2. Restaura el texto anterior a D.1 (literal) de usp_radicar_solicitud_revision_asistencia y de su v2.
--   3. DROP de la vista, el SP de consulta, el interno y la funcion; borra los mensajes REV_020/REV_025. Idempotente.
-- ============================================================================
:on error exit
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.usp_radicar_solicitud_revision_asistencia_v3', N'P') IS NOT NULL
   OR OBJECT_ID(N'dbo.usp_internal_radicar_solicitud_revision', N'P') IS NOT NULL
    THROW 50020, 'CULM001_D1_DOWN: D.2 esta aplicada (existe usp_radicar_solicitud_revision_asistencia_v3 o usp_internal_radicar_solicitud_revision); revierta primero la migracion 21.', 1;
GO
PRINT 'MIGRACION 20 DOWN: restaura v1/v2 anteriores a D.1';
GO
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia.sql (texto anterior a D.1)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @soporteNombre      NVARCHAR(250),
    @soporteUrl         NVARCHAR(500),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @categoriaDefecto         NVARCHAR(50)     = TRIM(@categoria);
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);
    DECLARE @soporteNombreDefecto     NVARCHAR(250)    = TRIM(@soporteNombre);
    DECLARE @soporteUrlDefecto        NVARCHAR(500)    = TRIM(@soporteUrl);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;

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
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validar existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validar existencia de la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validar pertenencia del estudiante a la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: Radicación atómica transaccional de la solicitud
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            BEGIN TRANSACTION;

            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                CAST(CURRENT_TIMESTAMP AS DATE),
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revisión de asistencia radicada por estudiante.' END,
                ''
            );

            COMMIT TRANSACTION;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
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
-- ---- schema/stored-procedures/usp_radicar_solicitud_revision_asistencia_v2.sql (texto anterior a D.1)
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_radicar_solicitud_revision_asistencia_v2  (LB-004D, W2)
--
-- Radica la solicitud de revision y, si se indica @idArchivoSoporte, vincula el soporte
-- (DRAFT -> ATTACHED) en la MISMA transaccion. La v1 permanece intacta.
--
--   * Sin @soporteNombre/@soporteUrl: la v2 no confia en datos de soporte del cliente.
--   * Verifica que @idEstudiante pertenezca a @idUsuarioEjecutor (defensa en profundidad, H-01).
--   * El soporte es opcional: sin @idArchivoSoporte el comportamiento es el de la v1.
--   * Soporte inexistente, ajeno, ya vinculado u huerfano => ARC_001 identico, sin escritura.
--   * Reintento con la misma correlacion tras un exito => exito idempotente (sin segunda solicitud).
--   * Carrera por el mismo fileId: el UPDLOCK sobre la fila serializa; la segunda ve ATTACHED => ARC_001.
--   * `fecha` conserva la semantica de la v1 (DATE de calendario local), no es un instante UTC.
--
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas).
-- Ownership transaccional: transaccion propia o SAVE TRANSACTION si el llamador ya tiene una.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_radicar_solicitud_revision_asistencia_v2]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @categoria          NVARCHAR(50),
    @justificacion      NVARCHAR(MAX),
    @idArchivoSoporte   UNIQUEIDENTIFIER = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidVacio                UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(NULL, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @justificacionDefecto     NVARCHAR(MAX)    = TRIM(@justificacion);

    DECLARE @idAsistencia         UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @nuevaSolicitudId     UNIQUEIDENTIFIER = NEWID();
    DECLARE @nombreSolicitud      NVARCHAR(50);
    DECLARE @idEstadoPendiente    UNIQUEIDENTIFIER;

    DECLARE @tieneSoporte         BIT = IIF(@idArchivoSoporte IS NULL, 0, 1);
    DECLARE @propietarioSoporte   UNIQUEIDENTIFIER;
    DECLARE @estadoSoporte        VARCHAR(10);
    DECLARE @correlacionAdjuncion UNIQUEIDENTIFIER;
    DECLARE @esReintento          BIT = 0;
    DECLARE @filasActualizadas    INT;
    DECLARE @escrituraRealizada   BIT = 0;

    DECLARE @conteoTransaccionesInicial INT;
    DECLARE @transaccionPropia    BIT = 0;
    DECLARE @savepointCreado      BIT = 0;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: Validacion de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (no nulo, no GUID vacio)
        IF @estadoResultado = 1 AND (@idUsuarioEjecutor IS NULL OR @idUsuarioEjecutorDefecto = @guidVacio)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Perfil RBAC ESTUDIANTE
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Existencia del estudiante
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_exista_por_id_interno
                @idEstudiante = @idEstudianteDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: El estudiante debe corresponder al ejecutor autenticado (H-01)
        IF @estadoResultado = 1
           AND NOT EXISTS (
                SELECT 1 FROM dbo.Estudiante e
                WHERE e.id = @idEstudianteDefecto AND e.usuario = @idUsuarioEjecutorDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ARC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: Existencia de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 7: Matricula: el estudiante pertenece al grupo de la sesion
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 8: Transaccion propia (o savepoint si el llamador ya tiene una)
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
                SAVE TRANSACTION sp_lb004d_radicar_v2;
                SET @savepointCreado = 1;
            END
        END

        -- PASO 9: Soporte opcional. UPDLOCK serializa radicaciones concurrentes con el mismo fileId.
        IF @estadoResultado = 1 AND @tieneSoporte = 1
        BEGIN
            SELECT @propietarioSoporte   = a.usuarioPropietario,
                   @estadoSoporte        = a.estado,
                   @correlacionAdjuncion = a.idCorrelacionAdjuncion
            FROM dbo.ArchivoSoporte a WITH (UPDLOCK, ROWLOCK)
            WHERE a.id = @idArchivoSoporte;

            IF @propietarioSoporte IS NULL OR @propietarioSoporte <> @idUsuarioEjecutorDefecto
            BEGIN
                SET @estadoResultado = 0;
            END
            ELSE IF @estadoSoporte = 'ATTACHED' AND @correlacionAdjuncion = @idCorrelacionDefecto
            BEGIN
                SET @esReintento = 1;
            END
            ELSE IF @estadoSoporte <> 'DRAFT'
            BEGIN
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ARC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

        -- PASO 10: Creacion de la solicitud y vinculo atomico del soporte
        IF @estadoResultado = 1 AND @esReintento = 0
        BEGIN
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.Sesion s
            INNER JOIN dbo.EstudianteGrupo eg ON eg.grupo = s.grupo
            WHERE s.id = @idSesionDefecto AND eg.estudiante = @idEstudianteDefecto;

            SELECT TOP 1 @idAsistencia = id
            FROM dbo.Asistencia
            WHERE estudianteGrupo = @idEstudianteGrupo AND sesion = @idSesionDefecto;

            SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado WHERE codigo IN ('P', 'PEND') ORDER BY id ASC;
            IF @idEstadoPendiente IS NULL
            BEGIN
                SELECT TOP 1 @idEstadoPendiente = id FROM dbo.Estado ORDER BY id ASC;
            END

            SET @nombreSolicitud = CONCAT('REC-', UPPER(SUBSTRING(CAST(@nuevaSolicitudId AS VARCHAR(36)), 1, 8)));

            SET @escrituraRealizada = 1;
            IF @idAsistencia IS NULL
            BEGIN
                SET @idAsistencia = NEWID();
                INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
                VALUES (@idAsistencia, @idEstudianteGrupo, @idSesionDefecto);
            END

            INSERT INTO dbo.SolicitudRevisionAsistencia (
                id, nombre, asistencia, fecha, estado,
                justificacionSolicitud, justificacionRespuesta
            )
            VALUES (
                @nuevaSolicitudId,
                @nombreSolicitud,
                @idAsistencia,
                CAST(CURRENT_TIMESTAMP AS DATE),
                @idEstadoPendiente,
                CASE WHEN @justificacionDefecto IS NOT NULL AND @justificacionDefecto <> '' THEN @justificacionDefecto ELSE 'Solicitud de revision de asistencia radicada por estudiante.' END,
                ''
            );

            IF @tieneSoporte = 1
            BEGIN
                UPDATE dbo.ArchivoSoporte
                SET estado = 'ATTACHED',
                    solicitudRevisionAsistencia = @nuevaSolicitudId,
                    fechaAdjuncionUtc = SYSUTCDATETIME(),
                    fechaCambioEstadoUtc = SYSUTCDATETIME(),
                    idCorrelacionAdjuncion = @idCorrelacionDefecto
                WHERE id = @idArchivoSoporte
                  AND estado = 'DRAFT'
                  AND usuarioPropietario = @idUsuarioEjecutorDefecto;
                SET @filasActualizadas = @@ROWCOUNT;

                -- Postcondicion verificada por lectura (no solo @@ROWCOUNT): el soporte quedo vinculado a ESTA solicitud.
                IF @filasActualizadas <> 1
                   OR NOT EXISTS (SELECT 1 FROM dbo.ArchivoSoporte a
                                  WHERE a.id = @idArchivoSoporte AND a.estado = 'ATTACHED'
                                    AND a.solicitudRevisionAsistencia = @nuevaSolicitudId)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ARC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'SolicitudRevisionAsistencia',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 11: Finalizacion respetando ownership: commit solo si el resultado es exitoso
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
            BEGIN
                IF @estadoResultado = 1
                    COMMIT TRANSACTION;
                ELSE
                    ROLLBACK TRANSACTION;
            END
            ELSE IF XACT_STATE() = -1
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            -- Solo se revierte lo escrito (un rechazo previo a las escrituras no deja nada que deshacer).
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END
    END TRY
    BEGIN CATCH
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_lb004d_radicar_v2;
        END

        -- Transaccion externa condenada que no nos pertenece: propagar la excepcion original al propietario
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

    -- BLOQUE FINAL: Retorno unificado de resultados (4 columnas canonicas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO

-- ---- retiro de los objetos de D.1 (la vista depende de la funcion; v1/v2 ya no usan el validador)
IF OBJECT_ID(N'dbo.usp_consultar_sesiones_materia_estudiante', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_consultar_sesiones_materia_estudiante];
GO
IF OBJECT_ID(N'dbo.uv_sesion_estudiante_reclamo', N'V') IS NOT NULL DROP VIEW [dbo].[uv_sesion_estudiante_reclamo];
GO
IF OBJECT_ID(N'dbo.usp_internal_validar_plazo_justificacion', N'P') IS NOT NULL DROP PROCEDURE [dbo].[usp_internal_validar_plazo_justificacion];
GO
IF OBJECT_ID(N'dbo.ufn_calcular_fecha_limite_justificacion', N'FN') IS NOT NULL DROP FUNCTION [dbo].[ufn_calcular_fecha_limite_justificacion];
GO
DELETE FROM [dbo].[CatalogoMensajeUsuario] WHERE codigo IN ('REV_020', 'REV_025');
DELETE FROM [dbo].[CatalogoMensajeTecnico] WHERE codigo IN ('REV_020', 'REV_025');
GO
