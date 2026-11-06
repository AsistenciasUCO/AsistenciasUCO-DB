USE [gestionasistenciadb];
GO

SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- HU112/HU128/HU143/HU157 (T-112-01, T-128-01, T-143-01, T-157-01, T-157-02, T-PAG-02): tabla unificada de
-- programas y creditos y directorio de docentes de la facultad del decano; busqueda transversal de asignaturas en
-- la institucion; buscador de estudiantes del administrador y ficha unificada con historial (ADMINISTRADOR y DECANO).
PRINT 'TEST START: test_consultas_transversales_hu112_hu157';

DECLARE @idEstudiante UNIQUEIDENTIFIER, @idFacultad UNIQUEIDENTIFIER, @idPrograma UNIQUEIDENTIFIER, @idGrupo UNIQUEIDENTIFIER;
DECLARE @idPlanEstudio UNIQUEIDENTIFIER, @idAsignatura UNIQUEIDENTIFIER, @numeroIdentificacion INT;
SELECT TOP 1 @idEstudiante = e.id, @idFacultad = e.idFacultad, @idPrograma = e.idPrograma, @idGrupo = e.idGrupo,
             @idPlanEstudio = e.idPlanEstudio, @idAsignatura = e.idAsignatura, @numeroIdentificacion = e.numeroIdentificacion
FROM dbo.uv_estudiante e
WHERE e.idGrupo IS NOT NULL
ORDER BY e.nombreCompleto, e.id;
DECLARE @idInstitucion UNIQUEIDENTIFIER = (SELECT institucion FROM dbo.Facultad WHERE id = @idFacultad);
DECLARE @tipoId UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion);
DECLARE @codigoAsignatura NVARCHAR(50) = (SELECT codigo FROM dbo.Asignatura WHERE id = @idAsignatura);
DECLARE @idDocente UNIQUEIDENTIFIER, @idProgramaDocente UNIQUEIDENTIFIER;
SELECT TOP 1 @idDocente = dp.idDocente, @idProgramaDocente = dp.idPrograma
FROM dbo.uv_docente_programa dp
WHERE dp.idFacultad = @idFacultad AND dp.estaActivoVinculacion = 1
ORDER BY dp.nombreCompleto, dp.idDocente;
DECLARE @uAdmin UNIQUEIDENTIFIER = (SELECT TOP 1 a.usuario FROM dbo.Administrador a WHERE a.institucion = @idInstitucion ORDER BY a.id);
IF @idEstudiante IS NULL OR @idInstitucion IS NULL OR @tipoId IS NULL OR @codigoAsignatura IS NULL OR @idDocente IS NULL OR @uAdmin IS NULL
    THROW 56110, 'TEST FAILED: faltan fixtures del seed (estudiante en grupo, docente vinculado en su facultad y administrador).', 1;

CREATE TABLE #programas (
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), nombreTipoPrograma NVARCHAR(100), nombreModalidad NVARCHAR(100),
    nombreJornada NVARCHAR(100), estaActivoPrograma BIT, idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT,
    estaActivoPlanEstudio BIT, totalSemestres INT, totalAsignaturas INT, totalCreditos INT, totalRegistros INT);
CREATE TABLE #docentes (
    idDocente UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion BIGINT, nombreCompleto NVARCHAR(250),
    correo NVARCHAR(255), estaActivoUsuario BIT, programas NVARCHAR(MAX), totalProgramas INT, totalGrupos INT, totalRegistros INT,
    tieneVinculoActivo BIT);
CREATE TABLE #asignaturas (
    idAsignatura UNIQUEIDENTIFIER, codigo NVARCHAR(50), nombre NVARCHAR(50), credito INT, nombreArea NVARCHAR(100),
    nombreComponente NVARCHAR(100), codigoSemestre NVARCHAR(50), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio INT,
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(100),
    estaActivaAsignatura BIT, totalRegistros INT);
CREATE TABLE #estudiantes (
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, numeroIdentificacion BIGINT, nombreCompleto NVARCHAR(250),
    correo NVARCHAR(255), estaActivoUsuario BIT, facultades NVARCHAR(MAX), programas NVARCHAR(MAX), totalGrupos INT, totalRegistros INT);
CREATE TABLE #historial (
    idEstudiante UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, tipoIdentificacion NVARCHAR(50), numeroIdentificacion BIGINT,
    nombreCompleto NVARCHAR(250), correo NVARCHAR(255), estaActivoUsuario BIT, idFacultad UNIQUEIDENTIFIER, nombreFacultad NVARCHAR(100),
    idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), inpPlanEstudio INT, idPeriodoAcademico UNIQUEIDENTIFIER,
    codigoPeriodoAcademico NVARCHAR(50), nombrePeriodoAcademico NVARCHAR(100), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), codigoEstadoEstudiante NVARCHAR(50), nombreEstadoEstudiante NVARCHAR(100),
    sesionesEjecutadas INT, asistencias INT, faltasSinJustaCausa INT, excusas INT, porcentajeInasistencia DECIMAL(5,2),
    codigoPermanencia NVARCHAR(50));

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

    -- Decano ajeno con una facultad propia sin programas en la MISMA institucion, y un usuario sin ambito.
    DECLARE @uDecAjeno UNIQUEIDENTIFIER = NEWID(), @decAjeno UNIQUEIDENTIFIER = NEWID(), @uPlano UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uDecAjeno, @tipoId, 600000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Decano', N'Ajeno', N'X', CONCAT(CONVERT(NVARCHAR(36), @uDecAjeno), N'@qa.test'), 1, 1, N'x'),
           (@uPlano, @tipoId, 600000000 + ABS(CHECKSUM(NEWID()) % 99999999), N'QA', N'Sin', N'Ambito', N'X', CONCAT(CONVERT(NVARCHAR(36), @uPlano), N'@qa.test'), 1, 1, N'x');
    INSERT INTO dbo.Decano (id, usuario) VALUES (@decAjeno, @uDecAjeno);
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado)
    VALUES (NEWID(), CONCAT(N'QA Facultad Ajena ', SUBSTRING(CONVERT(NVARCHAR(36), NEWID()), 1, 8)), @idInstitucion, @decAjeno, 1);

    DECLARE @c UNIQUEIDENTIFIER = NEWID();
    DECLARE @doc NVARCHAR(20) = CONVERT(NVARCHAR(20), @numeroIdentificacion);

    PRINT '-> T-112-01: tabla unificada de programas y creditos de la facultad';
    INSERT INTO #programas EXEC dbo.usp_consultar_programas_creditos_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (
            SELECT 1 FROM #programas p
            WHERE p.idPrograma = @idPrograma AND p.idPlanEstudio = @idPlanEstudio
              AND p.totalCreditos = (SELECT SUM(a.credito) FROM dbo.Asignatura a INNER JOIN dbo.SemestrePlanEstudio s ON s.id = a.semestrePlanEstudio WHERE s.planEstudio = @idPlanEstudio)
              AND p.totalAsignaturas = (SELECT COUNT(*) FROM dbo.Asignatura a INNER JOIN dbo.SemestrePlanEstudio s ON s.id = a.semestrePlanEstudio WHERE s.planEstudio = @idPlanEstudio))
        THROW 56111, 'TEST FAILED T-112-01: el plan del programa no trajo la suma real de creditos y asignaturas.', 1;
    IF EXISTS (SELECT 1 FROM #programas p WHERE NOT EXISTS (SELECT 1 FROM dbo.Programa pr WHERE pr.id = p.idPrograma AND pr.facultad = @idFacultad))
        THROW 56112, 'TEST FAILED T-112-01: aparecieron programas de otra facultad.', 1;
    -- Certificacion F3: totalSemestres es el mayor numero de semestre del plan (misma regla que el coordinador).
    IF EXISTS (
        SELECT 1 FROM #programas p
        WHERE p.idPlanEstudio IS NOT NULL
          AND p.totalSemestres <> ISNULL((SELECT MAX(spe.numeroSemestre) FROM dbo.uv_semestre_plan_estudio spe
                                          WHERE spe.idPlanEstudio = p.idPlanEstudio), 0))
        THROW 56178, 'TEST FAILED T-112-01: totalSemestres no es el mayor numero de semestre del plan.', 1;
    TRUNCATE TABLE #programas;
    INSERT INTO #programas EXEC dbo.usp_consultar_programas_creditos_facultad_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #programas)
        THROW 56113, 'TEST FAILED T-112-01: un decano ajeno vio programas de otra facultad.', 1;
    PRINT 'TEST_PASS:T-112-01';

    PRINT '-> T-128-01: docentes de la facultad filtrados por programa';
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @idPrograma = @idProgramaDocente;
    IF NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @idDocente)
        THROW 56114, 'TEST FAILED T-128-01: el filtro por programa no trajo al docente vinculado.', 1;
    IF EXISTS (SELECT 1 FROM #docentes d WHERE NOT EXISTS (
            SELECT 1 FROM dbo.DocentePrograma dp WHERE dp.docente = d.idDocente AND dp.programa = @idProgramaDocente AND dp.estado = 1))
        THROW 56115, 'TEST FAILED T-128-01: aparecieron docentes sin vinculo activo en el programa filtrado.', 1;
    IF (SELECT COUNT(*) FROM #docentes) <> (SELECT COUNT(DISTINCT idDocente) FROM #docentes)
        THROW 56116, 'TEST FAILED T-128-01: el directorio repitio docentes.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #docentes)
        THROW 56117, 'TEST FAILED T-128-01: un decano ajeno vio docentes de otra facultad.', 1;
    PRINT 'TEST_PASS:T-128-01';

    PRINT '-> T-136-01: el administrador ve los docentes de su institucion y filtra por facultad';
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @idDocente)
        THROW 56170, 'TEST FAILED T-136-01: el administrador no vio al docente vinculado en su institucion.', 1;
    IF EXISTS (SELECT 1 FROM #docentes d WHERE NOT EXISTS (
            SELECT 1 FROM dbo.uv_docente_programa v WHERE v.idDocente = d.idDocente AND v.idInstitucion = @idInstitucion))
        THROW 56171, 'TEST FAILED T-136-01: el administrador vio docentes de otra institucion.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @idFacultad = @idFacultad;
    IF NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @idDocente)
       OR EXISTS (SELECT 1 FROM #docentes d WHERE NOT EXISTS (
            SELECT 1 FROM dbo.uv_docente_programa v WHERE v.idDocente = d.idDocente AND v.idFacultad = @idFacultad AND v.estaActivoVinculacion = 1))
        THROW 56172, 'TEST FAILED T-136-01: el filtro por facultad del administrador no funciono.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @idFacultad = @idFacultad;
    IF EXISTS (SELECT 1 FROM #docentes)
        THROW 56173, 'TEST FAILED T-136-01: un decano ajeno vio docentes filtrando por otra facultad.', 1;
    -- Ajuste HU136: docentes sin vinculo activo (retirados de todos sus programas) solo para el administrador
    DECLARE @dSinVinculo UNIQUEIDENTIFIER = NEWID(), @uSinVinculo UNIQUEIDENTIFIER = NEWID();
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    VALUES (@uSinVinculo, @tipoId, 913600001, N'Retirado', N'Qa', N'Docente', N'', N'retirado.hu136@test.local', 1, 1, N'HashBackend_Hu136');
    INSERT INTO dbo.Docente (id, usuario) VALUES (@dSinVinculo, @uSinVinculo);
    INSERT INTO dbo.DocentePrograma (id, docente, programa, tipoVinculacion, estado, fechaVinculacionUtc)
    VALUES (NEWID(), @dSinVinculo, @idProgramaDocente, (SELECT TOP 1 id FROM dbo.TipoVinculacion ORDER BY codigo), 0, SYSUTCDATETIME());
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @dSinVinculo) OR EXISTS (SELECT 1 FROM #docentes WHERE tieneVinculoActivo = 0)
        THROW 56174, 'TEST FAILED T-136-02: por defecto el administrador vio docentes sin vinculo activo.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @estadoVinculo = 'SIN_VINCULO';
    IF NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @dSinVinculo AND tieneVinculoActivo = 0 AND programas IS NULL AND totalProgramas = 0 AND totalGrupos = 0)
       OR EXISTS (SELECT 1 FROM #docentes WHERE tieneVinculoActivo = 1)
        THROW 56175, 'TEST FAILED T-136-02: SIN_VINCULO no trajo al docente retirado con programa vacio o trajo vinculados.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @estadoVinculo = 'TODOS';
    IF NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @dSinVinculo) OR NOT EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @idDocente)
        THROW 56176, 'TEST FAILED T-136-02: TODOS no trajo a vinculados y sin vinculo.', 1;
    TRUNCATE TABLE #docentes;
    INSERT INTO #docentes EXEC dbo.usp_consultar_docentes_facultad_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @estadoVinculo = 'TODOS';
    IF EXISTS (SELECT 1 FROM #docentes WHERE idDocente = @dSinVinculo OR tieneVinculoActivo = 0)
        THROW 56177, 'TEST FAILED T-136-02: el decano vio docentes sin vinculo activo (HU128 no cambia).', 1;
    PRINT 'TEST_PASS:HU136_ADMIN_TEACHERS_INSTITUTION';

    PRINT '-> T-143-01: busqueda de asignaturas (administrador: institucion; decano: su facultad)';
    INSERT INTO #asignaturas EXEC dbo.usp_buscar_asignaturas_paginado
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @codigoAsignatura;
    IF NOT EXISTS (SELECT 1 FROM #asignaturas WHERE idAsignatura = @idAsignatura)
       OR EXISTS (SELECT 1 FROM #asignaturas WHERE idFacultad <> @idFacultad)
        THROW 56118, 'TEST FAILED T-143-01: el decano titular no encontro la asignatura por codigo o vio otra facultad.', 1;
    TRUNCATE TABLE #asignaturas;
    INSERT INTO #asignaturas EXEC dbo.usp_buscar_asignaturas_paginado
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #asignaturas)
        THROW 56130, 'TEST FAILED T-143-01: un decano vio asignaturas de una facultad que no es la suya.', 1;
    INSERT INTO #asignaturas EXEC dbo.usp_buscar_asignaturas_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @idFacultad = @idFacultad;
    IF NOT EXISTS (SELECT 1 FROM #asignaturas WHERE idAsignatura = @idAsignatura)
       OR EXISTS (SELECT 1 FROM #asignaturas WHERE idFacultad <> @idFacultad)
        THROW 56119, 'TEST FAILED T-143-01: el filtro por facultad del administrador no se aplico.', 1;
    PRINT 'TEST_PASS:T-143-01';

    PRINT '-> T-157-01: buscador de estudiantes del administrador';
    INSERT INTO #estudiantes EXEC dbo.usp_buscar_estudiantes_institucion_paginado
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 100, @busqueda = @doc;
    IF NOT EXISTS (SELECT 1 FROM #estudiantes WHERE idEstudiante = @idEstudiante)
        THROW 56121, 'TEST FAILED T-157-01: la busqueda por documento del administrador no encontro al estudiante.', 1;
    PRINT 'TEST_PASS:T-157-01';

    PRINT '-> T-157-02: ficha unificada con historial (administrador y decano)';
    INSERT INTO #historial EXEC dbo.usp_consultar_historial_estudiante
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    IF NOT EXISTS (SELECT 1 FROM #historial WHERE idGrupo = @idGrupo AND idPrograma = @idPrograma AND numeroIdentificacion = @numeroIdentificacion)
        THROW 56123, 'TEST FAILED T-157-02: el historial del administrador no incluyo la matricula del estudiante.', 1;
    TRUNCATE TABLE #historial;
    INSERT INTO #historial EXEC dbo.usp_consultar_historial_estudiante
        @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    IF NOT EXISTS (SELECT 1 FROM #historial WHERE idGrupo = @idGrupo)
       OR EXISTS (SELECT 1 FROM #historial WHERE idFacultad <> @idFacultad)
        THROW 56124, 'TEST FAILED T-157-02: el historial del decano no se limito a su facultad.', 1;
    TRUNCATE TABLE #historial;
    INSERT INTO #historial EXEC dbo.usp_consultar_historial_estudiante
        @idUsuarioEjecutor = @uDecAjeno, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    IF EXISTS (SELECT 1 FROM #historial)
        THROW 56125, 'TEST FAILED T-157-02: un decano ajeno vio el historial del estudiante.', 1;
    DECLARE @rechazadoSec BIT = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_historial_estudiante @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @idEstudiante = @idEstudiante;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazadoSec = 1;
    END CATCH;
    IF @rechazadoSec = 0
        THROW 56126, 'TEST FAILED T-157-02: un usuario sin perfil ADMINISTRADOR/DECANO no fue rechazado con SEC_001.', 1;
    PRINT 'TEST_PASS:T-157-02';

    PRINT '-> T-SEC-03: los SP rechazan con SEC_001 al usuario sin el perfil exigido';
    DECLARE @rechazos INT = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_programas_creditos_facultad_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_docentes_facultad_paginado @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_buscar_asignaturas_paginado @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=SEC_001|%' SET @rechazos += 1;
    END CATCH;
    IF @rechazos <> 4
        THROW 56131, 'TEST FAILED T-SEC-03: algun SP no rechazo con SEC_001 al usuario sin el perfil exigido.', 1;
    PRINT 'TEST_PASS:T-SEC-03';

    PRINT '-> T-PAG-02: paginacion invalida (PAG_001) y parametros obligatorios ausentes (VAL_001)';
    SET @rechazos = 0;
    BEGIN TRY
        EXEC dbo.usp_consultar_programas_creditos_facultad_paginado @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 0, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_docentes_facultad_paginado @idUsuarioEjecutor = @uDecTitular, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 0;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_buscar_asignaturas_paginado @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @numeroPagina = NULL, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=PAG_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_buscar_estudiantes_institucion_paginado @idUsuarioEjecutor = NULL, @idCorrelacion = @c, @numeroPagina = 1, @tamanoPagina = 10;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=VAL_001|%' SET @rechazos += 1;
    END CATCH;
    BEGIN TRY
        EXEC dbo.usp_consultar_historial_estudiante @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @idEstudiante = NULL;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%DBCODE=VAL_001|%' SET @rechazos += 1;
    END CATCH;
    IF @rechazos <> 5
        THROW 56128, 'TEST FAILED T-PAG-02: alguna validacion de paginacion o de parametros obligatorios no se rechazo con su codigo.', 1;
    PRINT 'TEST_PASS:T-PAG-02';

    PRINT '-> T-INT-01: usp_validar_consulta_paginada_interno (exito, VAL_001, SEC_001 y PAG_001 con el triplete)';
    DECLARE @idUsuarioValidado UNIQUEIDENTIFIER, @offset INT, @mu NVARCHAR(4000), @mt NVARCHAR(4000), @estado BIT;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @codigoPerfilRequerido = 'ADMINISTRADOR', @numeroPagina = 3, @tamanoPagina = 20,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 1 OR @offset <> 40 OR @idUsuarioValidado <> @uAdmin OR CONVERT(UNIQUEIDENTIFIER, SESSION_CONTEXT(N'idUsuarioEjecutor')) <> @uAdmin
        THROW 56132, 'TEST FAILED T-INT-01: el camino exitoso no devolvio el desplazamiento ni fijo el contexto del ejecutor.', 1;
    EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = NULL, @read_only = 0;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = NULL, @idCorrelacion = @c, @codigoPerfilRequerido = 'ADMINISTRADOR', @numeroPagina = 1, @tamanoPagina = 10,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 0 OR @mt NOT LIKE 'DBCODE=VAL_001|%Correlacion:%' OR @offset IS NOT NULL
        THROW 56133, 'TEST FAILED T-INT-01: el ejecutor nulo no se rechazo con VAL_001 y la correlacion.', 1;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @uPlano, @idCorrelacion = @c, @codigoPerfilRequerido = 'ADMINISTRADOR', @numeroPagina = 1, @tamanoPagina = 10,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 0 OR @mt NOT LIKE 'DBCODE=SEC_001|%'
        THROW 56134, 'TEST FAILED T-INT-01: el usuario sin perfil no se rechazo con SEC_001.', 1;
    EXEC dbo.usp_validar_consulta_paginada_interno
        @idUsuarioEjecutor = @uAdmin, @idCorrelacion = @c, @codigoPerfilRequerido = 'ADMINISTRADOR', @numeroPagina = 1, @tamanoPagina = 100000,
        @idUsuarioValidado = @idUsuarioValidado OUTPUT, @offset = @offset OUTPUT,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @estado OUTPUT;
    IF @estado <> 0 OR @mt NOT LIKE 'DBCODE=PAG_001|%Correlacion:%' OR SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
        THROW 56135, 'TEST FAILED T-INT-01: el tamano mayor al maximo no se rechazo con PAG_001 o fijo el contexto.', 1;
    PRINT 'TEST_PASS:T-INT-01';

    IF SESSION_CONTEXT(N'idUsuarioEjecutor') IS NOT NULL
        THROW 56127, 'TEST FAILED: las consultas transversales no restauraron el SESSION_CONTEXT previo.', 1;
    IF XACT_STATE() <> 1
        THROW 56129, 'TEST FAILED: un rechazo de validacion condeno la transaccion del llamador.', 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #programas, #docentes, #asignaturas, #estudiantes, #historial;
    THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DROP TABLE IF EXISTS #programas, #docentes, #asignaturas, #estudiantes, #historial;
PRINT 'TEST_PASS:TEST_CONSULTAS_TRANSVERSALES_HU112_HU157';
GO
