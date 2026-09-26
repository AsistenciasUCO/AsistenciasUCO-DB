USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_asistencia_estudiante_autonomo]
(
    @idEstudiante       UNIQUEIDENTIFIER,
    @idSesion           UNIQUEIDENTIFIER,
    @codigoVerificacion NVARCHAR(50),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    -- 1. Estandarización e inicialización de variables locales utilizando catálogo de parámetros (Sin ISNULL)
    DECLARE @idCorrelacionDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idEstudianteDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idEstudiante, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idSesionDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idSesion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoVerificacionDefecto NVARCHAR(50)     = TRIM(dbo.ufn_obtener_parametro_texto(@codigoVerificacion, 'GENERAL', 'CADENA_VACIA'));

    DECLARE @codigoReal NVARCHAR(50);

    -- Inicialización interna de variables de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- PASO 1: Validación de presencia del identificador de correlación obligatorio
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno 
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 1.5: Validación de perfil RBAC del usuario ejecutor si es suministrado
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ESTUDIANTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de existencia de la sesión de clase
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_sesion_exista_por_id_interno
                @idSesion = @idSesionDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de pertenencia activa del estudiante al grupo asociado a la sesión
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_estudiante_pertenece_a_grupo_de_sesion_interno
                @idEstudiante = @idEstudianteDefecto, 
                @idSesion = @idSesionDefecto, 
                @idCorrelacion = @idCorrelacionDefecto, 
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT, 
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT, 
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4: Validación del código de verificación dinámico de la sesión de clase
        IF @estadoResultado = 1
        BEGIN
            SELECT TOP 1 
                @codigoReal = TRIM(codigo)
            FROM [dbo].[Sesion]
            WHERE id = @idSesionDefecto;

            IF @codigoReal IS NULL OR @codigoReal <> @codigoVerificacionDefecto
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_007',
                    @p_param1 = 'codigoVerificacion',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Registro de la asistencia auto-gestionada por el estudiante (Estado AN - Asistió)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_sincronizar_asistencia_estudiante_interno
                @idEstudiante = @idEstudianteDefecto,
                @idSesion = @idSesionDefecto,
                @codigoEstado = 'AN',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: Evaluación de resultado final y generación de mensaje de éxito desde el Catálogo de Mensajes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'AsistenciaEstudianteAutonomo',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
        END

    END TRY
    BEGIN CATCH
        -- BLOQUE CATCH: Captura centralizada de excepciones inesperadas
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = [dbo].[ufn_obtener_detalle_error](@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    -- BLOQUE FINAL: Retorno unificado de resultados garantizando el nombre de columna idCorrelacion
    SELECT 
        idCorrelacion = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado = @estadoResultado;
END;
GO
