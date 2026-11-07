USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_cerrar_tomas_vencidas (CULM-001 B.2; CONTRACT §2.8.2, §3.5, [SUPUESTO-B-09])
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION. Job del servidor (sin usuario, como usp_rotar_token_matricula_automatico).
-- Resultset: una fila por toma cerrada en esta pasada: idToma, idSesion, idGrupo, totalAusentesMarcados.
--
-- Cierra las tomas ABIERTAS cuya sesion ya cumplio SYSUTCDATETIME() >= fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS o esta
-- cancelada (maximo TOMA_ASISTENCIA/LOTE_CIERRE_AUTOMATICO por pasada). Una transaccion por toma con el orden de bloqueos
-- Sesion -> TomaAsistencia; la toma se vuelve a leer bloqueada y, si otra instancia (o el docente) ya la cerro, se omite:
-- dos pasadas concurrentes nunca cierran la misma toma dos veces. Si el modo marca ausentes (y la sesion no esta cancelada)
-- inserta SJC a los activos sin registro ANTES de cerrar (permitido aunque la ventana vencio: es el cierre automatico).
-- Un error en una toma no deshace las anteriores.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_cerrar_tomas_vencidas]
(
    @idCorrelacion UNIQUEIDENTIFIER
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @margenMinutos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS');
    DECLARE @lote          INT = dbo.ufn_obtener_parametro_int(NULL, 'TOMA_ASISTENCIA', 'LOTE_CIERRE_AUTOMATICO');
    DECLARE @idEstadoCerrada UNIQUEIDENTIFIER = (SELECT e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0);
    DECLARE @ahora DATETIME2 = SYSUTCDATETIME();

    DECLARE @candidatas TABLE (n INT IDENTITY(1,1) PRIMARY KEY, idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER);
    DECLARE @cerradas TABLE (idToma UNIQUEIDENTIFIER, idSesion UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, totalAusentesMarcados INT);
    DECLARE @i INT = 1, @total INT;
    DECLARE @idToma UNIQUEIDENTIFIER, @idSesion UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER;
    DECLARE @abierta BIT, @marcaPorModo BIT, @cancelada BIT, @marcados INT, @fechaCierre DATETIME2(0);
    DECLARE @transaccionPropia BIT;

    SET @margenMinutos = IIF(@margenMinutos IS NULL OR @margenMinutos < 0, 0, @margenMinutos);
    SET @lote = IIF(@lote IS NULL OR @lote < 1, 200, @lote);
    IF @idEstadoCerrada IS NULL
        THROW 52512, 'CULM001_B2_CATALOGO_INCONSISTENTE: falta EstadoTomaAsistencia(estaAbierta = 0).', 1;

    INSERT INTO @candidatas (idToma, idSesion, idGrupo)
    SELECT TOP (@lote) t.id, t.sesion, s.grupo
    FROM dbo.TomaAsistencia t WITH (READPAST)
    INNER JOIN dbo.Sesion s ON s.id = t.sesion
    WHERE t.fechaCierreUtc IS NULL
      AND (@ahora >= DATEADD(MINUTE, @margenMinutos, s.fechaHoraFin)
           OR EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = t.sesion))
    ORDER BY t.fechaAperturaUtc ASC, t.id ASC;
    SET @total = @@ROWCOUNT;

    WHILE @i <= @total
    BEGIN
        SELECT @idToma = idToma, @idSesion = idSesion, @idGrupo = idGrupo FROM @candidatas WHERE n = @i;
        SET @transaccionPropia = 0;
        BEGIN TRY
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
                SAVE TRANSACTION sp_cerrar_tomas_vencidas;

            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SET @abierta = 0;
            SELECT @abierta = IIF(t.fechaCierreUtc IS NULL, 1, 0), @marcaPorModo = m.marcaAusentesAlCerrar
            FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.ModoTomaAsistencia m ON m.id = t.modo
            WHERE t.id = @idToma;

            IF @abierta = 1
            BEGIN
                SET @cancelada = IIF(EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = @idSesion), 1, 0);
                SET @fechaCierre = SYSUTCDATETIME();
                SET @marcados = 0;

                UPDATE dbo.TokenAsistenciaToma SET fechaCierreUtc = @fechaCierre WHERE toma = @idToma AND fechaCierreUtc IS NULL;

                IF @marcaPorModo = 1 AND @cancelada = 0
                    EXEC dbo.usp_internal_marcar_ausentes_toma
                        @idToma = @idToma, @idSesion = @idSesion, @idGrupo = @idGrupo,
                        @fechaRegistroUtc = @fechaCierre, @totalMarcados = @marcados OUTPUT;

                UPDATE dbo.TomaAsistencia
                SET estado = @idEstadoCerrada,
                    fechaCierreUtc = IIF(@fechaCierre < fechaAperturaUtc, fechaAperturaUtc, @fechaCierre),
                    totalAusentesMarcados = @marcados,
                    idCorrelacionCierre = @idCorrelacionDefecto
                WHERE id = @idToma;

                INSERT INTO @cerradas (idToma, idSesion, idGrupo, totalAusentesMarcados) VALUES (@idToma, @idSesion, @idGrupo, @marcados);
            END

            IF @transaccionPropia = 1
                COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @transaccionPropia = 1 AND XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
            ELSE IF @transaccionPropia = 0 AND XACT_STATE() = 1
                ROLLBACK TRANSACTION sp_cerrar_tomas_vencidas;
            ELSE IF @transaccionPropia = 0 AND XACT_STATE() = -1
                THROW;
        END CATCH;
        SET @i += 1;
    END

    SELECT idToma, idSesion, idGrupo, totalAusentesMarcados FROM @cerradas;
END;
GO
