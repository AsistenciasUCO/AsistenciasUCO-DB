USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B: el docente titular abre la ventana de matricula por QR/PIN de su grupo.
-- El token y el PIN los genera el backend (SecureRandom); la DB solo recibe el SHA-256 del token y el PIN.
--   * RBAC DOCENTE + titularidad del grupo (SEC_002) + grupo existente + cupo disponible.
--   * Cierra cualquier ventana ACTIVA del grupo e inserta la nueva (una ventana activa por grupo).
--   * Fin de la ventana = ahora + MATRICULA_QR/DURACION_MAXIMA_MINUTOS (parametro administrable, CONTRACT A1).
--   * PIN repetido en el PIN vigente o anterior de otra ventana activa -> MQR_006 sin escrituras (el backend reintenta).
-- Resultset: tupla canonica + idVentana + fechaExpiracionUtc (extension documentada, CONTRACT §2.3).
CREATE OR ALTER PROCEDURE [dbo].[usp_abrir_ventana_matricula_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @tokenHash         VARBINARY(32),
    @pin               NCHAR(6),
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;

    DECLARE @idDocenteTitular   UNIQUEIDENTIFIER;
    DECLARE @idVentana          UNIQUEIDENTIFIER = NULL;
    DECLARE @fechaExpiracionUtc DATETIME2(0)     = NULL;
    DECLARE @codigoRechazo      VARCHAR(20)      = NULL;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion, ejecutor y datos del token
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

        IF @estadoResultado = 1 AND (@idGrupo IS NULL OR @tokenHash IS NULL OR @pin IS NULL OR @pin LIKE N'%[^0-9]%' OR LEN(@pin) <> 6)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idGrupo/tokenHash/pin',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (DOCENTE)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutor,
                @codigoPerfilRequerido = 'DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: grupo existente y titularidad
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_grupo_exista_por_id_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            SELECT @idDocenteTitular = d.id
            FROM dbo.Grupo g
            INNER JOIN dbo.Docente d ON d.id = g.docente
            WHERE g.id = @idGrupoDefecto AND d.usuario = @idUsuarioEjecutor;

            IF @idDocenteTitular IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SEC_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: cupo disponible
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_cupo_disponible_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 5: escritura atomica
        IF @estadoResultado = 1
        BEGIN
            DECLARE @estadoActiva  NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10));
            DECLARE @estadoCerrada NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_CERRADA') AS NVARCHAR(10));
            DECLARE @duracionMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'DURACION_MAXIMA_MINUTOS');
            DECLARE @ahora DATETIME2(0) = SYSUTCDATETIME();

            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_hu176b_abrir;
                SET @savepointCreado = 1;
            END

            -- PIN unico frente al vigente y al anterior de las ventanas activas de OTROS grupos
            IF EXISTS (
                SELECT 1 FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
                WHERE t.estado = @estadoActiva AND t.grupo <> @idGrupoDefecto AND (t.pin = @pin OR t.pinAnterior = @pin)
            )
                SET @codigoRechazo = 'MQR_006';

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.TokenMatriculaGrupo
                SET estado = @estadoCerrada, fechaCierreUtc = @ahora
                WHERE grupo = @idGrupoDefecto AND estado = @estadoActiva;

                SET @idVentana = NEWID();
                SET @fechaExpiracionUtc = DATEADD(MINUTE, @duracionMinutos, @ahora);

                INSERT INTO dbo.TokenMatriculaGrupo
                    (id, grupo, docenteEmisor, tokenHash, pin, tokenHashAnterior, pinAnterior, fechaRotacionUtc,
                     estado, fechaEmisionUtc, fechaExpiracionUtc, fechaCierreUtc, totalMatriculas)
                VALUES
                    (@idVentana, @idGrupoDefecto, @idDocenteTitular, @tokenHash, @pin, NULL, NULL, @ahora,
                     @estadoActiva, @ahora, @fechaExpiracionUtc, NULL, 0);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004', @p_param1 = 'Ventana de matricula',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe nada: solo se confirma la transaccion propia.
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
            END
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
            ROLLBACK TRANSACTION sp_hu176b_abrir;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @idVentana = NULL;
        SET @fechaExpiracionUtc = NULL;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idVentana               = IIF(@estadoResultado = 1, @idVentana, NULL),
        fechaExpiracionUtc      = IIF(@estadoResultado = 1, @fechaExpiracionUtc, NULL);
END;
GO
