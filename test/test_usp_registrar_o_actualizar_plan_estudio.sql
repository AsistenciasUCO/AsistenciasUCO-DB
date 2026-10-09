USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Contrato de dbo.usp_registrar_o_actualizar_plan_estudio (provider publico, TD-043 STUDY_PLAN_PROVIDER).
-- Modelo real de dbo.PlanEstudio: (id, programa, inp, estado). Sin columnas codigo ni nombre.
-- Cubre: creacion, actualizacion (upsert determinista por idPlanEstudio), programa inexistente (PROG_001),
-- inp invalido (PLA_001) y el contrato canonico de 4 columnas. Toda escritura corre dentro de una
-- transaccion externa que se revierte al final (no queda ningun residuo).
PRINT 'TEST START: test_usp_registrar_o_actualizar_plan_estudio';

DECLARE @programa UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_programa WHERE estaActivoPrograma = 1 ORDER BY id);
IF @programa IS NULL
    THROW 54600, 'TEST FAILED: PLAN_ESTUDIO fixture missing an active programa.', 1;

IF OBJECT_ID('tempdb..#res') IS NOT NULL DROP TABLE #res;
CREATE TABLE #res (
    idCorrelacion UNIQUEIDENTIFIER NULL,
    mensajeUsuarioResultado NVARCHAR(MAX) NULL,
    mensajeTecnicoResultado NVARCHAR(MAX) NULL,
    estadoResultado INT NOT NULL
);

DECLARE @corr UNIQUEIDENTIFIER;
DECLARE @msgUsuario NVARCHAR(4000), @msgTecnico NVARCHAR(4000);
DECLARE @idPlan UNIQUEIDENTIFIER;
DECLARE @inp INT;
DECLARE @inpTexto NVARCHAR(20);

BEGIN TRANSACTION;

-- ---------------------------------------------------------------------------------------------
-- 1. Crear: plan nuevo -> estado 1, SUC_REGISTRO_PLAN_ESTUDIO, una fila en dbo.PlanEstudio.
-- ---------------------------------------------------------------------------------------------
SET @idPlan = NEWID();
SET @inp = 100000 + ABS(CHECKSUM(NEWID()) % 100000);
SET @corr = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_o_actualizar_plan_estudio
    @idPlanEstudio = @idPlan, @idPrograma = @programa, @inp = @inp, @idCorrelacion = @corr;
SET @inpTexto = CAST(@inp AS NVARCHAR(20));
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SUC_REGISTRO_PLAN_ESTUDIO', @p_param1 = @inpTexto,
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario)
    THROW 54610, 'TEST FAILED: PLAN_ESTUDIO_CREATE expected canonical SUC_REGISTRO_PLAN_ESTUDIO with estado 1.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @idPlan AND programa = @programa AND inp = @inp AND estado = 1)
    THROW 54611, 'TEST FAILED: PLAN_ESTUDIO_CREATE did not insert the expected row.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_CREATE';

-- ---------------------------------------------------------------------------------------------
-- 2. Actualizar: mismo idPlanEstudio con un inp distinto -> upsert determinista (UPDATE, no INSERT).
-- ---------------------------------------------------------------------------------------------
DECLARE @inpActualizado INT = @inp + 1;
SET @corr = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_o_actualizar_plan_estudio
    @idPlanEstudio = @idPlan, @idPrograma = @programa, @inp = @inpActualizado, @idCorrelacion = @corr;
SET @inpTexto = CAST(@inpActualizado AS NVARCHAR(20));
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'SUC_ACTUALIZACION_PLAN_ESTUDIO', @p_param1 = @inpTexto,
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 1 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario)
    THROW 54620, 'TEST FAILED: PLAN_ESTUDIO_UPDATE expected canonical SUC_ACTUALIZACION_PLAN_ESTUDIO with estado 1.', 1;
IF (SELECT COUNT(*) FROM dbo.PlanEstudio WHERE id = @idPlan) <> 1
    THROW 54621, 'TEST FAILED: PLAN_ESTUDIO_UPDATE must not duplicate the row (upsert deterministico).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @idPlan AND inp = @inpActualizado)
    THROW 54622, 'TEST FAILED: PLAN_ESTUDIO_UPDATE did not persist the new inp.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_UPDATE';

-- ---------------------------------------------------------------------------------------------
-- 3. Programa inexistente -> PROG_001 (no PRG_001), cero escrituras.
-- ---------------------------------------------------------------------------------------------
DECLARE @programaInexistente UNIQUEIDENTIFIER = NEWID();
DECLARE @idPlanProgramaInexistente UNIQUEIDENTIFIER = NEWID();
SET @inp = 200000 + ABS(CHECKSUM(NEWID()) % 100000);
SET @corr = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_o_actualizar_plan_estudio
    @idPlanEstudio = @idPlanProgramaInexistente, @idPrograma = @programaInexistente, @inp = @inp, @idCorrelacion = @corr;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PROG_001', @p_param1 = @programaInexistente,
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 54630, 'TEST FAILED: PLAN_ESTUDIO_PROGRAM_NOT_FOUND expected canonical PROG_001.', 1;
IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @idPlanProgramaInexistente)
    THROW 54631, 'TEST FAILED: PLAN_ESTUDIO_PROGRAM_NOT_FOUND produced a write.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_PROGRAM_NOT_FOUND';

-- ---------------------------------------------------------------------------------------------
-- 4. inp invalido (NULL y <= 0) -> PLA_001, cero escrituras.
-- ---------------------------------------------------------------------------------------------
DECLARE @idPlanInpInvalido UNIQUEIDENTIFIER = NEWID();
SET @corr = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_o_actualizar_plan_estudio
    @idPlanEstudio = @idPlanInpInvalido, @idPrograma = @programa, @inp = 0, @idCorrelacion = @corr;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PLA_001', @p_param1 = '0',
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 54640, 'TEST FAILED: PLAN_ESTUDIO_INP_INVALID expected canonical PLA_001 for inp = 0.', 1;
IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @idPlanInpInvalido)
    THROW 54641, 'TEST FAILED: PLAN_ESTUDIO_INP_INVALID produced a write for inp = 0.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_INP_INVALID';

-- ---------------------------------------------------------------------------------------------
-- 4b. inp NULL -> PLA_001, cero escrituras.
-- ---------------------------------------------------------------------------------------------
DECLARE @idPlanInpNulo UNIQUEIDENTIFIER = NEWID();
SET @corr = NEWID();
TRUNCATE TABLE #res;
INSERT INTO #res EXEC dbo.usp_registrar_o_actualizar_plan_estudio
    @idPlanEstudio = @idPlanInpNulo, @idPrograma = @programa, @inp = NULL, @idCorrelacion = @corr;
EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'PLA_001', @p_param1 = NULL,
    @mensajeUsuarioResultado = @msgUsuario OUTPUT, @mensajeTecnicoResultado = @msgTecnico OUTPUT;
IF NOT EXISTS (SELECT 1 FROM #res WHERE estadoResultado = 0 AND idCorrelacion = @corr
    AND mensajeUsuarioResultado = @msgUsuario AND mensajeTecnicoResultado = CONCAT(@msgTecnico, ' Correlacion: ', @corr))
    THROW 54645, 'TEST FAILED: PLAN_ESTUDIO_INP_NULL expected canonical PLA_001 for inp = NULL.', 1;
IF EXISTS (SELECT 1 FROM dbo.PlanEstudio WHERE id = @idPlanInpNulo)
    THROW 54646, 'TEST FAILED: PLAN_ESTUDIO_INP_NULL produced a write for inp = NULL.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_INP_NULL';

-- ---------------------------------------------------------------------------------------------
-- 5. Resultado canonico: siempre 1 fila y exactamente 4 columnas (idCorrelacion, mensajeUsuarioResultado,
--    mensajeTecnicoResultado, estadoResultado), tanto en exito como en fallo.
-- ---------------------------------------------------------------------------------------------
IF (SELECT COUNT(*) FROM #res) <> 1
    THROW 54650, 'TEST FAILED: PLAN_ESTUDIO_CANONICAL_RESULT expected exactly one row.', 1;
IF NOT EXISTS (
    SELECT 1 FROM tempdb.sys.columns c
    INNER JOIN tempdb.sys.tables t ON t.object_id = c.object_id
    WHERE t.name LIKE '#res%'
      AND c.name IN ('idCorrelacion', 'mensajeUsuarioResultado', 'mensajeTecnicoResultado', 'estadoResultado')
    GROUP BY t.object_id
    HAVING COUNT(*) = 4)
    THROW 54651, 'TEST FAILED: PLAN_ESTUDIO_CANONICAL_RESULT does not expose exactly the 4 canonical columns.', 1;
PRINT 'TEST_PASS:PLAN_ESTUDIO_CANONICAL_RESULT';

ROLLBACK TRANSACTION;
IF @@TRANCOUNT <> 0 THROW 54699, 'TEST FAILED: test_usp_registrar_o_actualizar_plan_estudio left transactions open.', 1;
DROP TABLE #res;
PRINT 'TEST END: test_usp_registrar_o_actualizar_plan_estudio';
GO
