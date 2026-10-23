USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU121/HU122: esquema y vistas del coordinador (CONTRACT HU121-HU122 §2.1, §2.2, §2.6).
-- Cubre T-DDL-02, T-VIEW-01 y T-120R-02. La idempotencia de la migracion (T-DDL-01/03) se ejecuta en la fase 04 con el script.
PRINT 'TEST START: test_hu121_hu122_esquema_coordinador';

IF COL_LENGTH('dbo.Coordinador', 'estado') IS NULL
    THROW 51700, 'TEST FAILED T-DDL: dbo.Coordinador no tiene la columna estado.', 1;
IF COL_LENGTH('dbo.Coordinador', 'facultad') IS NULL
    THROW 51701, 'TEST FAILED T-DDL: dbo.Coordinador no tiene la columna facultad.', 1;

-- T-DDL: estado NOT NULL con DEFAULT 1 (filas existentes quedan activas)
IF NOT EXISTS (
    SELECT 1 FROM sys.columns c
    JOIN sys.default_constraints d ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id
    WHERE c.object_id = OBJECT_ID('dbo.Coordinador') AND c.name = 'estado' AND c.is_nullable = 0 AND d.definition LIKE '%1%')
    THROW 51702, 'TEST FAILED T-DDL: Coordinador.estado debe ser NOT NULL con DEFAULT 1.', 1;
IF EXISTS (SELECT 1 FROM dbo.Coordinador WHERE estado = 0)
    THROW 51703, 'TEST FAILED T-DDL: hay coordinadores inactivos antes de usar el SP de estado.', 1;

-- T-DDL: FK de facultad
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
    WHERE fk.parent_object_id = OBJECT_ID('dbo.Coordinador') AND fk.referenced_object_id = OBJECT_ID('dbo.Facultad')
      AND COL_NAME(fkc.parent_object_id, fkc.parent_column_id) = 'facultad')
    THROW 51704, 'TEST FAILED T-DDL: falta la FK Coordinador.facultad -> Facultad.', 1;

-- T-DDL-02: relleno de facultad desde el programa que coordina
IF EXISTS (
    SELECT 1 FROM dbo.Coordinador c JOIN dbo.Programa p ON p.coordinador = c.id
    WHERE c.facultad IS NULL OR c.facultad <> p.facultad)
    THROW 51705, 'TEST FAILED T-DDL-02: Coordinador.facultad no coincide con la facultad de su programa.', 1;

-- T-VIEW-01: columnas nuevas de uv_coordinador
DECLARE @columnasFaltantes NVARCHAR(500) = (
    SELECT STRING_AGG(v.nombre, ', ')
    FROM (VALUES (N'primerNombre'), (N'segundoNombre'), (N'primerApellido'), (N'segundoApellido'), (N'correo'),
                 (N'estaActivoRolCoordinador'), (N'idFacultad')) v(nombre)
    WHERE COL_LENGTH('dbo.uv_coordinador', v.nombre) IS NULL);
IF @columnasFaltantes IS NOT NULL
    THROW 51706, 'TEST FAILED T-VIEW-01: uv_coordinador no expone todas las columnas del contrato.', 1;

-- T-120R-02: usp_crear_coordinador fija Coordinador.facultad (coordinador sin programa conserva su facultad)
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_tipo_identificacion WHERE tipoIdentificacion = 'CC');
DECLARE @idFacultadF1 UNIQUEIDENTIFIER = (SELECT TOP 1 idFacultad FROM dbo.uv_programa);
DECLARE @idDecanoF1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.uv_decano);
DECLARE @idUsuarioD1 UNIQUEIDENTIFIER = (SELECT TOP 1 idUsuario FROM dbo.uv_decano_identidad WHERE id = @idDecanoF1);
IF @idFacultadF1 IS NULL OR @idUsuarioD1 IS NULL THROW 51707, 'TEST FAILED: faltan fixtures de facultad o decano.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    CREATE TABLE #crea (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
    DECLARE @idCx UNIQUEIDENTIFIER = NEWID();
    DECLARE @corrCx UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #crea EXEC dbo.usp_crear_coordinador @idCoordinador = @idCx, @numeroIdentificacion = 917000001,
        @primerNombre = N'Coord', @segundoNombre = N'Facultad', @primerApellido = N'QA', @segundoApellido = N'Esquema',
        @correo = N'coord.facultad.qa12x@test.local', @idPrograma = NULL, @idFacultad = @idFacultadF1,
        @password = N'HashBackend_QaCoord1234567890', @idCorrelacion = @corrCx, @idUsuarioEjecutor = @idUsuarioD1;
    IF NOT EXISTS (SELECT 1 FROM #crea WHERE estadoResultado = 1)
        THROW 51708, 'TEST FAILED T-120R-02: no se pudo crear el coordinador sin programa.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Coordinador WHERE id = @idCx AND facultad = @idFacultadF1 AND estado = 1)
        THROW 51709, 'TEST FAILED T-120R-02: usp_crear_coordinador no fijo Coordinador.facultad/estado.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.uv_coordinador WHERE id = @idCx AND idPrograma IS NULL AND idFacultad = @idFacultadF1)
        THROW 51710, 'TEST FAILED T-120R-02: uv_coordinador no expone la facultad del coordinador sin programa.', 1;
    DROP TABLE #crea;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE correo = N'coord.facultad.qa12x@test.local')
    THROW 51711, 'TEST FAILED: el esquema de coordinador dejo datos permanentes.', 1;
IF @@TRANCOUNT <> 0 THROW 51712, 'TEST FAILED: el esquema de coordinador dejo transacciones abiertas.', 1;
PRINT 'TEST_PASS:COORDINATOR_SCHEMA_COLUMNS';
PRINT 'TEST_PASS:COORDINATOR_VIEW_COLUMNS';
PRINT 'TEST_PASS:COORDINATOR_CREATE_SETS_FACULTY';
PRINT 'TEST END: test_hu121_hu122_esquema_coordinador';
GO
