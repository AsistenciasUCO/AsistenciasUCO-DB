USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

-- HU091 (T-MIG-01..03): estructura, seed, backfill (R2) y retiro del SP autonomo (D7).
PRINT 'TEST START: test_migracion_docente_programa';

IF OBJECT_ID('dbo.TipoVinculacion', 'U') IS NULL THROW 52400, 'T-MIG FAILED: falta la tabla TipoVinculacion.', 1;
IF OBJECT_ID('dbo.DocentePrograma', 'U') IS NULL THROW 52401, 'T-MIG FAILED: falta la tabla DocentePrograma.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_DocentePrograma_docente_programa')
    THROW 52402, 'T-MIG FAILED: falta UNIQUE (docente, programa).', 1;
IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.DocentePrograma')) < 3
    THROW 52403, 'T-MIG FAILED: DocentePrograma debe tener FK a Docente, Programa y TipoVinculacion.', 1;
IF (SELECT COUNT(*) FROM dbo.TipoVinculacion WHERE codigo IN ('PLA','MTI','CAT','OCA') AND estado = 1) <> 4
    THROW 52404, 'T-MIG FAILED: catalogo semilla PLA/MTI/CAT/OCA incompleto.', 1;
IF OBJECT_ID('dbo.uv_tipo_vinculacion', 'V') IS NULL OR OBJECT_ID('dbo.uv_docente_programa', 'V') IS NULL OR OBJECT_ID('dbo.uv_auth_docente_programa', 'V') IS NULL
    THROW 52405, 'T-MIG FAILED: faltan las vistas uv_tipo_vinculacion / uv_docente_programa / uv_auth_docente_programa.', 1;
PRINT 'TEST_PASS:T-MIG-01';

-- T-MIG-02 (R2): todo par (docente, programa) que hoy sale de uv_docente tiene un vinculo.
IF EXISTS (
    SELECT 1 FROM (SELECT DISTINCT id AS idDocente, idPrograma FROM dbo.uv_docente) par
    WHERE NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = par.idDocente AND dp.programa = par.idPrograma))
    THROW 52410, 'T-MIG-02 FAILED: hay docentes con grupos sin vinculo (backfill incompleto).', 1;
IF EXISTS (SELECT 1 FROM dbo.DocentePrograma WHERE fechaVinculacionUtc IS NULL OR tipoVinculacion IS NULL)
    THROW 52411, 'T-MIG-02 FAILED: vinculos sin fecha o tipo.', 1;
PRINT 'TEST_PASS:T-MIG-02';

-- T-MIG-03 (D7): SP autonomo sin RBAC retirado
IF OBJECT_ID('dbo.usp_registrar_docente_en_grupo_autonomo', 'P') IS NOT NULL
    THROW 52420, 'T-MIG-03 FAILED: usp_registrar_docente_en_grupo_autonomo debio retirarse.', 1;
PRINT 'TEST_PASS:T-MIG-03';

-- Catalogo de mensajes DOC_* / IAM_001
IF EXISTS (
    SELECT 1 FROM (VALUES ('DOC_002'),('DOC_003'),('DOC_004'),('DOC_005'),('DOC_006'),('DOC_007'),('DOC_008'),('DOC_009'),('IAM_001')) x(codigo)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_usuario m WHERE m.codigo = x.codigo)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_mensaje_tecnico t WHERE t.codigo = x.codigo))
    THROW 52430, 'T-MIG FAILED: faltan mensajes de catalogo DOC_002..DOC_009 / IAM_001 (usuario o tecnico).', 1;
PRINT 'TEST_PASS:MENSAJES_DOC';
PRINT 'TEST_PASS:TEST_MIGRACION_DOCENTE_PROGRAMA';
GO
