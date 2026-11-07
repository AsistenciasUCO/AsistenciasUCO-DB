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
