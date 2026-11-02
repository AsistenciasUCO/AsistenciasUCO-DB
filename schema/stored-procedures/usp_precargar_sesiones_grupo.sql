USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F2 (2026-11-02): precarga de las sesiones del grupo a partir de su horario. Pueden ejecutarla el COORDINADOR del programa del
-- grupo y el DOCENTE titular (HOR/SEC_002 si no). Genera solo sesiones futuras y retira las futuras generadas que ya no encajan
-- (ver usp_precargar_sesiones_grupo_interno). No sustituye a usp_generar_sesiones_grupo (congelado, solo docente titular,
-- genera desde el inicio del periodo); no lo modifica ni lo invoca.
CREATE OR ALTER PROCEDURE [dbo].[usp_precargar_sesiones_grupo]
(
    @idGrupo           UNIQUEIDENTIFIER,
    @idCorrelacion     UNIQUEIDENTIFIER,
    @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignatura             UNIQUEIDENTIFIER;
    DECLARE @idDocente                UNIQUEIDENTIFIER;
    DECLARE @idPrograma               UNIQUEIDENTIFIER;
    DECLARE @idDocenteEjecutor        UNIQUEIDENTIFIER;
    DECLARE @ejecutorEsCoordinador    BIT = 0;
    DECLARE @sesionesCreadas          INT = 0;
    DECLARE @sesionesEliminadas       INT = 0;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @conteoTransaccionesInicial INT = 0;
    DECLARE @transaccionPropia          BIT = 0;
    DECLARE @savepointCreado            BIT = 0;
    DECLARE @estadoTransaccionCatch     INT;

BEGIN
    -- Sin XACT_ABORT ON: con savepoint condenaria la transaccion del llamador (Msg 3930); ver skill procedimientos-externos-condiciones.
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validar el identificador de correlacion
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: Ejecutor obligatorio (GEN_002) y perfil COORDINADOR o DOCENTE
        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'COORDINADOR,DOCENTE',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: El grupo existe (VAL_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idAsignatura = g.idAsignatura, @idDocente = g.idDocente
            FROM dbo.uv_grupo g
            WHERE g.id = @idGrupoDefecto;

            IF @idAsignatura IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_002', @p_param1 = 'Grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Ambito. COORDINADOR: titular del programa de la asignatura del grupo. DOCENTE: titular del grupo (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_coordinador_identidad ci WHERE ci.idUsuario = @idUsuarioEjecutorDefecto)
            BEGIN
                SET @ejecutorEsCoordinador = 1;
            END

            SELECT @idDocenteEjecutor = di.id
            FROM dbo.uv_docente_identidad di
            WHERE di.idUsuario = @idUsuarioEjecutorDefecto;
        END

        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 1
        BEGIN
            SELECT TOP 1 @idPrograma = pe.idPrograma
            FROM dbo.uv_asignatura a
            INNER JOIN dbo.uv_semestre_plan_estudio spe ON a.idSemestrePlanEstudio = spe.id
            INNER JOIN dbo.uv_plan_estudio pe ON spe.idPlanEstudio = pe.id
            WHERE a.id = @idAsignatura;

            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idPrograma,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0 AND (@idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocente)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: El grupo tiene horario y su periodo tiene fechas coherentes
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_horarios_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_fechas_periodo_academico_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 6: Precarga atomica: transaccion propia, o savepoint si ya hay una abierta (p. ej. la del alta del grupo)
        IF @estadoResultado = 1
        BEGIN
            SET @conteoTransaccionesInicial = @@TRANCOUNT;
            IF @conteoTransaccionesInicial = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_precargar_sesiones_grupo;
                SET @savepointCreado = 1;
            END

            EXEC dbo.usp_precargar_sesiones_grupo_interno
                @idGrupo = @idGrupoDefecto,
                @idCorrelacion = @idCorrelacionDefecto,
                @sesionesCreadas = @sesionesCreadas OUTPUT,
                @sesionesEliminadas = @sesionesEliminadas OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;

            IF @estadoResultado = 1
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'GEN_005', @p_param1 = 'Sesiones del grupo',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Creadas: ', @sesionesCreadas,
                    '. Eliminadas: ', @sesionesEliminadas, '. Correlacion: ', @idCorrelacionDefecto);
            END

            -- Rechazo despues de escribir: se deshace todo lo escrito en este SP
            IF @estadoResultado = 0
            BEGIN
                IF @transaccionPropia = 1
                BEGIN
                    ROLLBACK TRANSACTION;
                    SET @transaccionPropia = 0;
                END
                ELSE
                BEGIN
                    ROLLBACK TRANSACTION sp_precargar_sesiones_grupo;
                    SET @savepointCreado = 0;
                END
            END
            ELSE IF @transaccionPropia = 1
            BEGIN
                COMMIT TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
            BEGIN
                ROLLBACK TRANSACTION;
            END
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
        BEGIN
            ROLLBACK TRANSACTION sp_precargar_sesiones_grupo;
        END
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
        BEGIN
            THROW;
        END
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
