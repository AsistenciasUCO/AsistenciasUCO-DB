USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- Procedimiento: [dbo].[usp_insertar_programa_academico_interno]
-- Historia de Usuario: HU076
-- Ambito: alta atomica del programa: valida (con bloqueo del coordinador) e inserta con estado activo.
-- La transaccion vive aqui (SET XACT_ABORT ON, transaccion propia o savepoint si el llamador ya tiene una).
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_insertar_programa_academico_interno]
(
    @idPrograma              UNIQUEIDENTIFIER,
    @idFacultad              UNIQUEIDENTIFIER,
    @nombre                  NVARCHAR(100),
    @idTipoPrograma          UNIQUEIDENTIFIER,
    @idCoordinador           UNIQUEIDENTIFIER,
    @idModalidad             UNIQUEIDENTIFIER = NULL,
    @idJornada               UNIQUEIDENTIFIER = NULL,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @transaccionPropia BIT = 0;
    DECLARE @savepointCreado   BIT = 0;
    DECLARE @msgP1 NVARCHAR(500), @msgP2 NVARCHAR(500);
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    SET @estadoResultado = 1;

    BEGIN TRY
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_insertar_programa;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_validar_programa_academico_interno
                @idPrograma = NULL,
                @idFacultad = @idFacultad,
                @nombre = @nombre,
                @idTipoPrograma = @idTipoPrograma,
                @idCoordinador = @idCoordinador,
                @idModalidad = @idModalidad,
                @idJornada = @idJornada,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado, modalidad, jornada)
                VALUES (@idPrograma, @idFacultad, @idTipoPrograma, TRIM(@nombre), @idCoordinador, 1, @idModalidad, @idJornada);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_004',
                    @p_param1 = 'Programa Academico',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END

            -- Una validacion de negocio fallida no escribio nada: se libera la transaccion propia.
            IF @estadoResultado = 0 AND @transaccionPropia = 1 AND @@TRANCOUNT > 0
            BEGIN
                ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END

            IF @estadoResultado = 1 AND @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
            END
        END
    END TRY
    BEGIN CATCH
        IF @savepointCreado = 1 AND XACT_STATE() = 1
        BEGIN
            ROLLBACK TRANSACTION sp_insertar_programa;
        END
        ELSE IF @transaccionPropia = 1 AND @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
