USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CC-003G-01: proveedor publico exigido por el backend (PlanEstudioJpaRepository.SQL_REGISTRAR_O_ACTUALIZAR_PLAN).
--
-- Contrato de entrada: el backend envia (@idPlanEstudio, @idPrograma, @inp, @idCorrelacion) y, desde este
-- work item, @idUsuarioEjecutor (el usuario COORDINADOR autenticado). El ejecutor es obligatorio: la
-- autorizacion no puede depender solo del controlador/Application.
--
-- Semantica (UPSERT por id, unicidad de negocio por programa + inp):
--   * Ejecutor obligatorio, activo, con perfil COORDINADOR y titular del programa (@idPrograma).
--   * @idPlanEstudio identifica el registro; no existe => alta (estado activo) con ese id.
--   * Existe en el MISMO programa con igual inp => exito sin escribir (idempotente).
--   * Existe en el MISMO programa con otro inp   => actualiza solo inp.
--   * Existe en OTRO programa => rechazo SEC_002, no se modifica nada (un coordinador no puede mutar planes ajenos).
--   * Otro plan del mismo programa ya usa ese inp => rechazo GEN_003 (sin duplicados de negocio).
--   * inp debe ser un entero positivo. Programa inexistente => PROG_001.
-- Concurrencia: dbo.PlanEstudio no tiene indice unico de negocio; (programa, inp) se serializa bloqueando la fila del
-- programa (UPDLOCK, HOLDLOCK) durante la transaccion. No se usa sp_getapplock: impide que
-- sys.dm_exec_describe_first_result_set_for_object descubra el resultset canonico de 4 columnas.
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_plan_estudio]
(
    @idPlanEstudio     UNIQUEIDENTIFIER,
    @idPrograma        UNIQUEIDENTIFIER,
    @inp               INT,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto        UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @guidDefecto              UNIQUEIDENTIFIER = TRY_CAST(dbo.ufn_obtener_parametro('GENERAL', 'GUID_DEFECTO_CORRELACION') AS UNIQUEIDENTIFIER);

    DECLARE @programaPlanExistente UNIQUEIDENTIFIER;
    DECLARE @inpPlanExistente      INT;
    DECLARE @planExiste            BIT = 0;
    DECLARE @programaBloqueado     UNIQUEIDENTIFIER;

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

        -- PASO 2: Ejecutor obligatorio y perfil RBAC COORDINADOR (fail-closed)
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
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Parametros obligatorios del plan
        IF @estadoResultado = 1 AND @idPlanEstudioDefecto = @guidDefecto
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idPlanEstudio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@inp IS NULL OR @inp <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'inp',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: El programa debe existir (uv_programa)
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idProgramaDefecto)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PROG_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: Titularidad: el ejecutor debe ser el coordinador del programa indicado
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

        -- PASO 6: Transaccion propia (o savepoint) y exclusion mutua por programa
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
                SAVE TRANSACTION sp_plan_estudio;
                SET @savepointCreado = 1;
            END

            -- Exclusion mutua por programa: UPDLOCK + HOLDLOCK sobre la fila del programa hasta el final de la transaccion
            SELECT @programaBloqueado = pr.id
            FROM dbo.Programa pr WITH (UPDLOCK, HOLDLOCK)
            WHERE pr.id = @idProgramaDefecto;
        END

        -- PASO 7: Resolver el registro existente por id (bajo bloqueo)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1
                @planExiste = 1,
                @programaPlanExistente = pe.programa,
                @inpPlanExistente = pe.inp
            FROM dbo.PlanEstudio pe
            WHERE pe.id = @idPlanEstudioDefecto;

            -- Un plan de otro programa nunca se modifica ni se confirma
            IF @planExiste = 1 AND @programaPlanExistente <> @idProgramaDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002', @p_param1 = 'Plan de estudio',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 8: Unicidad de negocio (programa + inp) frente a OTROS planes
        IF @estadoResultado = 1
            AND NOT (@planExiste = 1 AND @inpPlanExistente = @inp)
            AND EXISTS (
                SELECT 1 FROM dbo.PlanEstudio pe
                WHERE pe.programa = @idProgramaDefecto AND pe.inp = @inp AND pe.id <> @idPlanEstudioDefecto
            )
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_003', @p_param1 = 'plan de estudio', @p_param2 = 'inp',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 9: Escritura (alta, actualizacion o confirmacion idempotente)
        IF @estadoResultado = 1
        BEGIN
            IF @planExiste = 0
            BEGIN
                INSERT INTO dbo.PlanEstudio (id, programa, inp, estado)
                VALUES (@idPlanEstudioDefecto, @idProgramaDefecto, @inp, 1);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Plan de estudio',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                IF @inpPlanExistente <> @inp
                BEGIN
                    UPDATE dbo.PlanEstudio
                    SET inp = @inp
                    WHERE id = @idPlanEstudioDefecto AND programa = @idProgramaDefecto;
                END

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Plan de estudio',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

        -- PASO 10: Finalizacion respetando ownership: commit solo si el resultado es exitoso
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
                ROLLBACK TRANSACTION sp_plan_estudio;
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
            ROLLBACK TRANSACTION sp_plan_estudio;
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
