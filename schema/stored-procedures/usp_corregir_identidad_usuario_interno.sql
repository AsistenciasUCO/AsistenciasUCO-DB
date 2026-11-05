USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_corregir_identidad_usuario_interno (HU159, decision de John 2026-11-05)
--
-- Nucleo comun de la correccion de identidad (nombres, apellidos y documento) de un usuario cuya jerarquia ya valido
-- la fachada (decano por el administrador, estudiante por el coordinador de su programa):
--   0. valida el documento sin escribir (un rechazo no necesita ROLLBACK);
--   1. instantanea de los valores anteriores (ufn_obtener_identidad_usuario_json);
--   2. nombres y apellidos con usp_actualizar_datos_usuario_interno (el correo se conserva);
--   3. documento con usp_corregir_documento_usuario_interno (aislado; apagable por parametro);
--   4. auditoria con el motivo y los valores anteriores y nuevos (usp_registrar_auditoria_identidad_interno).
-- El motivo lo valida la fachada (obligatorio siempre en este flujo). Sin transaccion propia.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_corregir_identidad_usuario_interno]
(
    @idUsuario               UNIQUEIDENTIFIER,
    @idTipoIdIdentificacion  UNIQUEIDENTIFIER,
    @numeroIdentificacion    INT,
    @primerNombre            NVARCHAR(50),
    @segundoNombre           NVARCHAR(50),
    @primerApellido          NVARCHAR(50),
    @segundoApellido         NVARCHAR(50),
    @motivo                  NVARCHAR(500),
    @accionAuditoria         VARCHAR(120),
    @tipoRecurso             VARCHAR(120),
    @idRecurso               UNIQUEIDENTIFIER,
    @rutaAuditoria           NVARCHAR(240),
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @identidadAnterior NVARCHAR(MAX) = dbo.ufn_obtener_identidad_usuario_json(@idUsuario);
    DECLARE @correoActual      NVARCHAR(100) = (SELECT u.correo FROM dbo.Usuario u WHERE u.id = @idUsuario);
    DECLARE @documentoCambiado BIT = 0;
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.usp_corregir_documento_usuario_interno
        @idUsuario = @idUsuario,
        @idTipoIdIdentificacion = @idTipoIdIdentificacion,
        @numeroIdentificacion = @numeroIdentificacion,
        @motivo = @motivo,
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT,
        @documentoCambiado = @documentoCambiado OUTPUT,
        @soloValidar = 1;

    IF @estadoResultado = 1
    EXEC dbo.usp_actualizar_datos_usuario_interno
        @idUsuario = @idUsuario,
        @primerNombre = @primerNombre,
        @segundoNombre = @segundoNombre,
        @primerApellido = @primerApellido,
        @segundoApellido = @segundoApellido,
        @correo = @correoActual,
        @idCorrelacion = @idCorrelacion,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_corregir_documento_usuario_interno
            @idUsuario = @idUsuario,
            @idTipoIdIdentificacion = @idTipoIdIdentificacion,
            @numeroIdentificacion = @numeroIdentificacion,
            @motivo = @motivo,
            @idCorrelacion = @idCorrelacion,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT,
            @documentoCambiado = @documentoCambiado OUTPUT;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_registrar_auditoria_identidad_interno
            @idUsuario = @idUsuario,
            @identidadAnterior = @identidadAnterior,
            @motivo = @motivo,
            @accion = @accionAuditoria,
            @tipoRecurso = @tipoRecurso,
            @idRecurso = @idRecurso,
            @ruta = @rutaAuditoria,
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'IDE_002',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacion);
    END
END;
GO
