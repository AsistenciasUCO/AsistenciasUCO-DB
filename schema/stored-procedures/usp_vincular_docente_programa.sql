USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU091: vincula un docente al programa del coordinador. Tres modos excluyentes:
--   (a) @idDocente        docente existente (p. ej. de otro programa de la misma institucion)
--   (b) @idUsuario        usuario existente que aun no es docente
--   (c) datos de persona  alta nueva (usuario + docente + vinculo); documento/correo existentes => DOC_003
-- RBAC COORDINADOR + titularidad PROGRAMA se validan DENTRO del SP. @password es el HASH (nunca texto plano).
-- Una sola transaccion con ownership (transaccion propia o savepoint si el llamador ya tiene una).
CREATE OR ALTER PROCEDURE [dbo].[usp_vincular_docente_programa]
(
    @idDocente              UNIQUEIDENTIFIER = NULL,
    @idUsuario              UNIQUEIDENTIFIER = NULL,
    @idTipoIdentificacion   UNIQUEIDENTIFIER = NULL,
    @numeroIdentificacion   INT              = NULL,
    @primerNombre           NVARCHAR(50)     = NULL,
    @segundoNombre          NVARCHAR(50)     = NULL,
    @primerApellido         NVARCHAR(50)     = NULL,
    @segundoApellido        NVARCHAR(50)     = NULL,
    @correo                 NVARCHAR(100)    = NULL,
    @password               NVARCHAR(500)    = NULL,
    @idTipoVinculacion      UNIQUEIDENTIFIER,
    @idPrograma             UNIQUEIDENTIFIER,
    @idCorrelacion          UNIQUEIDENTIFIER,
    @idUsuarioEjecutor      UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @modoDocente BIT = IIF(@idDocente IS NULL, 0, 1);
    DECLARE @modoUsuario BIT = IIF(@idUsuario IS NULL, 0, 1);
    DECLARE @modoNuevo   BIT = IIF(@numeroIdentificacion IS NULL AND @correo IS NULL AND @idTipoIdentificacion IS NULL
                                   AND @primerNombre IS NULL AND @primerApellido IS NULL AND @password IS NULL, 0, 1);
    DECLARE @idUsuarioResuelto  UNIQUEIDENTIFIER;
    DECLARE @idDocenteResuelto  UNIQUEIDENTIFIER;
    DECLARE @idInstitucion      UNIQUEIDENTIFIER;
    DECLARE @correoNormalizado  NVARCHAR(100) = LOWER(TRIM(@correo));

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

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

        -- PASO 2: ejecutor obligatorio
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: RBAC COORDINADOR
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: titularidad sobre el programa
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4B: programa activo
        IF @estadoResultado = 1
        BEGIN
            SELECT @idInstitucion = idInstitucion FROM dbo.uv_programa WHERE id = @idProgramaDefecto AND estaActivoPrograma = 1;
            IF @idInstitucion IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PROG_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: exactamente un modo (DOC_005)
        IF @estadoResultado = 1 AND (CAST(@modoDocente AS INT) + CAST(@modoUsuario AS INT) + CAST(@modoNuevo AS INT)) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 6: tipo de vinculacion antes de tocar datos (DOC_004)
        IF @estadoResultado = 1
           AND (@idTipoVinculacion IS NULL
                OR NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 7: validaciones de solo lectura ANTES de abrir la transaccion (sin escrituras no hay rollback que hacer)
        IF @estadoResultado = 1
        BEGIN
            IF @modoNuevo = 1
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.uv_usuario WHERE numeroIdentificacion = @numeroIdentificacion OR correo = @correoNormalizado)
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_003',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END
            ELSE IF @modoUsuario = 1
            BEGIN
                SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE id = @idUsuario AND estaActivoUsuario = 1;
                IF @idUsuarioResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
                ELSE
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END
            ELSE
            BEGIN
                SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE id = @idDocente AND estaActivoUsuario = 1;
                IF @idDocenteResuelto IS NULL
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'DOC_001',
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @estadoResultado = 0;
                END
            END

            -- El docente no puede pertenecer solo a otra institucion
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion <> @idInstitucion)
               AND NOT EXISTS (SELECT 1 FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteResuelto AND idInstitucion = @idInstitucion)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            -- Vinculo duplicado
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE docente = @idDocenteResuelto AND programa = @idProgramaDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_006',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @estadoResultado = 0;
            END

            IF @estadoResultado = 0
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 8: escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_vincular_docente_programa;
                SET @savepointCreado = 1;
            END

            -- 8A: persona nueva
            IF @modoNuevo = 1
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
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;

                IF @estadoResultado = 1
                    SELECT TOP 1 @idUsuarioResuelto = id FROM dbo.uv_usuario WHERE correo = @correoNormalizado;
            END

            -- 8B: rol Docente para la persona (modos nuevo y usuario sin rol)
            IF @estadoResultado = 1 AND @idDocenteResuelto IS NULL
            BEGIN
                EXEC dbo.usp_sincronizar_docente_interno
                    @idUsuario = @idUsuarioResuelto,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
                IF @estadoResultado = 1
                    SELECT TOP 1 @idDocenteResuelto = id FROM dbo.uv_docente_identidad WHERE idUsuario = @idUsuarioResuelto;
            END

            -- 8C: vinculo (revalida tipo y unicidad bajo UPDLOCK, HOLDLOCK)
            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_vincular_docente_programa_interno
                    @idDocente = @idDocenteResuelto,
                    @idPrograma = @idProgramaDefecto,
                    @idTipoVinculacion = @idTipoVinculacion,
                    @idCorrelacion = @idCorrelacionDefecto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                    @estadoResultado = @estadoResultado OUTPUT;
            END

            -- PASO 9: cierre respetando ownership
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                BEGIN
                    IF @estadoResultado = 1 COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
                END
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
            ELSE IF @savepointCreado = 1
            BEGIN
                IF XACT_STATE() = 1 AND @estadoResultado = 0
                    ROLLBACK TRANSACTION usp_vincular_docente_programa;
            END
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
            ROLLBACK TRANSACTION usp_vincular_docente_programa;
        END

        -- Transaccion externa doomed: no nos pertenece, se propaga al propietario.
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

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
