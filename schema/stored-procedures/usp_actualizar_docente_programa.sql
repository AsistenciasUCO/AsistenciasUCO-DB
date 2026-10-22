USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU092: edita (a) el tipo de vinculacion del vinculo docente-programa y (b) los nombres/apellidos de la persona.
-- Solo se actualizan los parametros no nulos (''/vacio en un segundo nombre o apellido lo limpia). Correo y documento
-- NO se editan aqui (el correo exige sincronizar Keycloak: IAM-001). Los nombres afectan a la persona en todos sus
-- programas. RBAC COORDINADOR + titularidad PROGRAMA + existencia del vinculo se validan DENTRO del SP, y las
-- validaciones de lectura ocurren antes de abrir la transaccion.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_docente_programa]
(
    @idDocente          UNIQUEIDENTIFIER,
    @idPrograma         UNIQUEIDENTIFIER,
    @idTipoVinculacion  UNIQUEIDENTIFIER = NULL,
    @primerNombre       NVARCHAR(50)     = NULL,
    @segundoNombre      NVARCHAR(50)     = NULL,
    @primerApellido     NVARCHAR(50)     = NULL,
    @segundoApellido    NVARCHAR(50)     = NULL,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idDocenteDefecto         UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idDocente, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @pn  NVARCHAR(50) = TRIM(@primerNombre);
    DECLARE @sn  NVARCHAR(50) = TRIM(@segundoNombre);
    DECLARE @pa  NVARCHAR(50) = TRIM(@primerApellido);
    DECLARE @sa  NVARCHAR(50) = TRIM(@segundoApellido);
    DECLARE @idUsuarioDocente UNIQUEIDENTIFIER;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

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
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto, @idEntidadPadre = @idProgramaDefecto,
                @tipoEntidadPadre = 'PROGRAMA', @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

        -- Al menos un campo a actualizar
        IF @estadoResultado = 1 AND @idTipoVinculacion IS NULL AND @pn IS NULL AND @sn IS NULL AND @pa IS NULL AND @sa IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'campo a actualizar',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Existencia del vinculo (docente, programa)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idUsuarioDocente = idUsuario FROM dbo.uv_docente_programa WHERE idDocente = @idDocenteDefecto AND idPrograma = @idProgramaDefecto;
            IF @idUsuarioDocente IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'DOC_008',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- Tipo de vinculacion (cuando viene)
        IF @estadoResultado = 1 AND @idTipoVinculacion IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.uv_tipo_vinculacion WHERE id = @idTipoVinculacion AND estaActivoTipoVinculacion = 1)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'DOC_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Nombres: obligatorios no vacios si vienen; opcionales pueden limpiarse con ''
        IF @estadoResultado = 1
           AND ((@pn IS NOT NULL AND dbo.ufn_validar_texto(@pn) = 0) OR (@pa IS NOT NULL AND dbo.ufn_validar_texto(@pa) = 0))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_003',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1
           AND ((@sn IS NOT NULL AND @sn <> '' AND dbo.ufn_validar_texto(@sn) = 0) OR (@sa IS NOT NULL AND @sa <> '' AND dbo.ufn_validar_texto(@sa) = 0))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- Escrituras en una sola transaccion con ownership
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
                SAVE TRANSACTION usp_actualizar_docente_programa;
                SET @savepointCreado = 1;
            END

            IF @idTipoVinculacion IS NOT NULL
                UPDATE dbo.DocentePrograma SET tipoVinculacion = @idTipoVinculacion
                WHERE docente = @idDocenteDefecto AND programa = @idProgramaDefecto;

            IF @pn IS NOT NULL OR @sn IS NOT NULL OR @pa IS NOT NULL OR @sa IS NOT NULL
                EXEC dbo.usp_actualizar_nombres_usuario_interno
                    @idUsuario = @idUsuarioDocente, @primerNombre = @pn, @segundoNombre = @sn,
                    @primerApellido = @pa, @segundoApellido = @sa;

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_005', @p_param1 = 'Docente',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
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
            ROLLBACK TRANSACTION usp_actualizar_docente_programa;
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
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
