USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F2 (2026-11-02): nucleo atomico de usp_precargar_sesiones_grupo. Alinea las sesiones FUTURAS del grupo con su horario:
--   * crea las sesiones que faltan, desde hoy (hora institucional) o desde el inicio del periodo si aun no empieza,
--     hasta el fin del periodo, sin duplicar las que ya existen (mismo grupo, inicio y fin);
--   * elimina las sesiones futuras GENERADAS (procedenciaTemporal = UTC_GENERADOR) que ya no encajan en el horario y no
--     tienen asistencia ni clasificacion. Nunca toca sesiones del pasado ni las creadas a mano por el docente.
-- No abre transaccion: la controla el SP publico (propia o savepoint). No modifica usp_generar_sesiones_grupo (congelado).
CREATE OR ALTER PROCEDURE [dbo].[usp_precargar_sesiones_grupo_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @sesionesCreadas         INT OUTPUT,
    @sesionesEliminadas      INT OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @zonaHorariaSqlServer SYSNAME;
    DECLARE @ahoraUtc             DATETIME2 = SYSUTCDATETIME();
    DECLARE @fechaInicio          DATE;
    DECLARE @fechaFin             DATE;
    DECLARE @fechaHoy             DATE;
    DECLARE @fechaDesde           DATE;
    DECLARE @maxNumeroSesion      INT;
    DECLARE @fechaHoraLocalInexistente DATETIME2;

    DECLARE @slots TABLE (
        fecha       DATE      NOT NULL,
        inicioLocal DATETIME2 NOT NULL,
        finLocal    DATETIME2 NOT NULL,
        inicioUtc   DATETIME2 NULL,
        finUtc      DATETIME2 NULL
    );

    SELECT
        @sesionesCreadas = 0,
        @sesionesEliminadas = 0,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validacion del identificador de correlacion obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Zona horaria institucional valida para convertir el horario local a UTC
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @zonaHorariaSqlServer = CONVERT(SYSNAME, valor)
            FROM dbo.CatalogoParametro
            WHERE grupo = 'TIEMPO' AND clave = 'ZONA_HORARIA_SQLSERVER' AND estaActivo = 1;

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

        -- PASO 3: Franjas futuras del horario del grupo, desde hoy (o desde el inicio del periodo) hasta el fin del periodo
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 @fechaInicio = pa.fechaInicio, @fechaFin = pa.fechaFin
            FROM dbo.Grupo g
            INNER JOIN dbo.PeriodoAcademico pa ON pa.id = g.periodoAcademico
            WHERE g.id = @idGrupoDefecto;

            SET @fechaHoy = CAST(@ahoraUtc AT TIME ZONE 'UTC' AT TIME ZONE @zonaHorariaSqlServer AS DATE);
            SET @fechaDesde = IIF(@fechaHoy > @fechaInicio, @fechaHoy, @fechaInicio);

            -- 1900-01-01 fue lunes: el resto de dividir los dias desde esa fecha entre 7 da el dia de la semana sin depender del idioma
            WITH fechas AS (
                SELECT fecha = @fechaDesde
                WHERE @fechaDesde <= @fechaFin
                UNION ALL
                SELECT DATEADD(DAY, 1, fecha) FROM fechas WHERE fecha < @fechaFin
            )
            INSERT INTO @slots (fecha, inicioLocal, finLocal)
            SELECT f.fecha,
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaInicio, 108)) AS DATETIME2),
                   CAST(CONCAT(CONVERT(CHAR(10), f.fecha, 23), 'T', CONVERT(CHAR(8), h.horaFin, 108)) AS DATETIME2)
            FROM fechas f
            INNER JOIN dbo.Horario h ON h.grupo = @idGrupoDefecto
            INNER JOIN dbo.Dia d ON d.id = h.dia
            WHERE d.codigo = CASE DATEDIFF(DAY, '19000101', f.fecha) % 7
                                 WHEN 0 THEN 'LU' WHEN 1 THEN 'MA' WHEN 2 THEN 'MI' WHEN 3 THEN 'JU'
                                 WHEN 4 THEN 'VI' WHEN 5 THEN 'SA' ELSE 'DO' END
            OPTION (MAXRECURSION 0);

            -- Una hora local inexistente (salto de horario de verano) se desplaza en silencio: se aborta antes de escribir
            SELECT TOP 1 @fechaHoraLocalInexistente = x.horaLocal
            FROM (SELECT horaLocal = inicioLocal FROM @slots UNION ALL SELECT finLocal FROM @slots) x
            WHERE CAST(x.horaLocal AT TIME ZONE @zonaHorariaSqlServer AS DATETIME2) <> x.horaLocal
            ORDER BY x.horaLocal;

            IF @fechaHoraLocalInexistente IS NOT NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SES_005', @p_param1 = @zonaHorariaSqlServer, @p_param2 = @fechaHoraLocalInexistente,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            UPDATE @slots
            SET inicioUtc = CAST(inicioLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2),
                finUtc = CAST(finLocal AT TIME ZONE @zonaHorariaSqlServer AT TIME ZONE 'UTC' AS DATETIME2);

            -- Solo lo que aun no empezo: el pasado no se genera ni se toca
            DELETE FROM @slots WHERE inicioUtc <= @ahoraUtc;

            -- PASO 4: Sesiones futuras generadas que ya no encajan en el horario y no tienen asistencia ni clasificacion
            DELETE s
            FROM dbo.Sesion s
            WHERE s.grupo = @idGrupoDefecto
              AND s.fechaHoraInicio > @ahoraUtc
              AND s.procedenciaTemporal = N'UTC_GENERADOR'
              AND NOT EXISTS (SELECT 1 FROM @slots x WHERE x.inicioUtc = s.fechaHoraInicio AND x.finUtc = s.fechaHoraFin)
              AND NOT EXISTS (SELECT 1 FROM dbo.Asistencia a WHERE a.sesion = s.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.SesionProcedenciaClasificacion c WHERE c.sesion = s.id);
            SET @sesionesEliminadas = @@ROWCOUNT;

            -- PASO 5: Sesiones que faltan, con correlativo protegido contra carreras con usp_crear_sesion
            SELECT @maxNumeroSesion = MAX(numero) FROM dbo.Sesion WITH (UPDLOCK, HOLDLOCK) WHERE grupo = @idGrupoDefecto;

            INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
            SELECT NEWID(),
                   CONCAT(N'Sesi', NCHAR(243), N'n ', CAST(n.numero AS NVARCHAR(10))),
                   n.numero,
                   UPPER(LEFT(REPLACE(CAST(NEWID() AS NVARCHAR(50)), '-', ''), 6)),
                   DATEDIFF(WEEK, @fechaInicio, n.fecha) + 1,
                   @idGrupoDefecto,
                   n.inicioUtc,
                   n.finUtc,
                   N'UTC_GENERADOR'
            FROM (
                SELECT x.fecha, x.inicioUtc, x.finUtc,
                       numero = COALESCE(@maxNumeroSesion, 0) + ROW_NUMBER() OVER (ORDER BY x.inicioUtc)
                FROM @slots x
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.Sesion e
                    WHERE e.grupo = @idGrupoDefecto AND e.fechaHoraInicio = x.inicioUtc AND e.fechaHoraFin = x.finUtc)
            ) n;
            SET @sesionesCreadas = @@ROWCOUNT;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
