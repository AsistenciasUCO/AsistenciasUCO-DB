USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_aplicar_festivos_grupos (CULM-001 B.1; CONTRACT §2.7.5) — nucleo, sin EXECUTE para el rol runtime.
--
-- Selecciona los grupos y aplica usp_internal_aplicar_festivos_grupo (@soloFuturas = 1) a cada uno en su PROPIA
-- transaccion (o savepoint si el llamador ya tiene una): un grupo con error no deshace los anteriores y se cuenta en
-- @gruposConError. Una transaccion externa condenada se propaga (THROW). Seleccion de grupos (tabla variable, sin
-- tablas temporales, para que los SP publicos sigan siendo describibles por sp_describe_first_result_set):
--   * @idPeriodoAcademico NOT NULL: los grupos del periodo (usp_aplicar_festivos_periodo con periodo);
--   * si no, @idUsuarioAdministrador NOT NULL: los grupos de los periodos de la institucion del administrador que se
--     cruzan con @anio (usp_aplicar_festivos_periodo con anio);
--   * si no: todos los grupos con sesiones cuya fecha local cae en @anio (usp_aplicar_festivos_automatico).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupos]
(
    @idPeriodoAcademico       UNIQUEIDENTIFIER,
    @anio                     INT,
    @idUsuarioAdministrador   UNIQUEIDENTIFIER,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @gruposProcesados         INT OUTPUT,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @gruposConError           INT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoActual    UNIQUEIDENTIFIER;
    DECLARE @canceladas       INT;
    DECLARE @conAsistencia    INT;
    DECLARE @mensajeUsuario   NVARCHAR(4000);
    DECLARE @mensajeTecnico   NVARCHAR(4000);
    DECLARE @estado           BIT;
    DECLARE @transaccionPropia BIT;
    DECLARE @estadoTransaccion INT;
    DECLARE @zonaHorariaSqlServer SYSNAME = CONVERT(SYSNAME, dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER'));
    DECLARE @grupos TABLE (idGrupo UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);

    SELECT @gruposProcesados = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0, @gruposConError = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @idPeriodoAcademico IS NOT NULL
        INSERT INTO @grupos (idGrupo)
        SELECT g.id FROM dbo.Grupo g WHERE g.periodoAcademico = @idPeriodoAcademico;
    ELSE IF @idUsuarioAdministrador IS NOT NULL
        INSERT INTO @grupos (idGrupo)
        SELECT g.id
        FROM dbo.Grupo g
        INNER JOIN dbo.uv_periodo_academico pa ON pa.id = g.periodoAcademico
        WHERE pa.fechaInicio <= DATEFROMPARTS(@anio, 12, 31) AND pa.fechaFin >= DATEFROMPARTS(@anio, 1, 1)
          AND pa.idInstitucion IN (SELECT a.idInstitucion FROM dbo.uv_administrador a WHERE a.idUsuario = @idUsuarioAdministrador);
    ELSE IF @anio IS NOT NULL AND @zonaHorariaSqlServer IS NOT NULL
        INSERT INTO @grupos (idGrupo)
        SELECT DISTINCT s.grupo
        FROM dbo.Sesion s
        WHERE YEAR(CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)) = @anio;

    DECLARE grupos_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT idGrupo FROM @grupos ORDER BY idGrupo;
    OPEN grupos_cursor;
    FETCH NEXT FROM grupos_cursor INTO @idGrupoActual;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @canceladas = 0, @conAsistencia = 0, @estado = 1, @transaccionPropia = 0;
        BEGIN TRY
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
                SAVE TRANSACTION sp_aplicar_festivos_grupos;

            EXEC dbo.usp_internal_aplicar_festivos_grupo
                @idGrupo = @idGrupoActual,
                @soloFuturas = 1,
                @idCorrelacion = @idCorrelacionDefecto,
                @idUsuarioEjecutor = @idUsuarioEjecutor,
                @sesionesCanceladas = @canceladas OUTPUT,
                @sesionesConAsistencia = @conAsistencia OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuario OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnico OUTPUT,
                @estadoResultado = @estado OUTPUT;

            SET @estadoTransaccion = XACT_STATE();
            IF @estadoTransaccion = -1
            BEGIN
                -- El nucleo atrapo un error que condeno la transaccion
                IF @transaccionPropia = 1
                    ROLLBACK TRANSACTION;
                ELSE
                    THROW 51000, @mensajeTecnico, 1;
                SET @estado = 0;
            END
            ELSE IF @transaccionPropia = 1
            BEGIN
                -- Las ramas de rechazo del nucleo no escriben: se confirma igual
                COMMIT TRANSACTION;
            END

            IF @estado = 1
                SELECT @gruposProcesados += 1, @sesionesCanceladas += @canceladas, @sesionesConAsistencia += @conAsistencia;
            ELSE
                SET @gruposConError += 1;
        END TRY
        BEGIN CATCH
            SET @estadoTransaccion = XACT_STATE();
            IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            ELSE IF @transaccionPropia = 0 AND @estadoTransaccion = -1
            BEGIN
                CLOSE grupos_cursor;
                DEALLOCATE grupos_cursor;
                THROW;
            END
            ELSE IF @transaccionPropia = 0 AND @estadoTransaccion = 1
                ROLLBACK TRANSACTION sp_aplicar_festivos_grupos;
            SET @gruposConError += 1;
        END CATCH

        FETCH NEXT FROM grupos_cursor INTO @idGrupoActual;
    END
    CLOSE grupos_cursor;
    DEALLOCATE grupos_cursor;
END;
GO
