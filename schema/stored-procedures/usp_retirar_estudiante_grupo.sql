USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_retirar_estudiante_grupo  (HU051)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El DOCENTE TITULAR (Grupo.docente -> Docente.usuario = ejecutor) retira a un estudiante de su grupo:
--   - la matricula activa (EstudianteGrupo estado A) pasa al estado existente I (inactivo); no se borra nada;
--   - las asistencias del estudiante se conservan como historial;
--   - el cupo se libera solo (uv_grupo.cuposDisponibles = capacidad - matriculas activas);
--   - el motivo es obligatorio (1..500 caracteres, sin espacios extremos) y queda en dbo.AuditoriaEvento;
--   - se rechaza si el periodo del grupo ya termino (fecha local segun TIEMPO.ZONA_HORARIA_SQLSERVER).
-- Codigos: GEN_002 ejecutor nulo, RET_004 motivo, RET_001 grupo inexistente o no titular (indistinguibles),
-- RET_003 periodo terminado, RET_002 sin matricula activa, RET_005 exito.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_retirar_estudiante_grupo]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idEstudiante            UNIQUEIDENTIFIER,
    @motivo                  NVARCHAR(MAX),
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @motivoNormalizado        NVARCHAR(MAX) = NULLIF(TRIM(@motivo), N'');
    DECLARE @zonaHoraria              NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal                 DATE;
    DECLARE @grupoBloqueado           UNIQUEIDENTIFIER;
    DECLARE @fechaFinPeriodo          DATE;
    DECLARE @idEstudianteGrupo        UNIQUEIDENTIFIER;
    DECLARE @estadoActivo             UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'A');
    DECLARE @estadoInactivo           UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = 'I');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
    DECLARE @codigoRechazo           VARCHAR(100);

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        SET @hoyLocal = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE @zonaHoraria AS DATE);

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

        IF @estadoResultado = 1 AND (@motivoNormalizado IS NULL OR LEN(@motivoNormalizado) > 500)
            SET @codigoRechazo = 'RET_004';

        IF @estadoResultado = 1 AND @codigoRechazo IS NULL
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_retirar_estudiante_grupo;
                SET @savepointCreado = 1;
            END

            -- Titularidad en tablas base: un grupo ajeno es indistinguible de uno inexistente (RET_001).
            SELECT @grupoBloqueado = g.id, @fechaFinPeriodo = pa.fechaFin
            FROM dbo.Grupo g WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Docente d ON d.id = g.docente
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto AND d.usuario = @idUsuarioEjecutorDefecto;

            IF @grupoBloqueado IS NOT NULL
                SELECT @idEstudianteGrupo = eg.id
                FROM dbo.EstudianteGrupo eg WITH (UPDLOCK, HOLDLOCK)
                WHERE eg.grupo = @idGrupoDefecto AND eg.estudiante = @idEstudianteDefecto AND eg.estado = @estadoActivo;

            SET @codigoRechazo =
                CASE
                    WHEN @grupoBloqueado IS NULL THEN 'RET_001'
                    WHEN @fechaFinPeriodo < @hoyLocal THEN 'RET_003'
                    WHEN @idEstudianteGrupo IS NULL THEN 'RET_002'
                END;

            IF @codigoRechazo IS NULL
            BEGIN
                UPDATE dbo.EstudianteGrupo SET estado = @estadoInactivo WHERE id = @idEstudianteGrupo;

                INSERT INTO dbo.AuditoriaEvento (
                    id, occurredAt, actorId, actorType, action,
                    resourceType, resourceId, result, correlationId,
                    httpMethod, path, httpStatus, metadata
                ) VALUES (
                    NEWID(),
                    SYSDATETIMEOFFSET(),
                    CAST(@idUsuarioEjecutorDefecto AS NVARCHAR(120)),
                    'USER',
                    'RETIRO_ESTUDIANTE_GRUPO',
                    'EstudianteGrupo',
                    CAST(@idEstudianteGrupo AS NVARCHAR(120)),
                    'SUCCESS',
                    @idCorrelacionDefecto,
                    'POST',
                    N'/api/v1/docente/grupos/{grupoId}/estudiantes/{estudianteId}/retiro',
                    200,
                    (SELECT idGrupo = CAST(@idGrupoDefecto AS NVARCHAR(36)),
                            idEstudiante = CAST(@idEstudianteDefecto AS NVARCHAR(36)),
                            motivo = @motivoNormalizado
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
                );

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'RET_005',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1 COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1 ROLLBACK TRANSACTION;
            END
        END

        IF @estadoResultado = 1 AND @codigoRechazo IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = @codigoRechazo,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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
            ROLLBACK TRANSACTION sp_retirar_estudiante_grupo;
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
