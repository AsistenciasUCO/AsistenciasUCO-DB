USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_aplicar_festivos_grupo (CULM-001 B.1; CONTRACT §2.7.5) — nucleo, sin EXECUTE para el rol runtime.
--
-- Marca como canceladas por FESTIVO las sesiones del grupo cuya fecha LOCAL (TIEMPO/ZONA_HORARIA_SQLSERVER) es un
-- DiaFestivo activo. No abre transaccion: la controla el llamador (publico, generacion v2 o precarga).
--   * Solo sesiones con procedencia temporal confirmada y sin SesionCancelacion (idempotente).
--   * @soloFuturas = 1 (mantenimiento de grupos ya creados): solo fechaHoraInicio > SYSUTCDATETIME();
--     @soloFuturas = 0 (generacion y precarga): toda sesion nueva en festivo nace cancelada ([SUPUESTO-B-11]).
--   * Una candidata con Asistencia no se toca ([SUPUESTO-B-10]): se cuenta en @sesionesConAsistencia y se reporta con
--     usp_consultar_sesiones_festivo_con_asistencia_paginado. No se usa la tabla temporal opcional
--     #sesionesFestivoConAsistencia del contrato: sus SP publicos (que tambien llaman a este nucleo) deben seguir siendo
--     describibles por sp_describe_first_result_set (PUBLIC_CANONICAL_RESULTSET). B.2 agrega la condicion sobre TomaAsistencia.
--   * Tipo por bandera TipoCancelacionSesion.esAutomatica = 1; motivo = FESTIVOS/PREFIJO_MOTIVO_CANCELACION + nombre.
-- Bloqueo: dbo.Sesion WITH (UPDLOCK, HOLDLOCK) sobre las candidatas antes de escribir (mismo orden que la ventana).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_aplicar_festivos_grupo]
(
    @idGrupo                  UNIQUEIDENTIFIER,
    @soloFuturas              BIT,
    @idCorrelacion            UNIQUEIDENTIFIER,
    @idUsuarioEjecutor        UNIQUEIDENTIFIER,
    @sesionesCanceladas       INT OUTPUT,
    @sesionesConAsistencia    INT OUTPUT,
    @mensajeUsuarioResultado  NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado  NVARCHAR(4000) OUTPUT,
    @estadoResultado          BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @prefijoMotivo        NVARCHAR(200)    = dbo.ufn_obtener_parametro('FESTIVOS', 'PREFIJO_MOTIVO_CANCELACION');
    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @idTipoAutomatico     UNIQUEIDENTIFIER;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);
    DECLARE @mensajeUsuarioExito  NVARCHAR(4000);

    DECLARE @candidatas TABLE (
        idSesion        UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        idDiaFestivo    UNIQUEIDENTIFIER NOT NULL,
        fecha           DATE             NOT NULL,
        nombreFestivo   NVARCHAR(120)    NOT NULL,
        tieneAsistencia BIT              NOT NULL
    );

    SELECT
        @sesionesCanceladas = 0,
        @sesionesConAsistencia = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: zona horaria institucional valida (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, p.valor)
            FROM dbo.uv_parametro p
            WHERE p.grupo = 'TIEMPO' AND p.clave = 'ZONA_HORARIA_SQLSERVER' AND p.estaActivo = 1;

            IF @zonaHorariaSqlServer IS NULL
               OR NOT EXISTS (SELECT 1 FROM sys.time_zone_info WHERE [name] = @zonaHorariaSqlServer)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TIEMPO/ZONA_HORARIA_SQLSERVER',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 3: tipo automatico por bandera de catalogo (GEN_001)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idTipoAutomatico = t.id FROM dbo.uv_tipo_cancelacion_sesion t WHERE t.esAutomatica = 1;

            IF @idTipoAutomatico IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_001', @p_param1 = 'TipoCancelacionSesion(esAutomatica = 1)',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: candidatas bloqueadas (fecha local en un festivo activo, sin cancelacion previa)
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO @candidatas (idSesion, idDiaFestivo, fecha, nombreFestivo, tieneAsistencia)
            SELECT  s.id, df.id, df.fecha, df.nombre,
                    CAST(IIF(EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id), 1, 0) AS BIT)
            FROM    dbo.Sesion s WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.DiaFestivo df
            ON      df.estaActivo = 1
            AND     df.fecha = CAST((s.fechaHoraInicio AT TIME ZONE 'UTC') AT TIME ZONE @zonaHorariaSqlServer AS DATE)
            WHERE   s.grupo = @idGrupoDefecto
              AND   s.procedenciaTemporal IS NOT NULL
              AND   (@soloFuturas = 0 OR s.fechaHoraInicio > @ahoraUtc)
              AND   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id);

            SET @sesionesConAsistencia = (SELECT COUNT(1) FROM @candidatas WHERE tieneAsistencia = 1);

            INSERT INTO dbo.SesionCancelacion (sesion, tipoCancelacion, motivo, diaFestivo, usuarioEjecutor, fechaCancelacionUtc, idCorrelacion)
            SELECT  c.idSesion, @idTipoAutomatico, LEFT(CONCAT(@prefijoMotivo, c.nombreFestivo), 500), c.idDiaFestivo,
                    @idUsuarioEjecutor, SYSUTCDATETIME(), @idCorrelacionDefecto
            FROM    @candidatas c
            WHERE   c.tieneAsistencia = 0;
            SET @sesionesCanceladas = @@ROWCOUNT;

            -- FES_008: usuario (canceladas, con asistencia); tecnico (grupo)
            SELECT @p1 = CONVERT(NVARCHAR(20), @sesionesCanceladas), @p2 = CONVERT(NVARCHAR(20), @sesionesConAsistencia);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1, @p_param2 = @p2,
                @mensajeUsuarioResultado = @mensajeUsuarioExito OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @p1 = CONVERT(NVARCHAR(36), @idGrupoDefecto);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'FES_008', @p_param1 = @p1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeUsuarioResultado = @mensajeUsuarioExito;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, N' Canceladas: ', @sesionesCanceladas,
                                                  N'. Con asistencia: ', @sesionesConAsistencia, N'. Correlacion: ', @idCorrelacionDefecto);
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SELECT @estadoResultado = 0, @sesionesCanceladas = 0, @sesionesConAsistencia = 0;
    END CATCH
END;
GO
