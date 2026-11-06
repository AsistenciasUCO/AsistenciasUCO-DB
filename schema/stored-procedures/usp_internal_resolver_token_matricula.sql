USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): resuelve la ventana ACTIVA a la que pertenece un token o un PIN y decide si es utilizable.
-- Interno: lo invocan usp_validar_token_matricula_publico y usp_matricular_estudiante_por_token dentro de su transaccion.
--   * Exactamente uno de @tokenHash / @pin (si no: MQR_007).
--   * Coincide con el token/PIN VIGENTE  -> valido mientras la ventana no llegue a fechaExpiracionUtc.
--   * Coincide con el token/PIN ANTERIOR -> valido solo durante MATRICULA_QR/TOLERANCIA_SEGUNDOS desde la rotacion.
--   * Una ventana ACTIVA que ya llego a su fin se marca EXPIRADA de forma perezosa (escritura persistida por el llamador).
-- Cualquier otro caso devuelve el mismo codigo MQR_001 (anti-enumeracion: no distingue inexistente, cerrado o vencido).
-- Toma UPDLOCK/HOLDLOCK sobre la fila para serializar matriculas y rotaciones concurrentes.
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_resolver_token_matricula]
(
    @tokenHash       VARBINARY(32),
    @pin             NCHAR(6),
    @idVentana       UNIQUEIDENTIFIER OUTPUT,
    @idGrupo         UNIQUEIDENTIFIER OUTPUT,
    @idDocenteEmisor UNIQUEIDENTIFIER OUTPUT,
    @codigoRechazo   VARCHAR(20) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @idVentana = NULL, @idGrupo = NULL, @idDocenteEmisor = NULL, @codigoRechazo = NULL;

    IF (@tokenHash IS NULL AND @pin IS NULL) OR (@tokenHash IS NOT NULL AND @pin IS NOT NULL)
    BEGIN
        SET @codigoRechazo = 'MQR_007';
        RETURN;
    END

    DECLARE @estadoActiva   NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_ACTIVA') AS NVARCHAR(10));
    DECLARE @estadoExpirada NVARCHAR(10) = CAST(dbo.ufn_obtener_parametro('MATRICULA_QR', 'ESTADO_EXPIRADA') AS NVARCHAR(10));
    DECLARE @tolerancia     INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'TOLERANCIA_SEGUNDOS');

    DECLARE @ahora              DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @fechaExpiracionUtc DATETIME2(0);
    DECLARE @fechaRotacionUtc   DATETIME2(0);
    DECLARE @coincideVigente    BIT = 0;
    DECLARE @idEncontrado       UNIQUEIDENTIFIER;

    SELECT TOP (1)
        @idEncontrado       = t.id,
        @idGrupo            = t.grupo,
        @idDocenteEmisor    = t.docenteEmisor,
        @fechaExpiracionUtc = t.fechaExpiracionUtc,
        @fechaRotacionUtc   = t.fechaRotacionUtc,
        @coincideVigente    = IIF((@tokenHash IS NOT NULL AND t.tokenHash = @tokenHash) OR (@pin IS NOT NULL AND t.pin = @pin), 1, 0)
    FROM dbo.TokenMatriculaGrupo t WITH (UPDLOCK, HOLDLOCK)
    WHERE t.estado = @estadoActiva
      AND (
            (@tokenHash IS NOT NULL AND (t.tokenHash = @tokenHash OR t.tokenHashAnterior = @tokenHash))
         OR (@pin IS NOT NULL AND (t.pin = @pin OR t.pinAnterior = @pin))
          );

    IF @idEncontrado IS NULL
    BEGIN
        SET @codigoRechazo = 'MQR_001';
        RETURN;
    END

    -- Fin de la ventana: expiracion perezosa
    IF @ahora >= @fechaExpiracionUtc
    BEGIN
        UPDATE dbo.TokenMatriculaGrupo SET estado = @estadoExpirada WHERE id = @idEncontrado;
        SELECT @idGrupo = NULL, @idDocenteEmisor = NULL;
        SET @codigoRechazo = 'MQR_001';
        RETURN;
    END

    -- Token anterior fuera de la tolerancia
    IF @coincideVigente = 0 AND @ahora >= DATEADD(SECOND, @tolerancia, @fechaRotacionUtc)
    BEGIN
        SELECT @idGrupo = NULL, @idDocenteEmisor = NULL;
        SET @codigoRechazo = 'MQR_001';
        RETURN;
    END

    SET @idVentana = @idEncontrado;
END;
GO
