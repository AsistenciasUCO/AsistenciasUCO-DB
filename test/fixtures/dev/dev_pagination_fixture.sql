USE [gestionasistenciadb];
GO
/*
  MAINT-003K - fixtures sinteticos de desarrollo para paginacion, filtros y asistencia.

  NO es un seed de despliegue: lo ejecuta deploy_dev_fixtures.ps1 (limpieza -> carga -> validacion) solo contra un contenedor
  SQL Server Developer de desarrollo. Todo es sintetico y reproducible:
    * ids deterministas con prefijo reservado 'DE0000' (el limpiador solo toca ese prefijo);
    * correos @fixture.invalid y password inutilizable (no son cuentas de Keycloak ni de login real);
    * escenarios 300 / 1000 / 5000 estudiantes: un grupo por escenario con su propio docente fixture (alcance DOCENTE exacto);
    * los estudiantes 1..300 estan matriculados en los tres grupos y 1..1000 en dos => duplicados multi-grupo en uv_estudiante;
    * pares de estudiantes con el MISMO nombre completo (i multiplo de 25) para probar desempate estable por id;
    * estados academicos: A (activo), I, CVP, CI, F; ~1% de usuarios inactivos (estado = 0);
    * sesiones: 4 por grupo, instantes UTC exactos DATETIME2(7) con procedenciaTemporal = 'UTC_V2'
      (la sesion 1 lleva fracciones de 100 ns: .1234567 / .7654321);
    * asistencia: grupo 300 -> sesiones 1..3; grupos 1000 y 5000 -> sesion 1 (solo matriculas en estado A).
  Variable sqlcmd: $(Scenarios) = lista de tamanos, p. ej. 300,1000,5000 (cualquier subconjunto de esos tres).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) NOT LIKE 'Developer%'
    THROW 55011, 'BLOCKED - dev fixtures only run on SQL Server Developer Edition.', 1;
IF DB_NAME() <> N'gestionasistenciadb'
    THROW 55012, 'BLOCKED - unexpected database for dev fixtures.', 1;
IF EXISTS (SELECT 1 FROM dbo.CatalogoParametro WHERE grupo = N'OPERACION' AND clave = N'AMBIENTE' AND UPPER(valor) IN (N'PRODUCCION', N'PROD', N'PRODUCTION'))
    THROW 55013, 'BLOCKED - OPERACION/AMBIENTE declares a production database.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000')
    THROW 55014, 'ABORT - fixture rows already exist; run dev_pagination_cleanup.sql first (deploy_dev_fixtures.ps1 does it).', 1;

DECLARE @scenarios NVARCHAR(100) = N'$(Scenarios)';

CREATE TABLE #esc (code TINYINT NOT NULL PRIMARY KEY, size INT NOT NULL);
INSERT INTO #esc (code, size)
SELECT v.code, v.size
FROM (VALUES (1, 300), (2, 1000), (3, 5000)) v(code, size)
WHERE v.size IN (SELECT TRY_CAST(TRIM(value) AS INT) FROM STRING_SPLIT(@scenarios, N','));
IF NOT EXISTS (SELECT 1 FROM #esc)
    THROW 55015, 'ABORT - Scenarios must contain at least one of 300, 1000, 5000.', 1;
DECLARE @maxN INT = (SELECT MAX(size) FROM #esc);

DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @baseGrupo UNIQUEIDENTIFIER = 'A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D';
DECLARE @asignatura UNIQUEIDENTIFIER, @periodo UNIQUEIDENTIFIER;
SELECT @asignatura = asignatura, @periodo = periodoAcademico FROM dbo.Grupo WHERE id = @baseGrupo;
DECLARE @programa UNIQUEIDENTIFIER = (SELECT TOP (1) id FROM dbo.Programa ORDER BY id);
IF @tipoCC IS NULL OR @asignatura IS NULL OR @periodo IS NULL OR @programa IS NULL
    THROW 55016, 'ABORT - base seed (tipo CC, grupo 14_grupos_sesiones, programa) is missing; deploy the schema first.', 1;

DECLARE @rAN UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'AN');
DECLARE @rSJC UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC');
DECLARE @rEX UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'EX');
IF @rAN IS NULL OR @rSJC IS NULL OR @rEX IS NULL THROW 55017, 'ABORT - RazonCausa AN/SJC/EX missing.', 1;

-- Nombres sinteticos (tokens ASCII -> caracteres Unicode, independiente de la codificacion del archivo).
CREATE TABLE #nom (k INT NOT NULL PRIMARY KEY, nombre NVARCHAR(40) NOT NULL);
INSERT INTO #nom (k, nombre) SELECT ROW_NUMBER() OVER (ORDER BY n) - 1, n FROM (VALUES
 (N'Juan'),(N'Mar{i}a'),(N'Andr{e}s'),(N'Valentina'),(N'Camilo'),(N'Daniela'),(N'Santiago'),(N'Sof{i}a'),(N'Sebasti{a}n'),(N'Laura'),
 (N'Mateo'),(N'Isabella'),(N'Nicol{a}s'),(N'Camila'),(N'Felipe'),(N'Mariana'),(N'Daniel'),(N'Luisa'),(N'Juli{a}n'),(N'Pamela'),
 (N'Alejandro'),(N'Natalia'),(N'David'),(N'Carolina'),(N'Esteban'),(N'Juliana'),(N'Cristian'),(N'Manuela'),(N'Samuel'),(N'{A}ngela')) t(n);
CREATE TABLE #ape (k INT NOT NULL PRIMARY KEY, apellido NVARCHAR(40) NOT NULL);
INSERT INTO #ape (k, apellido) SELECT ROW_NUMBER() OVER (ORDER BY n) - 1, n FROM (VALUES
 (N'G{o}mez'),(N'Rodr{i}guez'),(N'Mart{i}nez'),(N'L{o}pez'),(N'Garc{i}a'),(N'Hern{a}ndez'),(N'P{e}rez'),(N'S{a}nchez'),(N'Ram{i}rez'),(N'Torres'),
 (N'Fl{o}rez'),(N'D{i}az'),(N'Vargas'),(N'Castro'),(N'Rojas'),(N'Ortiz'),(N'Moreno'),(N'Jim{e}nez'),(N'Mu{n}oz'),(N'{A}lvarez'),
 (N'Romero'),(N'Su{a}rez'),(N'Guti{e}rrez'),(N'R{i}os'),(N'Zapata'),(N'Restrepo'),(N'Cardona'),(N'Ospina'),(N'Giraldo'),(N'Montoya'),
 (N'Arango'),(N'Henao'),(N'Valencia'),(N'Mej{i}a'),(N'{U}suga'),(N'Echeverri'),(N'Bedoya'),(N'Pineda'),(N'Agudelo'),(N'{N}{a}{n}ez')) t(n);
UPDATE #nom SET nombre = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(nombre, N'{a}', NCHAR(225)), N'{e}', NCHAR(233)), N'{i}', NCHAR(237)), N'{o}', NCHAR(243)), N'{u}', NCHAR(250)), N'{n}', NCHAR(241)), N'{A}', NCHAR(193));
UPDATE #ape SET apellido = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(apellido, N'{a}', NCHAR(225)), N'{e}', NCHAR(233)), N'{i}', NCHAR(237)), N'{o}', NCHAR(243)), N'{u}', NCHAR(250)), N'{n}', NCHAR(241)), N'{A}', NCHAR(193)), N'{U}', NCHAR(218)), N'{N}', NCHAR(209));

CREATE TABLE #est (i INT NOT NULL PRIMARY KEY, nameKey INT NOT NULL);
INSERT INTO #est (i, nameKey)
SELECT s.value, CASE WHEN s.value % 25 = 0 THEN s.value - 1 ELSE s.value END   -- i multiplo de 25 comparte nombre con i-1
FROM GENERATE_SERIES(1, @maxN) s;

-- Helpers GUID: DE0000<tt>-0000-4000-8000-<12 hex>
DECLARE @pfx CHAR(8);

BEGIN TRANSACTION;

-- 1) Usuarios y estudiantes (1..maxN)
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
SELECT
    CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000001-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), e.i), 2)), 12))),
    @tipoCC,
    880000000 + e.i,
    ap1.apellido, ap2.apellido,
    n1.nombre,
    CASE WHEN e.nameKey % 3 = 0 THEN n2.nombre ELSE N'' END,
    CONCAT(N'dev.est.', RIGHT(CONCAT(N'00000', e.i), 5), N'@fixture.invalid'),
    1,
    CASE WHEN e.i % 97 = 0 THEN 0 ELSE 1 END,
    N'FIXTURE_DISABLED_ACCOUNT'
FROM #est e
JOIN #nom n1 ON n1.k = e.nameKey % 30
JOIN #nom n2 ON n2.k = (e.nameKey / 3) % 30
JOIN #ape ap1 ON ap1.k = (e.nameKey * 7 + e.nameKey / 40) % 40
JOIN #ape ap2 ON ap2.k = (e.nameKey * 11 + 3) % 40;

INSERT INTO dbo.Estudiante (id, usuario)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000002-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), e.i), 2)), 12))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000001-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), e.i), 2)), 12)))
FROM #est e;

INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE00000A-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), e.i), 2)), 12))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000002-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), e.i), 2)), 12))),
       @programa
FROM #est e;

-- 2) Docente fixture por escenario
INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000003-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12))),
       @tipoCC, 870000000 + c.code, N'Docente', N'Fixture', CONCAT(N'Paginacion', c.size), N'',
       CONCAT(N'dev.docente.', c.size, N'@fixture.invalid'), 1, 1, N'FIXTURE_DISABLED_ACCOUNT'
FROM #esc c;

INSERT INTO dbo.Docente (id, usuario)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000004-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000003-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12)))
FROM #esc c;

-- 3) Grupo por escenario (contadores = distribucion real de estados)
INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron, cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000005-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12))),
       @asignatura, @periodo, 9000 + c.code, CONCAT(N'FIX-PAG-', c.size, N' Paginacion ', c.size, N' estudiantes'),
       c.size,
       (SELECT COUNT(*) FROM GENERATE_SERIES(1, c.size) s WHERE s.value % 50 = 2),
       (SELECT COUNT(*) FROM GENERATE_SERIES(1, c.size) s WHERE s.value % 50 = 1),
       (SELECT COUNT(*) FROM GENERATE_SERIES(1, c.size) s WHERE s.value % 50 = 0),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000004-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12)))
FROM #esc c;

-- 4) Matriculas con estados academicos (i%50: 0=CI, 1=CVP, 2=F, 3=I, resto=A)
INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000006-0000-4000-8000-', RIGHT(CONCAT('00', c.code), 2), '00', RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), s.value), 2)), 8))),
       (SELECT TOP (1) id FROM dbo.EstadoEstudianteGrupo WHERE codigo = CASE s.value % 50 WHEN 0 THEN 'CI' WHEN 1 THEN 'CVP' WHEN 2 THEN 'F' WHEN 3 THEN 'I' ELSE 'A' END),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000002-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), s.value), 2)), 12))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000005-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12)))
FROM #esc c
CROSS APPLY GENERATE_SERIES(1, c.size) s;

-- 5) Sesiones: 4 por grupo, instantes UTC confirmados DATETIME2(7) marcados UTC_V2
--    Base: 2026-09-14T13:00:00Z (08:00 America/Bogota) + 7 dias por sesion; duracion 2 h. La sesion 1 lleva fraccion de 100 ns.
INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin, procedenciaTemporal)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000007-0000-4000-8000-', RIGHT(CONCAT('00', c.code), 2), RIGHT(CONCAT('00', n.value), 2), '00000000')),
       CONCAT(N'Sesion FIX ', c.size, N' - ', RIGHT(CONCAT(N'00', n.value), 2)),
       n.value, CONCAT(N'FIX-S', RIGHT(CONCAT(N'00', n.value), 2)), n.value,
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000005-0000-4000-8000-', RIGHT(CONCAT('000000000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), c.code), 2)), 12))),
       DATEADD(NANOSECOND, CASE WHEN n.value = 1 THEN 123456700 ELSE 0 END, DATEADD(DAY, (n.value - 1) * 7, CAST('2026-09-14T13:00:00.0000000' AS DATETIME2(7)))),
       DATEADD(NANOSECOND, CASE WHEN n.value = 1 THEN 765432100 ELSE 0 END, DATEADD(HOUR, 2, DATEADD(DAY, (n.value - 1) * 7, CAST('2026-09-14T13:00:00.0000000' AS DATETIME2(7))))),
       N'UTC_V2'
FROM #esc c
CROSS APPLY GENERATE_SERIES(1, 4) n;

-- 6) Asistencia (solo matriculas en estado A): grupo 300 -> sesiones 1..3; otros -> sesion 1
INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000008-0000-4000-8000-', RIGHT(CONCAT('00', c.code), 2), RIGHT(CONCAT('00', n.value), 2), RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), s.value), 2)), 8))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000006-0000-4000-8000-', RIGHT(CONCAT('00', c.code), 2), '00', RIGHT(CONCAT('00000000', CONVERT(VARCHAR(8), CONVERT(VARBINARY(4), s.value), 2)), 8))),
       CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000007-0000-4000-8000-', RIGHT(CONCAT('00', c.code), 2), RIGHT(CONCAT('00', n.value), 2), '00000000'))
FROM #esc c
CROSS APPLY GENERATE_SERIES(1, c.size) s
CROSS APPLY GENERATE_SERIES(1, CASE WHEN c.size = 300 THEN 3 ELSE 1 END) n
WHERE s.value % 50 NOT IN (0, 1, 2, 3);

DECLARE @codigoBase INT = ISNULL((SELECT MAX(codigo) FROM dbo.DetalleAsistencia), 0);
INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin)
SELECT CONVERT(UNIQUEIDENTIFIER, CONCAT('DE000009', SUBSTRING(CONVERT(CHAR(36), a.id), 9, 28))),
       @codigoBase + ROW_NUMBER() OVER (ORDER BY a.id),
       a.id,
       CASE WHEN x.estado = 'AN' THEN 1 ELSE 0 END,
       CASE x.estado WHEN 'AN' THEN @rAN WHEN 'SJC' THEN @rSJC ELSE @rEX END,
       ses.fechaHoraInicio, ses.fechaHoraFin
FROM dbo.Asistencia a
JOIN dbo.Sesion ses ON ses.id = a.sesion
JOIN dbo.EstudianteGrupo eg ON eg.id = a.estudianteGrupo
CROSS APPLY (SELECT estado = CASE WHEN (CONVERT(INT, CONVERT(VARBINARY(4), RIGHT(CONVERT(CHAR(36), eg.id), 8), 2)) + ses.numero) % 11 = 0 THEN 'EX'
                                  WHEN (CONVERT(INT, CONVERT(VARBINARY(4), RIGHT(CONVERT(CHAR(36), eg.id), 8), 2)) + ses.numero) % 7 = 0 THEN 'SJC'
                                  ELSE 'AN' END) x
WHERE LEFT(CONVERT(CHAR(36), a.id), 6) = 'DE0000';

COMMIT TRANSACTION;

SELECT
    (SELECT COUNT(*) FROM dbo.Usuario WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS usuarios,
    (SELECT COUNT(*) FROM dbo.Estudiante WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS estudiantes,
    (SELECT COUNT(*) FROM dbo.Docente WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS docentes,
    (SELECT COUNT(*) FROM dbo.Grupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS grupos,
    (SELECT COUNT(*) FROM dbo.EstudianteGrupo WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS matriculas,
    (SELECT COUNT(*) FROM dbo.Sesion WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS sesiones,
    (SELECT COUNT(*) FROM dbo.Asistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS asistencias,
    (SELECT COUNT(*) FROM dbo.DetalleAsistencia WHERE LEFT(CONVERT(CHAR(36), id), 6) = 'DE0000') AS detalles;
PRINT 'DEV_FIXTURE_LOAD_OK';
GO
