USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- F1/F2/F3 (2026-11-02): validacion compartida de "quien puede gestionar el horario y las sesiones de un grupo"
-- (skill procedimientos-externos-condiciones, REC4 #5: la validacion repetida entre SP se extrae a un usp_validar_*_interno).
-- La usan usp_guardar_horarios_grupo y usp_precargar_sesiones_grupo.
--   * ejecutor obligatorio (GEN_002) con perfil COORDINADOR o DOCENTE (SEC_001);
--   * el grupo existe (VAL_002);
--   * COORDINADOR: debe coordinar el programa de la asignatura del grupo (SEC_002);
--   * DOCENTE: debe ser el titular del grupo (SEC_002).
-- Devuelve si el ejecutor actua como coordinador y el docente titular del grupo, para las reglas propias del caller.
CREATE OR ALTER PROCEDURE [dbo].[usp_validar_gestion_grupo_coordinador_o_titular_interno]
(
    @idGrupo                 UNIQUEIDENTIFIER,
    @idUsuarioEjecutor       UNIQUEIDENTIFIER,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @ejecutorEsCoordinador   BIT OUTPUT,
    @idDocenteTitular        UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idGrupoDefecto           UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idGrupo, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignatura             UNIQUEIDENTIFIER;
    DECLARE @idPrograma               UNIQUEIDENTIFIER;
    DECLARE @idDocenteEjecutor        UNIQUEIDENTIFIER;

    SELECT
        @ejecutorEsCoordinador = 0,
        @idDocenteTitular = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Ejecutor obligatorio (GEN_002) y perfil COORDINADOR o DOCENTE (SEC_001)
        IF @idUsuarioEjecutor IS NULL
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

        -- PASO 2: El grupo existe (VAL_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idAsignatura = g.idAsignatura, @idDocenteTitular = g.idDocente
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

        -- PASO 3: Ambito del ejecutor
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

        -- COORDINADOR: titular del programa de la asignatura del grupo
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

        -- DOCENTE: solo el titular del grupo
        IF @estadoResultado = 1 AND @ejecutorEsCoordinador = 0
           AND (@idDocenteEjecutor IS NULL OR @idDocenteEjecutor <> @idDocenteTitular)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'SEC_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
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
