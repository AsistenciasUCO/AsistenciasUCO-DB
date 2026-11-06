USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: nucleo interno de la matricula atomica por token o PIN de una ventana ACTIVA. Lo invocan las fachadas
-- usp_matricular_estudiante_por_token (autenticado) y usp_registrar_estudiante_por_token_publico (publico). NO se concede
-- EXECUTE al rol de runtime. CONTRACT A2.
--   * @idUsuarioAutenticado NO NULL: modo autenticado: RBAC ESTUDIANTE; el estudiante es el de ese usuario.
--   * @idUsuarioAutenticado NULL: modo publico: crea Usuario (ACTIVO, correoConfirmado = 0) y Estudiante; el correo debe ser
--     institucional (IDENT-001: VCE_001). Documento o correo ya existentes: MQR_005 sin cambios.
--   * Reglas de HU050 via usp_registrar_estudiante_en_grupo_interno (cupo, cruce, duplicado, programa). El estado de la
--     matricula es el parametro MATRICULA_QR/ESTADO_MATRICULA (sin literal quemado), validado ANTES de escribir.
--   * Atomico: la expiracion perezosa de la ventana persiste; el trabajo de negocio se revierte hasta su savepoint ante
--     cualquier falla posterior a la escritura.
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_matricular_por_token]
(
    @idCorrelacion            UNIQUEIDENTIFIER,
    @tokenHash                VARBINARY(32),
    @pin                      NCHAR(6),
    @idUsuarioAutenticado     UNIQUEIDENTIFIER,
    @idTipoIdentificacion     UNIQUEIDENTIFIER,
    @numeroIdentificacion     INT,
    @primerNombre             NVARCHAR(50),
    @segundoNombre            NVARCHAR(50),
    @primerApellido           NVARCHAR(50),
    @segundoApellido          NVARCHAR(50),
    @correo                   NVARCHAR(100),
    @password                 NVARCHAR(500),
    @mensajeUsuarioResultado  NVARCHAR(4000)   OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000)   OUTPUT,
    @estadoResultado          BIT              OUTPUT,
    @idEstudianteResultado    UNIQUEIDENTIFIER OUTPUT,
    @idUsuarioResultado       UNIQUEIDENTIFIER OUTPUT,
    @idGrupoResultado         UNIQUEIDENTIFIER OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idVentana        UNIQUEIDENTIFIER;
    DECLARE @idGrupo          UNIQUEIDENTIFIER;
    DECLARE @idDocenteEmisor  UNIQUEIDENTIFIER;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @parametroRechazo NVARCHAR(255) = NULL;

    DECLARE @idUsuarioTarget    UNIQUEIDENTIFIER = NULL;
    DECLARE @idEstudianteTarget UNIQUEIDENTIFIER = NULL;
    DECLARE @correoNormalizado  NVARCHAR(100)    = LOWER(TRIM(@correo));
BEGIN
    SET NOCOUNT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @idEstudianteResultado = NULL, @idUsuarioResultado = NULL, @idGrupoResultado = NULL;

    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_hu176b_matricular;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: resolver la ventana (UPDLOCK). Puede escribir solo la expiracion perezosa.
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_internal_resolver_token_matricula
                @tokenHash = @tokenHash, @pin = @pin,
                @idVentana = @idVentana OUTPUT, @idGrupo = @idGrupo OUTPUT,
                @idDocenteEmisor = @idDocenteEmisor OUTPUT, @codigoRechazo = @codigoRechazo OUTPUT;
        END

        -- PASO 3: validaciones sin escritura
        DECLARE @codigoMatricula NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_MATRICULA') AS NVARCHAR(10));

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idUsuarioAutenticado IS NOT NULL
        BEGIN
            -- Modo autenticado: el usuario debe ser un ESTUDIANTE
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioAutenticado,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SET @idUsuarioTarget = @idUsuarioAutenticado;
                SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioAutenticado;

                IF @idEstudianteTarget IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'GEN_001', @p_param1 = 'Estudiante',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
            END
        END
        ELSE IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            -- Modo publico: datos obligatorios
            IF @idTipoIdentificacion IS NULL OR @numeroIdentificacion IS NULL OR @primerNombre IS NULL
               OR @primerApellido IS NULL OR @correoNormalizado IS NULL OR @correoNormalizado = N'' OR @password IS NULL
            BEGIN
                SET @codigoRechazo = 'GEN_002';
                SET @parametroRechazo = N'datos de registro';
            END
            -- Persona ya registrada (documento o correo): debe iniciar sesion
            ELSE IF EXISTS (
                SELECT 1 FROM dbo.Usuario u
                WHERE u.correo = @correoNormalizado
                   OR (u.tipoIdIdentificacion = @idTipoIdentificacion AND u.numeroIdentificacion = @numeroIdentificacion)
            )
                SET @codigoRechazo = 'MQR_005';
            -- IDENT-001: el correo de un alta nueva debe ser institucional
            ELSE IF dbo.ufn_correo_cumple_dominio_institucional(@correo, dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE')) = 0
            BEGIN
                SET @codigoRechazo = 'VCE_001';
                SET @parametroRechazo = CAST(dbo.ufn_obtener_parametro('REGISTRO', 'DOMINIO_CORREO_ESTUDIANTE') AS NVARCHAR(255));
            END
        END

        -- Ya matriculado (solo se puede evaluar con estudiante conocido: modo autenticado)
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL AND @idEstudianteTarget IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.EstudianteGrupo eg
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                WHERE eg.estudiante = @idEstudianteTarget AND eg.grupo = @idGrupo AND es.codigo = @codigoMatricula
           )
            SET @codigoRechazo = 'MQR_004';

        -- Cupo, antes de crear nada
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupo,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- Estado de matricula configurado y existente, ANTES de escribir (falla rapida: un parametro mal
        -- configurado no debe dejar usuarios a medias; ademas ROLLBACK no es valido bajo INSERT ... EXEC).
        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = UPPER(TRIM(@codigoMatricula)))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001', @p_param1 = 'Estado de matricula por QR',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Mensaje del rechazo por catalogo
        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo, @p_param1 = @parametroRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: escrituras de negocio bajo un savepoint propio (la expiracion perezosa del paso 2 no se revierte)
        IF @estadoResultado = 1
        BEGIN
            SAVE TRANSACTION sp_hu176b_negocio;

            IF @idEstudianteTarget IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_usuario_interno
                    @idTipoIdIdentificacion = @idTipoIdentificacion,
                    @numeroIdentificacion = @numeroIdentificacion,
                    @primerApellido = @primerApellido,
                    @segundoApellido = @segundoApellido,
                    @primerNombre = @primerNombre,
                    @segundoNombre = @segundoNombre,
                    @correo = @correo,
                    @password = @password,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @estaActivo = 1,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioTarget = u.id FROM dbo.Usuario u WHERE u.correo = @correoNormalizado;

                IF @estadoResultado = 1
                BEGIN
                    EXEC dbo.usp_sincronizar_estudiante_interno
                        @idUsuario = @idUsuarioTarget,
                        @idCorrelacion = @idCorrelacionDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                        @estadoResultado = @estadoResultado OUTPUT;

                    IF @estadoResultado = 1
                        SELECT TOP 1 @idEstudianteTarget = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioTarget;
                END
            END

            IF @estadoResultado = 1 AND @idEstudianteTarget IS NOT NULL
            BEGIN
                EXEC dbo.usp_registrar_estudiante_en_grupo_interno
                    @idEstudiante = @idEstudianteTarget,
                    @idGrupo = @idGrupo,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @codigoEstado = @codigoMatricula,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            IF @estadoResultado = 1
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo SET totalMatriculas = totalMatriculas + 1 WHERE id = @idVentana;
            END
            ELSE IF XACT_STATE() = 1
            BEGIN
                -- Falla despues de escribir: se revierte solo el trabajo de negocio
                ROLLBACK TRANSACTION sp_hu176b_negocio;
                SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
            END
        END

        -- PASO 5: cierre de la transaccion propia (confirma tambien la expiracion perezosa)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
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
            ROLLBACK TRANSACTION sp_hu176b_matricular;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SELECT @idUsuarioTarget = NULL, @idEstudianteTarget = NULL;
    END CATCH

    IF @estadoResultado = 1
        SELECT @idEstudianteResultado = @idEstudianteTarget, @idUsuarioResultado = @idUsuarioTarget, @idGrupoResultado = @idGrupo;
END;
GO
