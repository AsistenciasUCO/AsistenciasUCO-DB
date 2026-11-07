USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_resolver_token_asistencia (CULM-001 B.2, HU176; CONTRACT §2.8.3, DEC-015) - NUCLEO, no se concede EXECUTE.
--
-- Resuelve un hash de token o un PIN (exactamente uno; si no @codigoRechazo = AQR_007) contra el token VIGENTE (activo y
-- no expirado) o el ANTERIOR mientras dure ASISTENCIA_QR/TOLERANCIA_SEGUNDOS desde fechaRotacionUtc. Lectura sin UPDLOCK
-- (READ COMMITTED): 40 lecturas concurrentes no se serializan sobre la fila del token. Cualquier token/PIN desconocido,
-- cerrado o expirado devuelve el mismo AQR_001 (no revela si existio).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_resolver_token_asistencia]
(
    @tokenHash         VARBINARY(32) = NULL,
    @pin               NCHAR(6) = NULL,
    @idTokenAsistencia UNIQUEIDENTIFIER OUTPUT,
    @idToma            UNIQUEIDENTIFIER OUTPUT,
    @idSesion          UNIQUEIDENTIFIER OUTPUT,
    @idGrupo           UNIQUEIDENTIFIER OUTPUT,
    @codigoRechazo     VARCHAR(20) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @toleranciaSegundos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS');
    DECLARE @ahora DATETIME2 = SYSUTCDATETIME();
    SET @toleranciaSegundos = IIF(@toleranciaSegundos IS NULL OR @toleranciaSegundos < 0, 0, @toleranciaSegundos);
    SELECT @idTokenAsistencia = NULL, @idToma = NULL, @idSesion = NULL, @idGrupo = NULL, @codigoRechazo = NULL;

    IF (@tokenHash IS NULL AND @pin IS NULL) OR (@tokenHash IS NOT NULL AND @pin IS NOT NULL)
    BEGIN
        SET @codigoRechazo = 'AQR_007';
        RETURN;
    END

    IF @tokenHash IS NOT NULL
        SELECT TOP 1 @idTokenAsistencia = tk.id, @idToma = tk.toma
        FROM dbo.TokenAsistenciaToma tk
        WHERE tk.fechaCierreUtc IS NULL
          AND @ahora < tk.fechaExpiracionUtc
          AND (tk.tokenHash = @tokenHash
               OR (tk.tokenHashAnterior = @tokenHash AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc)))
        ORDER BY IIF(tk.tokenHash = @tokenHash, 0, 1);
    ELSE
        SELECT TOP 1 @idTokenAsistencia = tk.id, @idToma = tk.toma
        FROM dbo.TokenAsistenciaToma tk
        WHERE tk.fechaCierreUtc IS NULL
          AND @ahora < tk.fechaExpiracionUtc
          AND (tk.pin = @pin
               OR (tk.pinAnterior = @pin AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc)))
        ORDER BY IIF(tk.pin = @pin, 0, 1);

    IF @idTokenAsistencia IS NULL
    BEGIN
        SET @codigoRechazo = 'AQR_001';
        RETURN;
    END

    SELECT @idSesion = t.sesion, @idGrupo = s.grupo
    FROM dbo.TomaAsistencia t INNER JOIN dbo.Sesion s ON s.id = t.sesion
    WHERE t.id = @idToma;
END;
GO
