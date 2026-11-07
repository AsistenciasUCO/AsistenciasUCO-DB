USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_reactivar_matricula_retirada (CULM-001 A.1, DEC-009; CONTRACT §2.3)
--
-- Interno (sin GRANT al runtime). Lo llama usp_registrar_estudiante_en_grupo_interno (PASO 3.8), al que llegan las dos
-- vias de matricula que quedan: la manual del docente titular (HU050) y la de QR/PIN (HU176B). Regla INT-HU-01: si el
-- estudiante tiene en el grupo una matricula RETIRADA (codigo del parametro MATRICULA/ESTADO_RETIRADA), se reactiva la
-- MISMA fila al estado destino (se conservan sus asistencias historicas). Sin matricula retirada no escribe nada
-- (@reactivada = 0, exito) y el interno sigue con el alta normal.
--   * La busqueda inicial no toma bloqueos: la matricula nueva normal no paga el costo del bloqueo.
--   * Solo con matricula retirada se bloquea el Grupo (UPDLOCK, HOLDLOCK), se relee la fila por su id y se cuentan las
--     matriculas en el estado destino bajo bloqueo: sin cupo => ERR_CUPO_SUPERADO, sin escrituras.
--   * No inscribe en el programa: esa regla la aplica una sola vez el bloque comun del interno.
--   * Transaccion propia si @@TRANCOUNT = 0; si no, savepoint sp_reactivar_matricula. @@TRANCOUNT sale igual que entra.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_reactivar_matricula_retirada]
(
    @idEstudiante            UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @codigoEstadoDestino     NVARCHAR(10),
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @reactivada              BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto  UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDestino        NVARCHAR(10)     = UPPER(TRIM(dbo.ufn_obtener_parametro_texto(@codigoEstadoDestino, 'GENERAL', 'CADENA_VACIA')));
    DECLARE @codigoRetirada       NVARCHAR(10)     = UPPER(TRIM(CAST(dbo.ufn_obtener_parametro('MATRICULA', 'ESTADO_RETIRADA') AS NVARCHAR(10))));
    DECLARE @idEstadoDestino      UNIQUEIDENTIFIER;
    DECLARE @idEstadoRetirada     UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupo    UNIQUEIDENTIFIER;
    DECLARE @idEstudianteGrupoBloqueado UNIQUEIDENTIFIER;
    DECLARE @capacidad            INT;
    DECLARE @activos              INT;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1,
           @reactivada = 0;

    BEGIN TRY
        SET @conteoTransaccionesInicial = @@TRANCOUNT;
        IF @conteoTransaccionesInicial = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @transaccionPropia = 1;
        END
        ELSE
        BEGIN
            SAVE TRANSACTION sp_reactivar_matricula;
            SET @savepointCreado = 1;
        END

        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: codigos por catalogo (parametro MATRICULA/ESTADO_RETIRADA y estado destino del interno)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idEstadoRetirada = es.id FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = @codigoRetirada;
            SELECT @idEstadoDestino = es.id FROM dbo.uv_estado_estudiante_grupo es WHERE es.codigo = @codigoDestino;

            IF @idEstadoRetirada IS NULL OR @idEstadoDestino IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001',
                    @p_param1 = 'Estado Estudiante Grupo (reactivacion)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: busqueda sin bloqueo de una matricula retirada del estudiante en el grupo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @idEstudianteGrupo = eg.id
            FROM dbo.EstudianteGrupo eg
            INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
            WHERE eg.grupo = @idGrupoDefecto
              AND eg.estudiante = @idEstudianteDefecto
              AND es.codigo = @codigoRetirada
            ORDER BY eg.id;
        END

        -- PASO 4: solo con matricula retirada: bloqueo del grupo, relectura de la fila y cupo bajo bloqueo
        IF @estadoResultado = 1 AND @idEstudianteGrupo IS NOT NULL
        BEGIN
            SELECT @capacidad = g.cantidadEstudiantes
            FROM dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)
            WHERE g.id = @idGrupoDefecto;

            SELECT @idEstudianteGrupoBloqueado = eg.id
            FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
            WHERE eg.id = @idEstudianteGrupo
              AND eg.estado = @idEstadoRetirada;

            IF @idEstudianteGrupoBloqueado IS NOT NULL
            BEGIN
                SELECT @activos = COUNT(*)
                FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.uv_estado_estudiante_grupo es ON es.id = eg.estado
                WHERE eg.grupo = @idGrupoDefecto
                  AND es.codigo = @codigoDestino;

                IF @capacidad IS NULL OR @capacidad - @activos <= 0
                BEGIN
                    EXEC dbo.usp_obtener_mensaje_catalogo
                        @p_codigo = 'ERR_CUPO_SUPERADO',
                        @p_param1 = @idGrupoDefecto,
                        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                    SET @estadoResultado = 0;
                END
                ELSE
                BEGIN
                    -- PASO 5: misma fila, nuevo estado (INT-HU-01); el mensaje de exito lo pone el interno
                    UPDATE dbo.EstudianteGrupo
                    SET estado = @idEstadoDestino
                    WHERE id = @idEstudianteGrupoBloqueado;

                    SET @reactivada = 1;
                    SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                END
            END
        END

        IF @estadoResultado = 1 AND @reactivada = 0 AND @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA')
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);

        -- PASO 6: cierre de la transaccion propia (las ramas de rechazo no escriben)
        IF @transaccionPropia = 1
        BEGIN
            IF XACT_STATE() = 1
                COMMIT TRANSACTION;
            ELSE IF XACT_STATE() = -1
                ROLLBACK TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_reactivar_matricula;

        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
        SET @reactivada = 0;
    END CATCH
END;
GO
