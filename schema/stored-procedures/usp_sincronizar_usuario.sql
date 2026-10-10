USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CC-003G-01: proveedor publico exigido por el backend (UsuarioJpaRepository.SQL_SINCRONIZAR_USUARIO).
--
-- Semantica: ALTA IDEMPOTENTE (find-or-create), nunca actualizacion de un usuario existente.
--   * Identidad nueva (tipo + numero + correo libres)            -> alta atomica (GEN_004).
--   * Reintento EXACTO (mismo tipo, numero, correo y nombres)    -> exito sin escribir (GEN_004).
--   * Cualquier otra coincidencia (documento o correo en uso)    -> rechazo sin escribir
--     (ERR_UNICIDAD_DOCUMENTO / VAL_006). El SP no modifica nombres, correo ni password de un usuario
--     existente: /api/v1/usuarios es accesible a cualquier usuario autenticado y un UPSERT permitiria
--     sobrescribir credenciales ajenas.
--   * El password recibido es el hash del backend; solo se persiste en un alta nueva, nunca se compara,
--     se devuelve ni se incluye en mensajes.
--   * El id generado se consulta por identificacion (uv_usuario), el resultado canonico no lo expone.
-- Autorizacion: el contrato HTTP es AUTENTICADO (sin ejecutor); la defensa en DB es de minimo privilegio
-- (EXEC solo para rol_asistencias_runtime, sin DML directo sobre dbo.Usuario).
-- Concurrencia: dbo.Usuario no tiene indices unicos de negocio; la unicidad se serializa con un barrido
-- SERIALIZABLE + UPDLOCK dentro de la transaccion para que dos altas simultaneas no dupliquen documento ni
-- correo. No se usa sp_getapplock: impide que sys.dm_exec_describe_first_result_set_for_object descubra el
-- resultset canonico de 4 columnas que el gate PUBLIC_CANONICAL_RESULTSET exige.
CREATE OR ALTER PROCEDURE [dbo].[usp_sincronizar_usuario]
(
    @idTipoIdIdentificacion UNIQUEIDENTIFIER,
    @numeroIdentificacion   INT,
    @primerApellido         NVARCHAR(255),
    @segundoApellido        NVARCHAR(255),
    @primerNombre           NVARCHAR(255),
    @segundoNombre          NVARCHAR(255),
    @correo                 NVARCHAR(255),
    @password               NVARCHAR(500),
    @idCorrelacion          UNIQUEIDENTIFIER
)
AS
    DECLARE @idCorrelacionDefecto          UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idTipoIdIdentificacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idTipoIdIdentificacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @numeroIdentificacionDefecto   INT           = dbo.ufn_obtener_parametro_int(@numeroIdentificacion, 'GENERAL', 'ENTERO_CERO');
    DECLARE @primerApellidoDefecto         NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoApellidoDefecto        NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoApellido, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @primerNombreDefecto           NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@primerNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @segundoNombreDefecto          NVARCHAR(255) = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@segundoNombre, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @correoDefecto                 NVARCHAR(255) = LOWER(TRIM(dbo.ufn_obtener_parametro_texto(@correo, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @passwordDefecto               NVARCHAR(500) = TRIM(dbo.ufn_obtener_parametro_texto(@password, 'GENERAL', 'CADENA_VACIA'));

    DECLARE @idUsuarioCoincidente UNIQUEIDENTIFIER;
    DECLARE @conteoBloqueo        BIGINT;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    -- Control de ownership transaccional (ver docs/arquitectura/transaccion-procedimiento.md)
    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validacion del identificador de correlacion obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Limites de longitud de dbo.Usuario. Se rechaza antes de escribir para que un overflow
        -- nunca llegue a SQL Server (el mensaje 2628 incluye el valor truncado).
        IF @estadoResultado = 1 AND LEN(@primerNombreDefecto) > 50
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004', @p_param1 = 'primer nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND LEN(@segundoNombreDefecto) > 50
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004', @p_param1 = 'segundo nombre',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND LEN(@primerApellidoDefecto) > 50
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004', @p_param1 = 'primer apellido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND LEN(@segundoApellidoDefecto) > 50
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_004', @p_param1 = 'segundo apellido',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        IF @estadoResultado = 1 AND LEN(@correoDefecto) > 100
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_005',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: Transaccion propia (o savepoint si el llamador ya tiene una) y exclusion mutua del alta
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
                SAVE TRANSACTION usp_sincronizar_usuario;
                SET @savepointCreado = 1;
            END

            -- Exclusion mutua: el barrido serializable con UPDLOCK toma bloqueos de rango sobre dbo.Usuario hasta
            -- el final de la transaccion; una segunda alta concurrente espera y luego ve la fila ya confirmada.
            SELECT @conteoBloqueo = COUNT_BIG(*)
            FROM dbo.Usuario u WITH (UPDLOCK, HOLDLOCK)
            WHERE (u.tipoIdIdentificacion = @idTipoIdIdentificacionDefecto AND u.numeroIdentificacion = @numeroIdentificacionDefecto)
               OR LOWER(TRIM(u.correo)) = @correoDefecto;
        END

        -- PASO 4: Reintento exacto => exito idempotente sin escribir (no se compara ni toca el password)
        IF @estadoResultado = 1 AND @passwordDefecto <> ''
        BEGIN
            SELECT TOP 1 @idUsuarioCoincidente = u.id
            FROM dbo.uv_usuario u
            WHERE u.idTipoIdentificacion = @idTipoIdIdentificacionDefecto
              AND u.numeroIdentificacion = @numeroIdentificacionDefecto
              AND LOWER(TRIM(u.correo)) = @correoDefecto
              AND UPPER(TRIM(u.primerNombre)) = @primerNombreDefecto
              AND UPPER(TRIM(u.segundoNombre)) = @segundoNombreDefecto
              AND UPPER(TRIM(u.primerApellido)) = @primerApellidoDefecto
              AND UPPER(TRIM(u.segundoApellido)) = @segundoApellidoDefecto;

            IF @idUsuarioCoincidente IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Usuario',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
        END

        -- PASO 5: Alta. La validacion de tipo, unicidad, formatos y password y el INSERT viven en el nucleo interno.
        IF @estadoResultado = 1 AND @idUsuarioCoincidente IS NULL
        BEGIN
            EXEC dbo.usp_sincronizar_usuario_interno
                @idTipoIdIdentificacion  = @idTipoIdIdentificacion,
                @numeroIdentificacion    = @numeroIdentificacion,
                @primerApellido          = @primerApellido,
                @segundoApellido         = @segundoApellido,
                @primerNombre            = @primerNombre,
                @segundoNombre           = @segundoNombre,
                @correo                  = @correo,
                @password                = @password,
                @idCorrelacion           = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado         = @estadoResultado OUTPUT;
        END

        -- PASO 6: Finalizacion respetando ownership: commit solo si el resultado es exitoso
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
            IF XACT_STATE() = 1 AND @estadoResultado = 0
                ROLLBACK TRANSACTION usp_sincronizar_usuario;
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
            ROLLBACK TRANSACTION usp_sincronizar_usuario;
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
