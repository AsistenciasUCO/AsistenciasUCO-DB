USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_admitir_estudiante (CULM-001 D.4, HU156; CONTRACT §5.2, SUPUESTO-D-07, SUPUESTO-D-11)
--
-- El ADMINISTRADOR crea (o reutiliza) un estudiante y lo vincula a un programa de SU institucion, sin matricularlo en grupos.
-- Orden: correlacion -> ejecutor (GEN_002) -> RBAC ADMINISTRADOR -> programa activo de su institucion (ADS_003) -> lectura bloqueada
-- (UPDLOCK, HOLDLOCK) de Usuario por documento y por correo -> documento y correo de personas distintas (ADS_004) -> en alta nueva:
-- correo institucional (ADS_005) y contrasena inicial (ADS_006) -> ya admitido en el programa (ADS_002) -> escrituras: Usuario
-- (usp_sincronizar_usuario_interno, solo si no existe), Estudiante (usp_sincronizar_estudiante_interno, solo si no existe) y
-- EstudiantePrograma. Todos los rechazos de negocio ocurren ANTES de escribir; un error del motor revierte lo escrito (transaccion
-- propia o savepoint). Persona existente (mismo documento y correo): no se revalida el dominio ni se pide contrasena (D5).
-- El vinculo se inserta aqui y no con usp_registrar_estudiante_en_programa_interno: ese nucleo resuelve la institucion del
-- estudiante desde uv_estudiante, que exige un programa, asi que fallaria para un estudiante sin programa.
-- @password es el HASH que arma el backend (nunca texto plano); no se escribe en ningun mensaje.
-- Resultset: MUTATION_COMMAND_RESULTSET (4 columnas canonicas) + idUsuario, idEstudiante, esUsuarioNuevo, esEstudianteNuevo
-- (nulos si falla, salvo ADS_002 que devuelve la persona ya admitida para que el backend repare su cuenta de identidad).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_admitir_estudiante]
(
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50) = NULL,
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50) = NULL,
    @correo                  NVARCHAR(255),
    @password                NVARCHAR(500) = NULL,
    @idPrograma              UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @correoNormalizado        NVARCHAR(255) = LOWER(TRIM(@correo));
    DECLARE @passwordNormalizado      NVARCHAR(500) = NULLIF(TRIM(@password), N'');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @idInstitucion           UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorDocumento   UNIQUEIDENTIFIER;
    DECLARE @idUsuarioPorCorreo      UNIQUEIDENTIFIER;
    DECLARE @idUsuarioResultado      UNIQUEIDENTIFIER;
    DECLARE @idEstudianteResultado   UNIQUEIDENTIFIER;
    DECLARE @esUsuarioNuevo          BIT = 0;
    DECLARE @esEstudianteNuevo       BIT = 0;
    DECLARE @dominioInstitucional    NVARCHAR(255);
    DECLARE @devolverPersona         BIT = 0;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @escrituraRealizada         BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: ejecutor obligatorio (GEN_002)
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC ADMINISTRADOR
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

        -- PASO 4: programa activo de la institucion del administrador (ADS_003; indistinguible de uno inexistente)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idInstitucion = a.institucion
            FROM dbo.Administrador a
            WHERE a.usuario = @idUsuarioEjecutorDefecto
            ORDER BY a.id;

            IF @idInstitucion IS NULL
               OR NOT EXISTS (SELECT 1 FROM dbo.uv_programa p
                              WHERE p.id = @idProgramaDefecto AND p.idInstitucion = @idInstitucion AND p.estaActivoPrograma = 1)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_003',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: transaccion (propia o savepoint) y lectura bloqueada de la persona por documento y por correo
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
                SAVE TRANSACTION sp_admitir_estudiante;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioPorDocumento = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.tipoIdIdentificacion = @idTipoIdIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion;

            SELECT TOP 1 @idUsuarioPorCorreo = u.id
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE u.correo = @correoNormalizado;

            -- ADS_004: documento y correo deben ser de la misma persona (ambos inexistentes o ambos del mismo usuario)
            IF (@idUsuarioPorDocumento IS NULL AND @idUsuarioPorCorreo IS NOT NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorCorreo IS NULL)
               OR (@idUsuarioPorDocumento IS NOT NULL AND @idUsuarioPorDocumento <> @idUsuarioPorCorreo)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
            ELSE
            BEGIN
                SET @idUsuarioResultado = @idUsuarioPorDocumento;
            END

            -- Alta nueva: correo institucional (ADS_005) y contrasena inicial (ADS_006)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @dominioInstitucional = dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE');
                IF dbo.ufn_correo_cumple_dominio_institucional(@correoNormalizado, @dominioInstitucional) = 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_005', @p_param1 = @dominioInstitucional,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE IF @passwordNormalizado IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_006',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END

            -- Persona existente: estudiante y vinculo previos (ADS_002 si ya esta admitida en el programa)
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NOT NULL
            BEGIN
                SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                IF @idEstudianteResultado IS NOT NULL
                   AND EXISTS (SELECT 1 FROM dbo.EstudiantePrograma ep
                               WHERE ep.estudiante = @idEstudianteResultado AND ep.programa = @idProgramaDefecto)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ADS_002',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                    SET @devolverPersona = 1;
                END
            END

            -- PASO 6: escrituras
            IF @estadoResultado = 1 AND @idUsuarioResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correoNormalizado,
                    @password = @passwordNormalizado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idUsuarioResultado = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;
                    SET @esUsuarioNuevo = 1;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteResultado IS NULL
            BEGIN
                SET @escrituraRealizada = 1;
                EXEC dbo.usp_sincronizar_estudiante_interno
                    @idUsuario = @idUsuarioResultado,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                BEGIN
                    SELECT TOP 1 @idEstudianteResultado = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioResultado;
                    SET @esEstudianteNuevo = 1;
                END
            END

            IF @estadoResultado = 1
            BEGIN
                SET @escrituraRealizada = 1;
                INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
                VALUES (NEWID(), @idEstudianteResultado, @idProgramaDefecto);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'ADS_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- PASO 7: cierre respetando el ownership (rollback solo si hubo escrituras y el resultado es fallido)
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 OR @escrituraRealizada = 0
                        COMMIT TRANSACTION;
                    ELSE
                        ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @escrituraRealizada = 1
                    ROLLBACK TRANSACTION sp_admitir_estudiante;
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
        BEGIN
            ROLLBACK TRANSACTION sp_admitir_estudiante;
        END
        -- Transaccion externa condenada que no nos pertenece: se propaga la excepcion al propietario
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
        SET @devolverPersona = 0;
        SET @esUsuarioNuevo = 0;
        SET @esEstudianteNuevo = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idUsuarioResultado, NULL),
        idEstudiante            = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @idEstudianteResultado, NULL),
        esUsuarioNuevo          = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esUsuarioNuevo, NULL),
        esEstudianteNuevo       = IIF(@estadoResultado = 1 OR @devolverPersona = 1, @esEstudianteNuevo, NULL);
END;
GO
