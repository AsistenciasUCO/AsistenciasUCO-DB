USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cambiar_estado_decano (CULM-001 A.2-8; F-ADM-002; CONTRACT §8.2.3 A2-DB-4)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando canonico + idUsuario, personaSinRolesActivos y estaActivoDecano
-- (igual que usp_cambiar_estado_coordinador) para que el backend sincronice la cuenta de identidad.
-- El ADMINISTRADOR activa o desactiva el rol de decano (Decano.estado, A2-C5) de una facultad de SU institucion:
--   * RBAC ADMINISTRADOR (SEC_001). Ambito dentro del SP: la facultad del decano es de la institucion del
--     administrador; si no (o el decano no existe), DEC_001 (404). Un decano sin facultad asignada se gestiona (F-A-S03).
--   * @estaActivo NULL invierte el estado actual (la ruta HTTP es un toggle). Idempotente.
--   * DEC_002 (409): no se desactiva al decano de una facultad con algun Programa activo (lectura con bloqueo).
--   * Regla D1: personaSinRolesActivos se calcula DESPUES de actualizar Decano.estado (uv_usuario_perfil ya filtrada);
--     Usuario.estado pasa a 0 solo si la persona no conserva otro rol activo y vuelve a 1 al reactivar.
-- SET XACT_ABORT ON; transaccion propia o savepoint; un rechazo de negocio no escribe ni hace ROLLBACK.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cambiar_estado_decano]
(
    @idDecano          UNIQUEIDENTIFIER,
    @estaActivo        BIT = NULL,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @idUsuarioDecano         UNIQUEIDENTIFIER = NULL;
    DECLARE @estadoActual            BIT = NULL;
    DECLARE @estadoDestino           BIT = NULL;
    DECLARE @personaSinRolesActivos  BIT = 0;
    DECLARE @nombrePrograma          NVARCHAR(200) = NULL;
    DECLARE @codigoRechazo           VARCHAR(20) = NULL;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @mutacionRealizada          BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
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

        -- PASO 2: RBAC ADMINISTRADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: transaccion; decano de una facultad de la institucion del administrador (DEC_001), bajo bloqueo
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
                SAVE TRANSACTION sp_cambiar_estado_decano;
                SET @savepointCreado = 1;
            END

            SELECT @idUsuarioDecano = d.usuario, @estadoActual = d.estado
            FROM dbo.Decano d WITH (UPDLOCK, HOLDLOCK)
            WHERE d.id = @idDecano
              -- F-A-S03: un decano creado sin facultad aun no pertenece a ninguna institucion y figura en el listado
              -- del administrador; se gestiona igual. Con facultad, alguna debe ser de la institucion del administrador.
              AND (EXISTS (SELECT 1 FROM dbo.Facultad f
                           INNER JOIN dbo.Administrador ad ON ad.institucion = f.institucion
                           WHERE f.decano = d.id AND ad.usuario = @idUsuarioEjecutor)
                   OR NOT EXISTS (SELECT 1 FROM dbo.Facultad f WHERE f.decano = d.id));

            IF @idUsuarioDecano IS NULL
                SET @codigoRechazo = 'DEC_001';
            ELSE
            BEGIN
                SET @estadoDestino = IIF(@estaActivo IS NULL, IIF(@estadoActual = 1, 0, 1), @estaActivo);

                -- DEC_002: no se desactiva al decano de una facultad con algun programa activo
                IF @estadoDestino = 0
                BEGIN
                    SELECT TOP 1 @nombrePrograma = p.nombre
                    FROM dbo.Programa p WITH (UPDLOCK, HOLDLOCK)
                    INNER JOIN dbo.Facultad f ON f.id = p.facultad
                    WHERE f.decano = @idDecano AND p.estado = 1;

                    IF @nombrePrograma IS NOT NULL
                        SET @codigoRechazo = 'DEC_002';
                END

                IF @codigoRechazo IS NULL
                BEGIN
                    UPDATE dbo.Decano SET estado = @estadoDestino WHERE id = @idDecano AND estado <> @estadoDestino;
                    SET @mutacionRealizada = 1;

                    -- D1: despues del cambio (uv_usuario_perfil ya refleja Decano.estado)
                    IF @estadoDestino = 0
                        SET @personaSinRolesActivos = IIF(dbo.ufn_usuario_tiene_roles_activos(@idUsuarioDecano) = 0, 1, 0);

                    IF @estadoDestino = 1 OR @personaSinRolesActivos = 1
                    BEGIN
                        EXEC dbo.usp_cambiar_estado_usuario_interno
                            @idUsuario = @idUsuarioDecano,
                            @estaActivo = @estadoDestino,
                            @idCorrelacion = @idCorrelacionDefecto,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                            @estadoResultado = @estadoResultado OUTPUT;
                    END

                    IF @estadoResultado = 1
                    BEGIN
                        EXEC dbo.usp_obtener_mensaje_catalogo
                            @p_codigo = 'DEC_003', @p_param1 = @idDecano,
                            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    END
                END
            END

            -- Cierre respetando el ownership (revierte solo si escribio y fallo despues)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @mutacionRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1 AND XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                ROLLBACK TRANSACTION sp_cambiar_estado_decano;
        END

        -- PASO 4: mensaje de rechazo por catalogo (sin escrituras)
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @idDecano, @p_param2 = @nombrePrograma,
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
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_cambiar_estado_decano;

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
        idUsuario               = IIF(@estadoResultado = 1, @idUsuarioDecano, NULL),
        personaSinRolesActivos  = IIF(@estadoResultado = 1, @personaSinRolesActivos, CAST(0 AS BIT)),
        estaActivoDecano        = IIF(@estadoResultado = 1, @estadoDestino, NULL);
END;
GO
