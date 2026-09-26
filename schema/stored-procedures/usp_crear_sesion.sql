USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_crear_sesion]
(
    @idGrupo            UNIQUEIDENTIFIER,
    @nombre             NVARCHAR(50),
    @fechaHoraInicio    DATETIME2,
    @fechaHoraFin       DATETIME2,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);

    DECLARE @idNuevoSesion   UNIQUEIDENTIFIER = NEWID();
    DECLARE @numeroSiguiente INT = 1;
    DECLARE @codigoSesion    NVARCHAR(50);

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Ownership transaccional (propia o savepoint bajo transacción externa)
    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación de correlación
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto, 
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: El ejecutor (Usuario.id) es obligatorio y nunca puede saltar seguridad.
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

        -- PASO 1.6: Validación de perfil RBAC del ejecutor
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

        -- PASO 2: Validación de existencia del grupo académico
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2.1: Titularidad del docente ejecutor sobre el grupo.
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

        -- PASO 2.5: Las fechas de sesión son obligatorias y representan instantes UTC.
        IF @estadoResultado = 1 AND @fechaHoraInicio IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'fechaHoraInicio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @fechaHoraFin IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'fechaHoraFin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND @fechaHoraFin <= @fechaHoraInicio
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SES_004',
                @p_param1 = 'fechaHoraFin',
                @p_param2 = 'fechaHoraInicio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Cálculo transaccional del correlativo de sesión e inserción
        -- (ownership transaccional: propia o savepoint bajo transacción externa)
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION usp_crear_sesion;
                SET @savepointCreado = 1;
            END

            SELECT @numeroSiguiente = COALESCE(MAX(numero), 0) + 1
            FROM [dbo].[Sesion] WITH (UPDLOCK, HOLDLOCK)
            WHERE grupo = @idGrupoDefecto;

            SET @codigoSesion = CASE
                WHEN @numeroSiguiente < 100 THEN CONCAT('SES-', RIGHT('0' + CAST(@numeroSiguiente AS VARCHAR(10)), 2))
                ELSE CONCAT('SES-', CAST(@numeroSiguiente AS VARCHAR(10)))
            END;

            INSERT INTO dbo.Sesion (
                id, nombre, numero, codigo, numeroSemana, grupo,
                fechaHoraInicio, fechaHoraFin
            )
            VALUES (
                @idNuevoSesion,
                CASE WHEN @nombreDefecto IS NOT NULL AND @nombreDefecto <> '' THEN @nombreDefecto ELSE CONCAT('Sesión #', @numeroSiguiente) END,
                @numeroSiguiente,
                @codigoSesion,
                @numeroSiguiente,
                @idGrupoDefecto,
                @fechaHoraInicio,
                @fechaHoraFin
            );

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() <> 0
                    ROLLBACK TRANSACTION;
            END

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Sesion',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones y reversión respetando ownership transaccional
        DECLARE @estadoTransaccionCatch INT = XACT_STATE();

        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION usp_crear_sesion;
        END

        -- Transacción externa condenada (XACT_STATE = -1) que no nos pertenece: propagar al propietario
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
