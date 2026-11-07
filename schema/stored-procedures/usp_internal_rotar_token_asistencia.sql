USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_internal_rotar_token_asistencia (CULM-001 B.2, HU175; CONTRACT §2.8.3, DEC-015) - NUCLEO, no se concede EXECUTE.
--
-- Rota el token/PIN activo de una toma: mueve tokenHash/pin vigentes a tokenHashAnterior/pinAnterior y guarda los nuevos
-- (fechaRotacionUtc = ahora). Con @forzar = 0 solo rota si el token debe rotar (fechaRotacionUtc + ROTACION_SEGUNDOS
-- vencido); si otra instancia ya roto: @rotado = 0 y exito sin cambios (AQR_012). Token inexistente, cerrado o expirado, o
-- toma cerrada: AQR_005. PIN repetido entre activos o anteriores vigentes (o hash repetido): AQR_006 sin escritura.
-- Hash de 32 bytes y PIN de 6 digitos: GEN_002. No abre transaccion: la del llamador (publico manual o automatico).
-- Bloqueos: Sesion -> TomaAsistencia -> TokenAsistenciaToma.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_internal_rotar_token_asistencia]
(
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idToma                  UNIQUEIDENTIFIER,
    @tokenHash               VARBINARY(32),
    @pin                     NCHAR(6),
    @forzar                  BIT,
    @idUsuarioManual         UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT,
    @idTokenAsistencia       UNIQUEIDENTIFIER OUTPUT,
    @idDocenteEmisor         UNIQUEIDENTIFIER OUTPUT,
    @idGrupo                 UNIQUEIDENTIFIER OUTPUT,
    @fechaRotacionUtc        DATETIME2(0) OUTPUT,
    @fechaExpiracionUtc      DATETIME2(0) OUTPUT,
    @rotado                  BIT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @rotacionSegundos   INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'ROTACION_SEGUNDOS');
    DECLARE @toleranciaSegundos INT = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS');
    DECLARE @idSesion    UNIQUEIDENTIFIER;
    DECLARE @tomaAbierta BIT;
    DECLARE @ahora       DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @p1 NVARCHAR(500), @p2 NVARCHAR(500);

    SET @rotacionSegundos = IIF(@rotacionSegundos IS NULL OR @rotacionSegundos < 1, 60, @rotacionSegundos);
    SET @toleranciaSegundos = IIF(@toleranciaSegundos IS NULL OR @toleranciaSegundos < 0, 0, @toleranciaSegundos);
    SELECT @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
           @estadoResultado = 1, @rotado = 0, @idTokenAsistencia = NULL, @idDocenteEmisor = NULL, @idGrupo = NULL,
           @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1
       AND (@tokenHash IS NULL OR DATALENGTH(@tokenHash) <> 32 OR @pin IS NULL OR LEN(@pin) <> 6 OR @pin LIKE N'%[^0-9]%')
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'GEN_002', @p_param1 = 'tokenHash/pin',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 1
    BEGIN
        SELECT @idSesion = t.sesion FROM dbo.TomaAsistencia t WHERE t.id = @idToma;
        IF @idSesion IS NOT NULL
        BEGIN
            SELECT @idGrupo = s.grupo FROM dbo.Sesion s WITH (UPDLOCK, HOLDLOCK) WHERE s.id = @idSesion;
            SELECT @tomaAbierta = IIF(t.fechaCierreUtc IS NULL, 1, 0) FROM dbo.TomaAsistencia t WITH (UPDLOCK, HOLDLOCK) WHERE t.id = @idToma;
            SELECT @idTokenAsistencia = tk.id, @idDocenteEmisor = tk.docenteEmisor, @fechaRotacionUtc = tk.fechaRotacionUtc,
                   @fechaExpiracionUtc = tk.fechaExpiracionUtc
            FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
            WHERE tk.toma = @idToma AND tk.fechaCierreUtc IS NULL;
        END

        IF @idSesion IS NULL OR @tomaAbierta = 0 OR @idTokenAsistencia IS NULL OR @ahora >= @fechaExpiracionUtc
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_005', @p_param1 = @idToma,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
            SELECT @idTokenAsistencia = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL;
        END
    END

    -- Con @forzar = 0 solo rota si ya debe rotar; si no (otra instancia roto), exito sin cambios
    IF @estadoResultado = 1 AND (@forzar = 1 OR @ahora >= DATEADD(SECOND, @rotacionSegundos, @fechaRotacionUtc))
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK)
                   WHERE tk.fechaCierreUtc IS NULL
                     AND (tk.pin = @pin
                          OR (tk.pinAnterior = @pin AND @ahora < tk.fechaExpiracionUtc AND @ahora < DATEADD(SECOND, @toleranciaSegundos, tk.fechaRotacionUtc))))
           OR EXISTS (SELECT 1 FROM dbo.TokenAsistenciaToma tk WITH (UPDLOCK, HOLDLOCK) WHERE tk.tokenHash = @tokenHash OR tk.tokenHashAnterior = @tokenHash)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_006', @p_param1 = @pin,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END
        ELSE
        BEGIN
            UPDATE dbo.TokenAsistenciaToma
            SET tokenHashAnterior = tokenHash,
                pinAnterior = pin,
                tokenHash = @tokenHash,
                pin = @pin,
                fechaRotacionUtc = @ahora
            WHERE id = @idTokenAsistencia;
            SET @fechaRotacionUtc = @ahora;
            SET @rotado = 1;
        END
    END

    IF @estadoResultado = 1
    BEGIN
        SET @p1 = CONVERT(NVARCHAR(36), @idTokenAsistencia);
        SET @p2 = CONVERT(NVARCHAR(36), @idToma);
        EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'AQR_012', @p_param1 = @p1, @p_param2 = @p2,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
    END
    ELSE
        SELECT @idTokenAsistencia = NULL, @idDocenteEmisor = NULL, @fechaRotacionUtc = NULL, @fechaExpiracionUtc = NULL, @rotado = NULL;
END;
GO
