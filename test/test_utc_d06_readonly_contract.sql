-- Copia verbatim de alejovh12/AsistenciasUCO docs/work-items/MAINT-003E-utc-unblock/DB_D06_READONLY_CONTRACT_ASSERTIONS.sql
-- (contrato read-only entregado por backend). Solo se agrega el marcador TEST_PASS al final.
/*
 * MAINT-003E / UTC-D06 — CONTRACT-FIRST READ-ONLY VERIFIER.
 * SQL Server 2022, isolated test database (gestionasistenciadb).
 * Expected RED until owner migrates schema. Does not modify data, create tables,
 * open transactions, or classify legacy records. Run with sqlcmd -b so THROW fails CI.
 * It proves metadata and view shape only; it does NOT certify DML protections,
 * SP atomicity, live JWT ownership or any runtime writes. Those need separate IT.
 */
USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
DECLARE @sesionId INT = OBJECT_ID(N'dbo.Sesion', N'U');
DECLARE @v1Id INT = OBJECT_ID(N'dbo.uv_sesion', N'V');
DECLARE @v2Id INT = OBJECT_ID(N'dbo.uv_sesion_v2', N'V');

IF @sesionId IS NULL THROW 52101, 'D06 RED: dbo.Sesion is absent', 1;
IF @v1Id IS NULL THROW 52102, 'D06 RED: dbo.uv_sesion is absent', 1;
IF @v2Id IS NULL THROW 52103, 'D06 RED: dbo.uv_sesion_v2 is absent', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = @sesionId
      AND name = N'procedenciaTemporal'
      AND TYPE_NAME(user_type_id) = N'nvarchar'
      AND max_length = 48 -- NVARCHAR(24) bytes
      AND is_nullable = 1
)
    THROW 52104, 'D06 RED: Sesion.procedenciaTemporal must be nullable NVARCHAR(24)', 1;

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = @sesionId
      AND is_disabled = 0
      AND is_not_trusted = 0
      AND definition LIKE N'%procedenciaTemporal%'
)
    THROW 52105, 'D06 RED: enabled trusted CHECK for provenance is missing', 1;

DECLARE @v1 TABLE (column_id INT NOT NULL PRIMARY KEY, name SYSNAME NOT NULL);
INSERT INTO @v1(column_id,name) VALUES
  (1,N'id'), (2,N'nombre'), (3,N'numero'), (4,N'codigo'),
  (5,N'numeroSemana'), (6,N'idGrupo'), (7,N'codigoGrupo'),
  (8,N'nombreGrupo'), (9,N'fechaHoraInicio'), (10,N'fechaHoraFin');

IF EXISTS (
    SELECT column_id,name FROM @v1
    EXCEPT
    SELECT column_id,name FROM sys.columns WHERE object_id = @v1Id
)
OR EXISTS (
    SELECT column_id,name FROM sys.columns WHERE object_id = @v1Id
    EXCEPT
    SELECT column_id,name FROM @v1
)
    THROW 52106, 'D06 REGRESSION: uv_sesion legacy columns/order changed', 1;

DECLARE @v2 TABLE (column_id INT NOT NULL PRIMARY KEY, name SYSNAME NOT NULL);
INSERT INTO @v2 SELECT column_id,name FROM @v1;
INSERT INTO @v2(column_id,name) VALUES (11,N'procedenciaTemporal');

IF EXISTS (
    SELECT column_id,name FROM @v2
    EXCEPT
    SELECT column_id,name FROM sys.columns WHERE object_id = @v2Id
)
OR EXISTS (
    SELECT column_id,name FROM sys.columns WHERE object_id = @v2Id
    EXCEPT
    SELECT column_id,name FROM @v2
)
    THROW 52107, 'D06 RED: uv_sesion_v2 must project 10 legacy fields and provenance', 1;

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id IN (@v1Id,@v2Id)
      AND name IN (N'fechaHoraInicio',N'fechaHoraFin')
      AND (TYPE_NAME(user_type_id) <> N'datetime2' OR scale <> 7)
)
    THROW 52108, 'D06 REGRESSION: session datetime2(7) contract changed', 1;

PRINT 'PASS D06 readonly schema/view metadata contract. WRITE/ROLE/ATOMICITY IT STILL REQUIRED.';
GO
PRINT 'TEST_PASS:UTC_D06_READONLY_CONTRACT';
GO
