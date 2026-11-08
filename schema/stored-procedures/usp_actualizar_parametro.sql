USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_actualizar_parametro (CULM-001 D.3, HU168; CONTRACT v2 §4.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idParametro, grupo, clave, valorAnterior,
-- valorNuevo y fechaModificacion (NULL si estadoResultado = 0).
--
-- El administrador edita el valor de un parametro de negocio de la lista blanca (CatalogoParametroEdicion). Pasos:
-- correlacion -> ejecutor -> RBAC ADMINISTRADOR -> una sola Institucion activa ([SUPUESTO-D-16], PRM_012) -> motivo con al
-- menos PARAMETROS/LONGITUD_MINIMA_MOTIVO caracteres tras recortar (PRM_009) -> fila de CatalogoParametro bloqueada
-- (UPDLOCK, HOLDLOCK), activa (PRM_002) -> grupo fuera de PARAMETROS/GRUPOS_NO_EDITABLES y fila editable (PRM_003) ->
-- fechaModificacion igual a la esperada, comparacion exacta en DATETIME (PRM_008) -> ufn_validar_valor_parametro
-- (PRM_004/005/006) -> reglas cruzadas estrictas en las dos direcciones (PRM_007) -> valor igual (PRM_011: exito sin
-- escritura) -> UPDATE valor y fechaModificacion + INSERT CambioParametro en la misma transaccion.
-- Transaccion propia o SAVE TRANSACTION. Las ramas de rechazo no escriben: solo confirman la transaccion propia (sin
-- ROLLBACK, compatible con INSERT ... EXEC). Las filas relacionadas por la regla cruzada se bloquean tambien para que dos
-- ediciones simultaneas de un par no violen la regla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_parametro]
(
    @idParametro               UNIQUEIDENTIFIER,
    @valor                     NVARCHAR(4000),
    @fechaModificacionEsperada DATETIME,
    @motivo                    NVARCHAR(500),
    @idCorrelacion             UNIQUEIDENTIFIER,
    @idUsuarioEjecutor         UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idParametroDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idParametro, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @valorLimpio      NVARCHAR(4000) = TRIM(@valor);
    DECLARE @motivoLimpio     NVARCHAR(500) = TRIM(@motivo);
    DECLARE @longitudMinima   INT = dbo.ufn_obtener_parametro_int(NULL, 'PARAMETROS', 'LONGITUD_MINIMA_MOTIVO');
    DECLARE @grupo            VARCHAR(100);
    DECLARE @clave            VARCHAR(100);
    DECLARE @tipoDato         VARCHAR(20);
    DECLARE @valorAnterior    NVARCHAR(4000);
    DECLARE @fechaActual      DATETIME;
    DECLARE @esEditable       BIT;
    DECLARE @valorMinimo      DECIMAL(19,4);
    DECLARE @valorMaximo      DECIMAL(19,4);
    DECLARE @permitidos       NVARCHAR(500);
    DECLARE @idReferido       UNIQUEIDENTIFIER;
    DECLARE @claveReferida    VARCHAR(100);
    DECLARE @valorReferido    DECIMAL(19,4);
    DECLARE @claveDependiente VARCHAR(100);
    DECLARE @numeroNuevo      DECIMAL(19,4);
    DECLARE @fechaNueva       DATETIME = NULL;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @param1           NVARCHAR(500) = NULL;
    DECLARE @param2           NVARCHAR(500) = NULL;
    DECLARE @sinCambios       BIT = 0;
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

        -- PASO 2: RBAC (ADMINISTRADOR)
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

        -- PASO 3: [SUPUESTO-D-16] despliegue monoinstitucional: exactamente una Institucion activa (PRM_012)
        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: motivo con la longitud minima parametrizada (PRM_009)
        IF @estadoResultado = 1 AND (@motivoLimpio IS NULL OR @longitudMinima IS NULL OR LEN(@motivoLimpio) < @longitudMinima)
        BEGIN
            SET @param1 = CONVERT(NVARCHAR(20), @longitudMinima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_009', @p_param1 = @param1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: transaccion y evaluacion bajo el bloqueo de la fila del parametro
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_actualizar_parametro;
                SET @savepointCreado = 1;
            END

            SELECT @grupo = p.grupo, @clave = p.clave, @tipoDato = p.tipoDato, @valorAnterior = CONVERT(NVARCHAR(4000), p.valor), @fechaActual = p.fechaModificacion
            FROM dbo.CatalogoParametro p WITH (UPDLOCK, HOLDLOCK)
            WHERE p.id = @idParametroDefecto AND p.estaActivo = 1;

            IF @clave IS NULL
                SET @codigoRechazo = 'PRM_002';

            IF @codigoRechazo IS NULL
            BEGIN
                SELECT @esEditable = e.esEditable, @valorMinimo = e.valorMinimo, @valorMaximo = e.valorMaximo,
                       @permitidos = e.valoresPermitidos, @idReferido = e.parametroDebeSerMenorQue
                FROM dbo.CatalogoParametroEdicion e
                WHERE e.parametro = @idParametroDefecto;

                IF ISNULL(@esEditable, 0) = 0
                   OR EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES'), ',') n WHERE TRIM(n.value) = @grupo)
                    SET @codigoRechazo = 'PRM_003';
            END

            IF @codigoRechazo IS NULL AND (@fechaModificacionEsperada IS NULL OR @fechaActual <> @fechaModificacionEsperada)
                SET @codigoRechazo = 'PRM_008';

            IF @codigoRechazo IS NULL
            BEGIN
                SET @codigoRechazo = dbo.ufn_validar_valor_parametro(@tipoDato, @valorLimpio, @valorMinimo, @valorMaximo, @permitidos);
                IF @codigoRechazo = 'PRM_004'
                    SET @param1 = @tipoDato;
                ELSE IF @codigoRechazo = 'PRM_005'
                BEGIN
                    SET @param1 = IIF(@valorMinimo IS NULL, N'-', IIF(@valorMinimo = FLOOR(@valorMinimo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMinimo)), CONVERT(NVARCHAR(40), @valorMinimo)));
                    SET @param2 = IIF(@valorMaximo IS NULL, N'-', IIF(@valorMaximo = FLOOR(@valorMaximo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMaximo)), CONVERT(NVARCHAR(40), @valorMaximo)));
                END
                ELSE IF @codigoRechazo = 'PRM_006'
                    SET @param1 = @permitidos;
            END

            -- Reglas cruzadas estrictas (PRM_007): este < referido y cada dependiente < este
            IF @codigoRechazo IS NULL
            BEGIN
                SET @numeroNuevo = TRY_CONVERT(DECIMAL(19,4), @valorLimpio);
                IF @numeroNuevo IS NOT NULL AND @idReferido IS NOT NULL
                BEGIN
                    SELECT @claveReferida = r.clave, @valorReferido = TRY_CONVERT(DECIMAL(19,4), r.valor)
                    FROM dbo.CatalogoParametro r WITH (UPDLOCK, HOLDLOCK)
                    WHERE r.id = @idReferido;
                    IF @valorReferido IS NOT NULL AND @numeroNuevo >= @valorReferido
                    BEGIN
                        SET @codigoRechazo = 'PRM_007';
                        SET @param1 = @clave;
                        SET @param2 = @claveReferida;
                    END
                END
                IF @codigoRechazo IS NULL AND @numeroNuevo IS NOT NULL
                BEGIN
                    SELECT TOP 1 @claveDependiente = d.clave
                    FROM dbo.CatalogoParametroEdicion de
                    INNER JOIN dbo.CatalogoParametro d WITH (UPDLOCK, HOLDLOCK) ON d.id = de.parametro
                    WHERE de.parametroDebeSerMenorQue = @idParametroDefecto
                      AND TRY_CONVERT(DECIMAL(19,4), d.valor) >= @numeroNuevo
                    ORDER BY d.clave;
                    IF @claveDependiente IS NOT NULL
                    BEGIN
                        SET @codigoRechazo = 'PRM_007';
                        SET @param1 = @claveDependiente;
                        SET @param2 = @clave;
                    END
                END
            END

            -- Valor igual: exito sin escritura (PRM_011)
            IF @codigoRechazo IS NULL AND @valorLimpio COLLATE Latin1_General_BIN2 = @valorAnterior COLLATE Latin1_General_BIN2
                SET @sinCambios = 1;

            IF @codigoRechazo IS NULL AND @sinCambios = 0
            BEGIN
                UPDATE dbo.CatalogoParametro
                SET valor = @valorLimpio, fechaModificacion = SYSUTCDATETIME()
                WHERE id = @idParametroDefecto;

                SELECT @fechaNueva = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @idParametroDefecto;

                INSERT INTO dbo.CambioParametro (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
                VALUES (NEWID(), @idParametroDefecto, @valorAnterior, @valorLimpio, @motivoLimpio, @idUsuarioEjecutorDefecto, @idCorrelacionDefecto, SYSUTCDATETIME());

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PRM_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE IF @sinCambios = 1
            BEGIN
                SET @fechaNueva = @fechaActual;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PRM_011',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @param1, @p_param2 = @param2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera los bloqueos).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
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
            ROLLBACK TRANSACTION sp_actualizar_parametro;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
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
        idParametro             = IIF(@estadoResultado = 1, @idParametroDefecto, NULL),
        grupo                   = IIF(@estadoResultado = 1, @grupo, NULL),
        clave                   = IIF(@estadoResultado = 1, @clave, NULL),
        valorAnterior           = IIF(@estadoResultado = 1, @valorAnterior, NULL),
        valorNuevo              = IIF(@estadoResultado = 1, IIF(@sinCambios = 1, @valorAnterior, @valorLimpio), NULL),
        fechaModificacion       = IIF(@estadoResultado = 1, @fechaNueva, NULL);
END;
GO
