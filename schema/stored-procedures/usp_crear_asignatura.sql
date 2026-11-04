USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_crear_asignatura
-- Reglas de negocio (decisiones de John, 2026-11-04):
--   * P5: el area y el componente deben existir en sus tablas (GEN_001); nunca se asigna uno "cualquiera".
--   * Creditos obligatorios y mayores que cero (ASI_001); no hay valor por defecto.
--   * El semestre debe existir en el plan de estudios (PLA_004); la malla del plan no se amplia desde aqui.
--   * El coordinador solo crea asignaturas en planes de su propio programa (PLA_002 si el plan no existe,
--     SEC_002 por usp_validar_titularidad_jerarquica_interno si el programa no es suyo).
-- Salida canonica: (idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_crear_asignatura]
(
    @idAsignatura       UNIQUEIDENTIFIER,
    @codigo             NVARCHAR(50),
    @nombre             NVARCHAR(50),
    @creditos           INT,
    @idPlanEstudio      UNIQUEIDENTIFIER,
    @semestreNumero     INT,
    @nombreArea         NVARCHAR(100),
    @nombreComponente   NVARCHAR(100),
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idUsuarioEjecutor  UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idAsignaturaDefecto      UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idAsignatura, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idPlanEstudioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPlanEstudio, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @codigoDefecto            NVARCHAR(50)     = UPPER(TRIM(@codigo));
    DECLARE @nombreDefecto            NVARCHAR(50)     = TRIM(@nombre);
    DECLARE @nombreAreaDefecto        NVARCHAR(100)    = TRIM(@nombreArea);
    DECLARE @nombreCompDefecto        NVARCHAR(100)    = TRIM(@nombreComponente);

    DECLARE @idAreaResolved       UNIQUEIDENTIFIER;
    DECLARE @idComponenteResolved UNIQUEIDENTIFIER;
    DECLARE @idSpeResolved        UNIQUEIDENTIFIER;
    DECLARE @idProgramaPlan       UNIQUEIDENTIFIER;

    -- Variables locales de respuesta
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Validación del identificador de correlación
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
                @codigoPerfilRequerido = 'COORDINADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 2: Validación de parámetros obligatorios
        IF @estadoResultado = 1 AND (@codigoDefecto IS NULL OR @codigoDefecto = '' OR @nombreDefecto IS NULL OR @nombreDefecto = '')
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'VAL_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Codigo y Nombre son obligatorios. Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.1: Creditos obligatorios y mayores que cero (ASI_001), sin valor por defecto
        IF @estadoResultado = 1 AND (@creditos IS NULL OR @creditos <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'ASI_001',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2.2: El plan existe (PLA_002) y pertenece al programa del coordinador (SEC_002)
        IF @estadoResultado = 1
        BEGIN
            SELECT @idProgramaPlan = idPrograma FROM [dbo].[uv_plan_estudio] WHERE id = @idPlanEstudioDefecto;

            IF @idProgramaPlan IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PLA_002',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_titularidad_jerarquica_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @idEntidadPadre = @idProgramaPlan,
                @tipoEntidadPadre = 'PROGRAMA',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: Validación de unicidad de código consultando uv_asignatura
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[uv_asignatura] WHERE UPPER(TRIM(codigo)) = @codigoDefecto)
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'VAL_006',
                    @p_param1 = 'Asignatura',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 4: Resolución de Área y Componente desde las tablas (P5, 2026-11-04): coincidencia exacta con su código
        -- o nombre; si no existen se rechaza con GEN_001. Nunca se asigna uno "cualquiera".
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_resolver_area_componente_asignatura_interno
                @area = @nombreAreaDefecto,
                @componente = @nombreCompDefecto,
                @obligatorios = 1,
                @idCorrelacion = @idCorrelacionDefecto,
                @idArea = @idAreaResolved OUTPUT,
                @idComponente = @idComponenteResolved OUTPUT,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 4.1: El semestre debe existir en el plan de estudios (PLA_004); no se crea desde aqui
        IF @estadoResultado = 1
        BEGIN
            SELECT @idSpeResolved = id
            FROM [dbo].[uv_semestre_plan_estudio]
            WHERE idPlanEstudio = @idPlanEstudioDefecto AND numeroSemestre = @semestreNumero;

            IF @idSpeResolved IS NULL
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PLA_004',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END
        END

        -- PASO 5: Inserción de Asignatura y generación de mensaje de éxito desde catálogo
        IF @estadoResultado = 1
        BEGIN
            INSERT INTO dbo.Asignatura (
                id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado
            )
            VALUES (
                @idAsignaturaDefecto,
                @codigoDefecto,
                @nombreDefecto,
                @creditos,
                @idAreaResolved,
                @idComponenteResolved,
                @idSpeResolved,
                1
            );

            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_004',
                @p_param1 = 'Asignatura',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
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

    -- BLOQUE FINAL: Retorno unificado de resultados
    SELECT 
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
