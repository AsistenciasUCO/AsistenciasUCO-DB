USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =====================================================================================
-- PUBLIC (consumido por el backend). TD-043 (STUDY_PLAN_PROVIDER): capability restaurada
-- contra el esquema ACTUAL.
--
-- Decision de contrato (documentada en docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md
-- y docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md):
--   dbo.PlanEstudio persiste (id, programa, inp, estado). NO existen columnas codigo ni nombre.
--   Por tanto el parametro es @inp INT (numero de plan). El nombre textual NO se persiste:
--   no se añade columna (sin necesidad contractual) ni se acepta un parametro fantasma.
--
-- Reglas:
--   - idCorrelacion obligatorio (interno de correlacion).
--   - idPlanEstudio obligatorio (sin fallback a GUID por defecto).
--   - inp obligatorio y entero positivo   -> PLA_001 (validacion).
--   - programa debe existir (uv_programa) -> PROG_001 (no encontrado).
--   - upsert determinista por idPlanEstudio: si existe UPDATE, si no INSERT (estado = 1).
--     Idempotente: repetir la misma llamada produce el mismo estado final.
--   - Sin regla de unicidad (programa, inp): no esta respaldada por una restriccion UNIQUE
--     del esquema ni por un contrato previo validado.
-- Lecturas: dbo.uv_plan_estudio (vista publica). Escrituras: dbo.PlanEstudio.
-- Transaccion: una unica sentencia de escritura (atomica por si misma); sin transaccion propia.
-- Salida: 1 fila, 4 columnas canonicas. Sin OUTPUT hacia el backend.
-- =====================================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_registrar_o_actualizar_plan_estudio]
(
    @idPlanEstudio UNIQUEIDENTIFIER,
    @idPrograma    UNIQUEIDENTIFIER,
    @inp           INT,
    @idCorrelacion UNIQUEIDENTIFIER
)
AS

DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
DECLARE @mensajeUsuarioResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @mensajeTecnicoResultado NVARCHAR(4000)   = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
DECLARE @estadoResultado         BIT              = 1;
DECLARE @existePlan              BIT              = 0;
DECLARE @inpTexto                NVARCHAR(20)     = CAST(@inp AS NVARCHAR(20));

BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- PASO 1: correlacion obligatoria
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: identificador del plan obligatorio (sin fallback)
        IF @estadoResultado = 1 AND @idPlanEstudio IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002',
                @p_param1 = 'idPlanEstudio',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 3: numero de plan (inp) obligatorio y entero positivo
        IF @estadoResultado = 1 AND (@inp IS NULL OR @inp <= 0)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PLA_001',
                @p_param1 = @inpTexto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: programa academico existente
        IF @estadoResultado = 1 AND NOT EXISTS (SELECT 1 FROM dbo.uv_programa p WHERE p.id = @idPrograma)
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PROG_001',
                @p_param1 = @idPrograma,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;

            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: upsert determinista por idPlanEstudio (una sola sentencia de escritura)
        IF @estadoResultado = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.uv_plan_estudio WHERE id = @idPlanEstudio)
            BEGIN
                SET @existePlan = 1;
            END

            IF @existePlan = 1
            BEGIN
                UPDATE dbo.PlanEstudio
                SET programa = @idPrograma,
                    inp      = @inp
                WHERE id = @idPlanEstudio;

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_ACTUALIZACION_PLAN_ESTUDIO',
                    @p_param1 = @inpTexto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.PlanEstudio (id, programa, inp, estado)
                VALUES (@idPlanEstudio, @idPrograma, @inp, 1);

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'SUC_REGISTRO_PLAN_ESTUDIO',
                    @p_param1 = @inpTexto,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            END

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

    -- BLOQUE FINAL: contrato canonico (4 columnas)
    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado;
END;
GO
