USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU104/HU105/HU109/HU119/HU145 (T-104-01, T-105-01, T-119-01, T-145-01, T-PAG-01): el decano consulta el
-- directorio y la ficha de estudiantes, la estructura Facultad -> Programa -> Plan y el cronograma de sesiones
-- SOLO de su facultad. Un decano de otra facultad y un usuario sin ambito no ven nada.
PRINT 'TEST START: test_consultas_decano_facultad';

DECLARE @idEstudiante UNIQUEIDENTIFIER, @idFacultad UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER;
DECLARE @numeroIdentificacion INT;
SELECT TOP 1 @idEstudiante = e.id, @idFacultad = e.idFacultad, @idPrograma = e.idPrograma, @idGrupo = e.idGrupo,
             @numeroIdentificacion = e.numeroIdentificacion
FROM dbo.uv_estudiante e
WHERE EXISTS (SELECT 1 FROM dbo.uv_sesion s WHERE s.idGrupo = e.idGrupo)
ORDER BY e.nombreCompleto, e.id;
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @idFacultad);
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @fechaSesion DATE = (SELECT TOP 1 CAST(s.fechaHoraInicio AS DATE) FROM dbo.uv_sesion s WHERE s.idGrupo = @idGrupo ORDER BY s.fechaHoraInicio);
IF @idEstudiante IS NULL OR @idInstitucion IS NULL OR @tipoId IS NULL OR @fechaSesion IS NULL
    THROW 52950, 'TEST FAILED: faltan fixtures del seed (estudiante matriculado en un grupo con sesiones).', 1;

CREATE TABLE #estudiantes (
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion INT, nombreCompleto NVARCHAR(250),
    correo NVARCHAR(255), estaActivoUsuario BIT, programas NVARCHAR(MAX), totalGrupos INT, totalRegistros INT);
CREATE TABLE #detalle (
    idEstudiante UNIQUEIDENTIFIER, numeroIdentificacion INT, nombreCompleto NVARCHAR(250), idPrograma UNIQUEIDENTIFIER,
    nombrePrograma NVARCHAR(100), inpPlanEstudio INT, idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
    idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(100), estaActivoEstudiante BIT);
CREATE TABLE #estructura (
    clave NVARCHAR(120), idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(100), nombreCompletoDecano NVARCHAR(250), estaActivaFacultad BIT,
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), nombreCoordinador NVARCHAR(250), estaActivoPrograma BIT,
    nombreTipoPrograma NVARCHAR(100), nombreModalidad NVARCHAR(100), nombreJornada NVARCHAR(100),
    idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT, estaActivoPlanEstudio BIT, totalSemestres INT);
CREATE TABLE #sesiones (
    id UNIQUEIDENTIFIER, nombre NVARCHAR(100), codigo NVARCHAR(50), numeroSemana INT, fechaHoraInicio DATETIME2,
    fechaHoraFin DATETIME2, idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(100),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idPrograma UNIQUEIDENTIFIER,
    nombrePrograma NVARCHAR(100), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    -- Decano titular: el de la facultad del estudiante (si el seed no lo tiene, se asigna uno dentro de la transaccion).
    DECLARE @uDecTitular UNIQUEIDENTIFIER = (SELECT d.usuario FROM dbo.Facultad f INNER JOIN dbo.Decano d ON d.id = f.decano WHERE f.id = @idFacultad);
    IF @uDecTitular IS NULL
    BEGIN
        DECLARE @decTitular UNIQUEIDENTIFIER = NEWID();
        SET @uDecTitular = NEWID();
        INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
        VALUES (@uDecTitular, @tipoId, 600000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Decano', N'Titular', N'X', CONCAT(CONVERT(NVARCHAR(36), @uDecTitular), N'@qa.test'), 1, 1, N'x');
        INSERT INTO dbo.Decano (id, usuario) VALUES (@decTitular, @uDecTitular);
        UPDATE dbo.Facultad SET decano = @decTitular WHERE id = @idFacultad;
    END

    -- Decano ajeno con una facultad propia sin programas, y un usuario sin ambito.
    DECLARE @uDecAjeno UNIQUEIDENTIFIER = NEWID(), @decAjeno UNIQUEIDENTIFIER = NEWID(), @uPlano UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uDecAjeno, @tipoId, 600000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Decano', N'Ajeno', N'X', CONCAT(CONVERT(NVARCHAR(36), @uDecAjeno), N'@qa.test'), 1, 1, N'x'),
           (@uPlano, @tipoId, 600000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Sin', N'Ambito', N'X', CONCAT(CONVERT(NVARCHAR(36), @uPlano), N'@qa.test'), 1, 1, N'x');
    INSERT INTO dbo.Decano (id, usuario) VALUES (@decAjeno, @uDecAjeno);
    DECLARE @fAjena UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (@fAjena, CONCAT(N'QA Facultad Ajena ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8)), @idInstitucion, @decAjeno, 1);

    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @doc NVARCHAR(20) = CONVERT(NVARCHAR(20), @numeroIdentificacion);

    PRINT '-> T-104-01: directorio de estudiantes de la facultad';
    INSERT INTO #estudiantes EXEC dbo.usp_consultar_estudiantes_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM #estudiantes)
        THROW 52951, 'TEST FAILED T-104-01: el decano titular no vio estudiantes de su facultad.', 1;
    IF (SELECT COUNT(*) FROM #estudiantes) <> (SELECT COUNT(DISTINCT idEstudiante) FROM #estudiantes)
        THROW 52952, 'TEST FAILED T-104-01: el directorio repitio estudiantes.', 1;
    IF EXISTS (SELECT 1 FROM #estudiantes es WHERE NOT EXISTS (
            SELECT 1 FROM dbo.uv_estudiante e WHERE e.id = es.idEstudiante AND e.idFacultad = @idFacultad))
        THROW 52953, 'TEST FAILED T-104-01: aparecieron estudiantes de otra facultad.', 1;
    TRUNCATE TABLE #estudiantes;
    INSERT INTO #estudiantes EXEC dbo.usp_consultar_estudiantes_facultad_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    INSERT INTO #estudiantes EXEC dbo.usp_consultar_estudiantes_facultad_paginado
        @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #estudiantes)
        THROW 52954, 'TEST FAILED T-104-01: un decano ajeno o un usuario sin ambito vio estudiantes.', 1;
    PRINT 'TEST_PASS:T-104-01';

    PRINT '-> T-105-01: busqueda por documento y ficha del estudiante';
    INSERT INTO #estudiantes EXEC dbo.usp_consultar_estudiantes_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @doc;
    IF NOT EXISTS (SELECT 1 FROM #estudiantes WHERE idEstudiante = @idEstudiante)
        THROW 52955, 'TEST FAILED T-105-01: la busqueda por documento no encontro al estudiante.', 1;
    TRUNCATE TABLE #estudiantes;
    INSERT INTO #detalle EXEC dbo.usp_consultar_estudiante_facultad_detalle
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    IF NOT EXISTS (SELECT 1 FROM #detalle WHERE idGrupo = @idGrupo AND idPrograma = @idPrograma)
        THROW 52956, 'TEST FAILED T-105-01: la ficha no incluyo la matricula del estudiante.', 1;
    TRUNCATE TABLE #detalle;
    INSERT INTO #detalle EXEC dbo.usp_consultar_estudiante_facultad_detalle
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    IF EXISTS (SELECT 1 FROM #detalle)
        THROW 52957, 'TEST FAILED T-105-01: un decano ajeno vio la ficha del estudiante.', 1;
    PRINT 'TEST_PASS:T-105-01';

    PRINT '-> T-119-01: estructura Facultad -> Programa -> Plan';
    INSERT INTO #estructura EXEC dbo.usp_consultar_estructura_facultad @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c;
    IF NOT EXISTS (SELECT 1 FROM #estructura WHERE idFacultad = @idFacultad AND idPrograma = @idPrograma AND idPlanEstudio IS NOT NULL)
        THROW 52958, 'TEST FAILED T-119-01: la estructura no incluyo el programa y su plan.', 1;
    IF EXISTS (SELECT 1 FROM #estructura WHERE idFacultad <> @idFacultad)
        THROW 52959, 'TEST FAILED T-119-01: aparecieron facultades ajenas.', 1;
    TRUNCATE TABLE #estructura;
    INSERT INTO #estructura EXEC dbo.usp_consultar_estructura_facultad @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #estructura) <> 1 OR EXISTS (SELECT 1 FROM #estructura WHERE idFacultad <> @fAjena OR idPrograma IS NOT NULL)
        THROW 52960, 'TEST FAILED T-119-01: el decano ajeno debia ver solo su facultad, sin programas.', 1;
    TRUNCATE TABLE #estructura;
    INSERT INTO #estructura EXEC dbo.usp_consultar_estructura_facultad @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c;
    IF EXISTS (SELECT 1 FROM #estructura)
        THROW 52961, 'TEST FAILED T-119-01: un usuario sin ambito vio la estructura.', 1;
    PRINT 'TEST_PASS:T-119-01';

    PRINT '-> T-145-01: cronograma de sesiones de la facultad';
    INSERT INTO #sesiones EXEC dbo.usp_consultar_sesiones_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100,
        @fechaDesde = @fechaSesion, @fechaHasta = @fechaSesion, @idPrograma = @idPrograma;
    IF NOT EXISTS (SELECT 1 FROM #sesiones WHERE idGrupo = @idGrupo)
        THROW 52962, 'TEST FAILED T-145-01: el cronograma no incluyo la sesion del dia.', 1;
    IF EXISTS (SELECT 1 FROM #sesiones WHERE CAST(fechaHoraInicio AS DATE) <> @fechaSesion OR idPrograma <> @idPrograma)
        THROW 52963, 'TEST FAILED T-145-01: el filtro de fecha o programa no se aplico.', 1;
    TRUNCATE TABLE #sesiones;
    INSERT INTO #sesiones EXEC dbo.usp_consultar_sesiones_facultad_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #sesiones)
        THROW 52964, 'TEST FAILED T-145-01: un decano ajeno vio sesiones.', 1;
    PRINT 'TEST_PASS:T-145-01';


    IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
        THROW 52967, 'TEST FAILED: los SP del decano no restauraron el SESSION_CONTEXT previo.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #estudiantes, #detalle, #estructura, #sesiones;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #estudiantes, #detalle, #estructura, #sesiones;

-- Paginacion fuera de la transaccion: la validacion ocurre antes del ambito, con cualquier ejecutor.
DECLARE @cPag UNIQUEIDENTIFIER = NEWID();
PRINT '-> T-PAG-01: paginacion invalida se rechaza con PAG_001';
DECLARE @rechazado BIT = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_estudiantes_facultad_paginado
        @idUsuarioEjecutor = @idEstudiante, @idCorrelacion = @cPag, @numeroPagina = 0, @tamanoPagina = 10;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazado = 1;
END CATCH;
IF @rechazado = 0
    THROW 52965, 'TEST FAILED T-PAG-01: la pagina 0 no fue rechazada con PAG_001.', 1;
SET @rechazado = 0;
BEGIN TRY
    EXEC dbo.usp_consultar_sesiones_facultad_paginado
        @idUsuarioEjecutor = @idEstudiante, @idCorrelacion = @cPag, @numeroPagina = 1, @tamanoPagina = 0;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazado = 1;
END CATCH;
IF @rechazado = 0
    THROW 52966, 'TEST FAILED T-PAG-01: el tamano 0 no fue rechazado con PAG_001.', 1;
PRINT 'TEST_PASS:T-PAG-01';
PRINT 'TEST_PASS:TEST_CONSULTAS_DECANO_FACULTAD';
GO
