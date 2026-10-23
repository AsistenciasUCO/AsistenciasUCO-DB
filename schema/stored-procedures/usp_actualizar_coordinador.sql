USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU121: edita nombres, apellidos y correo de un coordinador de la facultad del decano ejecutor.
-- Fachada transaccional: valida RBAC y titularidad, y delega la escritura en usp_actualizar_datos_usuario_interno.
-- El documento no se edita. Devuelve idUsuario para que el backend sincronice la cuenta de identidad.
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_coordinador]
(
    @idCoordinador      UNIQUEIDENTIFIER,
    @primerNombre       NVARCHAR(50),
    @segundoNombre      NVARCHAR(50) = NULL,
    @primerApellido     NVARCHAR(50),
    @segundoApellido    NVARCHAR(50) = NULL,
    @correo             NVARCHAR(100),
    @idFacultad         UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @idUsuarioCoordinador    UNIQUEIDENTIFIER = NULL;

    -- Control de ownership transaccional (ver docs/procedimiento-transacciones)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    -- Solo se hace ROLLBACK si hubo escritura. Un rechazo de negocio antes de escribir no necesita rollback,
    -- y SQL Server prohibe ROLLBACK dentro de INSERT ... EXEC (3915), que es como se consume este SP en las pruebas.
    DECLARE @mutacionRealizada          BIT = 0;

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- PASO 1: correlacion y ejecutor presentes
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (perfil DECANO) y titularidad sobre la facultad indicada
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'DECANO',
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutor,
                @idEntidadPadre = @idFacultad,
                @tipoEntidadPadre = 'FACULTAD',
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: el coordinador existe y es de esa facultad (GEN_001 en ambos casos)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_coordinador_de_facultad_interno
                @idCoordinador = @idCoordinador,
                @idFacultad = @idFacultad,
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: escritura dentro de una transaccion (propia o savepoint si el llamador ya tiene una)
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
                SAVE TRANSACTION usp_actualizar_coordinador;
                SET @savepointCreado = 1;
            END

            SELECT TOP 1 @idUsuarioCoordinador = idUsuario
            FROM dbo.uv_coordinador_identidad
            WHERE id = @idCoordinador;

            EXEC dbo.usp_actualizar_datos_usuario_interno
                @idUsuario = @idUsuarioCoordinador,
                @primerNombre = @primerNombre,
                @segundoNombre = @segundoNombre,
                @primerApellido = @primerApellido,
                @segundoApellido = @segundoApellido,
                @correo = @correo,
                @idCorrelacion = @idCorrelacion,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                SET @mutacionRealizada = 1;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005',
                    @p_param1 = 'Coordinador',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
            END
        END

        -- PASO 5: cierre de la transaccion respetando el ownership
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
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1
        BEGIN
            IF XACT_STATE() = 1 AND @estadoResultado = 0 AND @mutacionRealizada = 1
                ROLLBACK TRANSACTION usp_actualizar_coordinador;
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
            ROLLBACK TRANSACTION usp_actualizar_coordinador;
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

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacion);
        SET @estadoResultado = 0;
    END CATCH

    -- Resultado unificado
    SELECT
        idCorrelacion           = @idCorrelacion,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idUsuario               = IIF(@estadoResultado = 1, @idUsuarioCoordinador, NULL);
END;
GO
