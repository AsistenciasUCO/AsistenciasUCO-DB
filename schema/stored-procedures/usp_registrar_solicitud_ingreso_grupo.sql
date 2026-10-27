USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_registrar_solicitud_ingreso_grupo  (HU053)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con resultset canonico de 4 columnas.
-- El ESTUDIANTE autenticado (Estudiante.usuario = ejecutor) solicita ingresar a un grupo; queda PENDIENTE (P).
-- Codigos: GEN_002 ejecutor nulo, SIG_001 no es estudiante, SIG_002 grupo inexistente, SIG_003 periodo terminado,
-- SIG_004 ya matriculado activo, SIG_005 ya tiene una solicitud abierta (P/E), SIG_006 exito.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_solicitud_ingreso_grupo]
(
    @idSolicitud             UNIQUEIDENTIFIER,
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @zonaHoraria              NVARCHAR(100) = CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100));
    DECLARE @hoyLocal                 DATE;
    DECLARE @idEstudiante             UNIQUEIDENTIFIER;
    DECLARE @grupoEncontrado          UNIQUEIDENTIFIER;
    DECLARE @fechaFinPeriodo          DATE;
    DECLARE @estadoPendiente          UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
    DECLARE @estadoEspera             UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'E');

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
                SAVE TRANSACTION sp_registrar_solicitud_ingreso;
                SET @savepointCreado = 1;
            END

            SELECT @idEstudiante = e.id FROM dbo.Estudiante e WHERE e.usuario = @idUsuarioEjecutorDefecto;
            SELECT @grupoEncontrado = g.id, @fechaFinPeriodo = pa.fechaFin
            FROM dbo.Grupo g
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto;

            SET @codigoRechazo =
                CASE
                    WHEN @idEstudiante IS NULL THEN 'SIG_001'
                    WHEN @grupoEncontrado IS NULL THEN 'SIG_002'
                    WHEN @fechaFinPeriodo < @hoyLocal THEN 'SIG_003'
                    WHEN EXISTS (SELECT 1 FROM dbo.EstudianteGrupo eg INNER JOIN dbo.EstadoEstudianteGrupo est ON est.id = eg.estado
                                 WHERE eg.grupo = @idGrupoDefecto AND eg.estudiante = @idEstudiante AND est.codigo = 'A') THEN 'SIG_004'
                    WHEN EXISTS (SELECT 1 FROM dbo.SolicitudIngresoGrupo s WITH (UPDLOCK, HOLDLOCK)
                                 WHERE s.grupo = @idGrupoDefecto AND s.estudiante = @idEstudiante
                                   AND s.estado IN (@estadoPendiente, @estadoEspera)) THEN 'SIG_005'
                END;

            IF @codigoRechazo IS NULL
            BEGIN
                INSERT INTO dbo.SolicitudIngresoGrupo (id, estudiante, grupo, estado, fechaSolicitudUtc)
                VALUES (@idSolicitud, @idEstudiante, @idGrupoDefecto, @estadoPendiente, SYSUTCDATETIME());

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SIG_006',
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
            ROLLBACK TRANSACTION sp_registrar_solicitud_ingreso;
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
