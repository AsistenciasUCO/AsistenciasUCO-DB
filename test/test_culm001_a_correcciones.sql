USE [gestionasistenciadb];
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ============================================================================
-- CULM-001 paquete A.2 (CONTRACT §8.2.4): correcciones criticas y altas de la Fase 1, capa de BD.
--   A2-T-01..05 directorio con ambito en SP        A2-T-06/06b estudiantes del grupo con ambito y sin limite
--   A2-T-07 asistencias del grupo con ambito       A2-T-08 solo la matricula A cuenta como inscrita
--   A2-T-09 solape de sesiones                     A2-T-10/11 retiro del reclamo propio y estado X
--   A2-T-12 estado del decano y RBAC               A2-T-13 semillas 33      A2-T-14 grants
--   A2-T-17 busqueda por documento (DEC-027)
-- Fixtures: el procedimiento temporal #a2_fixture crea un segundo ambito completo con ids fijos (prefijo C1A2...),
-- siempre dentro de una transaccion que se revierte. Los SP de consulta rechazan con THROW y SET XACT_ABORT ON, lo que
-- deja la transaccion del llamador no confirmable; por eso cada rechazo esperado corre en su propia transaccion
-- (#a2_expect: fixture + llamada + ROLLBACK). Las pruebas no dependen de culm1_segundo_ambito.sql (A2-T-15).
-- ============================================================================
PRINT 'TEST START: test_culm001_a_correcciones';
GO

IF OBJECT_ID('tempdb..#a2_fixture') IS NOT NULL DROP PROCEDURE #a2_fixture;
IF OBJECT_ID('tempdb..#a2_expect') IS NOT NULL DROP PROCEDURE #a2_expect;
GO

CREATE PROCEDURE #a2_fixture
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @p CHAR(34) = 'C1A20000-0000-4000-8000-0000000000';
    DECLARE @inst1 UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Institucion ORDER BY id);
    DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
    DECLARE @tipoProg UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoPrograma ORDER BY nombre);
    DECLARE @semestre UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.Semestre ORDER BY id);
    DECLARE @area UNIQUEIDENTIFIER = (SELECT TOP 1 area FROM dbo.Asignatura ORDER BY id);
    DECLARE @esp UNIQUEIDENTIFIER = (SELECT id FROM dbo.Componente WHERE codigo = N'ESP');
    DECLARE @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
    DECLARE @estI UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'I');
    DECLARE @estCI UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'CI');
    DECLARE @estCVP UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'CVP');
    DECLARE @estF UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'F');
    DECLARE @an UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'AN');
    DECLARE @sjc UNIQUEIDENTIFIER = (SELECT id FROM dbo.RazonCausa WHERE codigo = 'SJC');
    DECLARE @recP UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'P');
    DECLARE @recA UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'A');
    DECLARE @recR UNIQUEIDENTIFIER = (SELECT id FROM dbo.Estado WHERE codigo = 'R');
    DECLARE @diaLu UNIQUEIDENTIFIER = (SELECT id FROM dbo.Dia WHERE codigo = N'LU');
    DECLARE @hoy DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE CAST(dbo.ufn_obtener_parametro('TIEMPO', 'ZONA_HORARIA_SQLSERVER') AS NVARCHAR(100)) AS DATE);
    DECLARE @codBase INT = 870000 + ABS(CHECKSUM(NEWID()) % 9000) * 10;
    DECLARE @detalle INT = 1 + (SELECT ISNULL(MAX(codigo), 0) FROM dbo.DetalleAsistencia);
    IF @inst1 IS NULL OR @tipoCC IS NULL OR @tipoProg IS NULL OR @semestre IS NULL OR @area IS NULL OR @esp IS NULL OR @estA IS NULL
       OR @estI IS NULL OR @estCI IS NULL OR @estCVP IS NULL OR @estF IS NULL OR @an IS NULL OR @sjc IS NULL OR @recP IS NULL
       OR @recA IS NULL OR @recR IS NULL OR @diaLu IS NULL
        THROW 58000, 'TEST FAILED: CULM001A2 catalogos base no disponibles (semilla).', 1;

    INSERT INTO dbo.Institucion (id, nombre, estado) VALUES (CAST(@p + '01' AS UNIQUEIDENTIFIER), N'QA CULM001A2 Inst Z', 1);

    -- Usuarios (11..1C roles, 21..28 estudiantes)
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), @tipoCC, 1987000000 + v.n, v.ape, N'Qa', v.nom, v.nom2, CONCAT(N'culm001a2.', LOWER(v.k), N'@test.local'), 1, 1, N'HashBackend_A2'
    FROM (VALUES
        ('11', 11, N'Admin', N'Uno', N'A'), ('12', 12, N'Admin', N'Dos', N'A'), ('13', 13, N'Coord', N'A', N'A'), ('14', 14, N'Coord', N'B', N'A'),
        ('15', 15, N'Coord', N'Z', N'A'), ('16', 16, N'Docente', N'Titular', N'A'), ('17', 17, N'Docente', N'Otro', N'A'),
        ('18', 18, N'Docente', N'Zeta', N'A'), ('19', 19, N'Decano', N'Uno', N'A'), ('1A', 20, N'Decano', N'Zeta', N'A'),
        ('1B', 21, N'Decano', N'Dual', N'A'), ('1C', 22, N'Decano', N'Solo', N'A'),
        ('21', 31, N'CulmdirA', N'Est', N'Pct_1'), ('22', 32, N'CulmdirB', N'Est', N'PctX1'), ('23', 33, N'CulmdirC', N'Est', N'A'),
        ('24', 34, N'CulmdirD', N'Est', N'A'), ('25', 35, N'CulmdirE', N'Est', N'A'), ('26', 36, N'CulmdirF', N'Est', N'A'),
        ('28', 38, N'CulmdirH', N'Est', N'A')
    ) v (k, n, ape, nom, nom2);

    INSERT INTO dbo.Administrador (id, usuario, institucion) VALUES
        (CAST(@p + '31' AS UNIQUEIDENTIFIER), CAST(@p + '11' AS UNIQUEIDENTIFIER), @inst1),
        (CAST(@p + '32' AS UNIQUEIDENTIFIER), CAST(@p + '12' AS UNIQUEIDENTIFIER), CAST(@p + '01' AS UNIQUEIDENTIFIER));
    INSERT INTO dbo.Decano (id, usuario) VALUES
        (CAST(@p + '49' AS UNIQUEIDENTIFIER), CAST(@p + '19' AS UNIQUEIDENTIFIER)), (CAST(@p + '4A' AS UNIQUEIDENTIFIER), CAST(@p + '1A' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '4B' AS UNIQUEIDENTIFIER), CAST(@p + '1B' AS UNIQUEIDENTIFIER)), (CAST(@p + '4C' AS UNIQUEIDENTIFIER), CAST(@p + '1C' AS UNIQUEIDENTIFIER));
    INSERT INTO dbo.Facultad (id, nombre, institucion, decano, estado) VALUES
        (CAST(@p + '61' AS UNIQUEIDENTIFIER), N'QA A2 Facultad A', @inst1, CAST(@p + '49' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '62' AS UNIQUEIDENTIFIER), N'QA A2 Facultad Z', CAST(@p + '01' AS UNIQUEIDENTIFIER), CAST(@p + '4A' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '63' AS UNIQUEIDENTIFIER), N'QA A2 Facultad D', @inst1, CAST(@p + '4B' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '64' AS UNIQUEIDENTIFIER), N'QA A2 Facultad E', @inst1, CAST(@p + '4C' AS UNIQUEIDENTIFIER), 1);
    INSERT INTO dbo.Coordinador (id, usuario, facultad) VALUES
        (CAST(@p + '33' AS UNIQUEIDENTIFIER), CAST(@p + '13' AS UNIQUEIDENTIFIER), CAST(@p + '61' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '34' AS UNIQUEIDENTIFIER), CAST(@p + '14' AS UNIQUEIDENTIFIER), CAST(@p + '61' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '35' AS UNIQUEIDENTIFIER), CAST(@p + '15' AS UNIQUEIDENTIFIER), CAST(@p + '62' AS UNIQUEIDENTIFIER));
    INSERT INTO dbo.Docente (id, usuario) VALUES
        (CAST(@p + '36' AS UNIQUEIDENTIFIER), CAST(@p + '16' AS UNIQUEIDENTIFIER)), (CAST(@p + '37' AS UNIQUEIDENTIFIER), CAST(@p + '17' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '38' AS UNIQUEIDENTIFIER), CAST(@p + '18' AS UNIQUEIDENTIFIER)), (CAST(@p + '3B' AS UNIQUEIDENTIFIER), CAST(@p + '1B' AS UNIQUEIDENTIFIER));
    INSERT INTO dbo.Estudiante (id, usuario)
    SELECT CAST(@p + CONCAT('5', RIGHT(v.k, 1)) AS UNIQUEIDENTIFIER), CAST(@p + v.k AS UNIQUEIDENTIFIER)
    FROM (VALUES ('21'), ('22'), ('23'), ('24'), ('25'), ('26'), ('28')) v (k);

    INSERT INTO dbo.Programa (id, facultad, tipoDePrograma, nombre, coordinador, estado) VALUES
        (CAST(@p + '65' AS UNIQUEIDENTIFIER), CAST(@p + '61' AS UNIQUEIDENTIFIER), @tipoProg, N'QA A2 Programa A', CAST(@p + '33' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '66' AS UNIQUEIDENTIFIER), CAST(@p + '61' AS UNIQUEIDENTIFIER), @tipoProg, N'QA A2 Programa B', CAST(@p + '34' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '67' AS UNIQUEIDENTIFIER), CAST(@p + '62' AS UNIQUEIDENTIFIER), @tipoProg, N'QA A2 Programa Z', CAST(@p + '35' AS UNIQUEIDENTIFIER), 1);
    INSERT INTO dbo.PlanEstudio (id, programa, inp, estado) VALUES
        (CAST(@p + '68' AS UNIQUEIDENTIFIER), CAST(@p + '65' AS UNIQUEIDENTIFIER), @codBase + 1, 1),
        (CAST(@p + '69' AS UNIQUEIDENTIFIER), CAST(@p + '66' AS UNIQUEIDENTIFIER), @codBase + 2, 1),
        (CAST(@p + '6A' AS UNIQUEIDENTIFIER), CAST(@p + '67' AS UNIQUEIDENTIFIER), @codBase + 3, 1);
    INSERT INTO dbo.SemestrePlanEstudio (id, planEstudio, semestre) VALUES
        (CAST(@p + '6B' AS UNIQUEIDENTIFIER), CAST(@p + '68' AS UNIQUEIDENTIFIER), @semestre),
        (CAST(@p + '6C' AS UNIQUEIDENTIFIER), CAST(@p + '69' AS UNIQUEIDENTIFIER), @semestre),
        (CAST(@p + '6D' AS UNIQUEIDENTIFIER), CAST(@p + '6A' AS UNIQUEIDENTIFIER), @semestre);
    INSERT INTO dbo.Asignatura (id, codigo, nombre, credito, area, componente, semestrePlanEstudio, estado) VALUES
        (CAST(@p + '6E' AS UNIQUEIDENTIFIER), CONCAT(N'A2A', @codBase), N'QA A2 Asignatura A', 3, @area, @esp, CAST(@p + '6B' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '6F' AS UNIQUEIDENTIFIER), CONCAT(N'A2B', @codBase), N'QA A2 Asignatura B', 3, @area, @esp, CAST(@p + '6C' AS UNIQUEIDENTIFIER), 1),
        (CAST(@p + '70' AS UNIQUEIDENTIFIER), CONCAT(N'A2Z', @codBase), N'QA A2 Asignatura Z', 3, @area, @esp, CAST(@p + '6D' AS UNIQUEIDENTIFIER), 1);
    INSERT INTO dbo.PeriodoAcademico (id, institucion, nombre, codigo, fechaInicio, fechaFin, anio) VALUES
        (CAST(@p + '71' AS UNIQUEIDENTIFIER), @inst1, N'QA A2 Periodo V', @codBase + 4, DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy)),
        (CAST(@p + '72' AS UNIQUEIDENTIFIER), CAST(@p + '01' AS UNIQUEIDENTIFIER), N'QA A2 Periodo Z', @codBase + 5, DATEADD(DAY, -60, @hoy), DATEADD(DAY, 60, @hoy), YEAR(@hoy));
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), CAST(@p + v.a AS UNIQUEIDENTIFIER), CAST(@p + v.per AS UNIQUEIDENTIFIER), @codBase + v.n, v.nombre, 30, 0, 0, 0,
           CAST(@p + v.d AS UNIQUEIDENTIFIER)
    FROM (VALUES
        ('73', '6E', '71', 6, N'QA A2 Grupo 1', '36'), ('74', '6F', '71', 7, N'QA A2 Grupo 2', '36'), ('75', '6E', '71', 8, N'QA A2 Grupo 3', '37'),
        ('76', '70', '72', 9, N'QA A2 Grupo Z', '38'), ('77', '6E', '71', 10, N'A2 Estado G5', '37'), ('78', '6E', '71', 11, N'A2 Estado G6', '37'),
        ('79', '6E', '71', 12, N'A2 Estado G7', '37'), ('7A', '6E', '71', 13, N'A2 Estado G8', '37'), ('7B', '6E', '71', 14, N'A2 Estado G9', '37')
    ) v (k, a, per, n, nombre, d);
    INSERT INTO dbo.Horario (id, grupo, dia, horaInicio, horaFin) VALUES
        (CAST(@p + 'B1' AS UNIQUEIDENTIFIER), CAST(@p + '77' AS UNIQUEIDENTIFIER), @diaLu, '06:00', '07:00'),
        (CAST(@p + 'B2' AS UNIQUEIDENTIFIER), CAST(@p + '78' AS UNIQUEIDENTIFIER), @diaLu, '07:00', '08:00');

    -- Matriculas y programas: E1 (G1 A, G3 A; PA), E2 (G1 A; PB), E3 (G1 I; sin programa), E4 (G3 A; PA), E5 sin vinculos,
    -- E6 (GZ A; PZ, otra institucion), E8 (G5 A, G6 I, G7 CI, G8 CVP, G9 F; PA).
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo)
    SELECT CAST(@p + v.k AS UNIQUEIDENTIFIER), v.est, CAST(@p + v.e AS UNIQUEIDENTIFIER), CAST(@p + v.g AS UNIQUEIDENTIFIER)
    FROM (VALUES
        ('81', @estA, '51', '73'), ('82', @estA, '51', '75'), ('83', @estA, '52', '73'), ('84', @estI, '53', '73'), ('85', @estA, '54', '75'),
        ('86', @estA, '56', '76'), ('87', @estA, '58', '77'), ('88', @estI, '58', '78'), ('89', @estCI, '58', '79'), ('8A', @estCVP, '58', '7A'),
        ('8B', @estF, '58', '7B')
    ) v (k, est, e, g);
    INSERT INTO dbo.EstudiantePrograma (id, estudiante, programa) VALUES
        (CAST(@p + '91' AS UNIQUEIDENTIFIER), CAST(@p + '51' AS UNIQUEIDENTIFIER), CAST(@p + '65' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '92' AS UNIQUEIDENTIFIER), CAST(@p + '52' AS UNIQUEIDENTIFIER), CAST(@p + '66' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '93' AS UNIQUEIDENTIFIER), CAST(@p + '54' AS UNIQUEIDENTIFIER), CAST(@p + '65' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '94' AS UNIQUEIDENTIFIER), CAST(@p + '56' AS UNIQUEIDENTIFIER), CAST(@p + '67' AS UNIQUEIDENTIFIER)),
        (CAST(@p + '95' AS UNIQUEIDENTIFIER), CAST(@p + '58' AS UNIQUEIDENTIFIER), CAST(@p + '65' AS UNIQUEIDENTIFIER));

    -- Sesiones pasadas de G1 con asistencias (E3 sin registro) y reclamos P (E2), A y R (E1).
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
        (CAST(@p + 'A1' AS UNIQUEIDENTIFIER), N'QA A2 S1', 1, N'QAA2S1', 1, CAST(@p + '73' AS UNIQUEIDENTIFIER), DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME())),
        (CAST(@p + 'A2' AS UNIQUEIDENTIFIER), N'QA A2 S2', 2, N'QAA2S2', 1, CAST(@p + '73' AS UNIQUEIDENTIFIER), DATEADD(HOUR, -27, SYSUTCDATETIME()), DATEADD(HOUR, -26, SYSUTCDATETIME()));
    INSERT INTO dbo.Asistencia (id, estudianteGrupo, sesion) VALUES
        (CAST(@p + 'A3' AS UNIQUEIDENTIFIER), CAST(@p + '81' AS UNIQUEIDENTIFIER), CAST(@p + 'A1' AS UNIQUEIDENTIFIER)),
        (CAST(@p + 'A4' AS UNIQUEIDENTIFIER), CAST(@p + '83' AS UNIQUEIDENTIFIER), CAST(@p + 'A1' AS UNIQUEIDENTIFIER)),
        (CAST(@p + 'A5' AS UNIQUEIDENTIFIER), CAST(@p + '81' AS UNIQUEIDENTIFIER), CAST(@p + 'A2' AS UNIQUEIDENTIFIER));
    INSERT INTO dbo.DetalleAsistencia (id, codigo, asistencia, asistio, razonCausa, fechaHoraInicio, fechaHoraFin) VALUES
        (CAST(@p + 'A6' AS UNIQUEIDENTIFIER), @detalle, CAST(@p + 'A3' AS UNIQUEIDENTIFIER), 1, @an, DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME())),
        (CAST(@p + 'A7' AS UNIQUEIDENTIFIER), @detalle + 1, CAST(@p + 'A4' AS UNIQUEIDENTIFIER), 0, @sjc, DATEADD(HOUR, -3, SYSUTCDATETIME()), DATEADD(HOUR, -2, SYSUTCDATETIME())),
        (CAST(@p + 'A8' AS UNIQUEIDENTIFIER), @detalle + 2, CAST(@p + 'A5' AS UNIQUEIDENTIFIER), 1, @an, DATEADD(HOUR, -27, SYSUTCDATETIME()), DATEADD(HOUR, -26, SYSUTCDATETIME()));
    INSERT INTO dbo.SolicitudRevisionAsistencia (id, nombre, asistencia, fecha, estado, justificacionSolicitud, justificacionRespuesta) VALUES
        (CAST(@p + 'A9' AS UNIQUEIDENTIFIER), N'REC-QAA2-1', CAST(@p + 'A4' AS UNIQUEIDENTIFIER), @hoy, @recP, 'QA A2 pendiente', ''),
        (CAST(@p + 'AA' AS UNIQUEIDENTIFIER), N'REC-QAA2-2', CAST(@p + 'A3' AS UNIQUEIDENTIFIER), @hoy, @recA, 'QA A2 aprobado', 'ok'),
        (CAST(@p + 'AB' AS UNIQUEIDENTIFIER), N'REC-QAA2-3', CAST(@p + 'A5' AS UNIQUEIDENTIFIER), @hoy, @recR, 'QA A2 rechazado', 'no');
END;
GO

-- #a2_expect: corre @sql en su propia transaccion con la fixture y exige el DBCODE esperado (o ningun error si es NULL).
CREATE PROCEDURE #a2_expect
    @etiqueta NVARCHAR(100),
    @sql      NVARCHAR(MAX),
    @codigo   VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mensaje NVARCHAR(4000) = NULL;
    BEGIN TRANSACTION;
    BEGIN TRY
        EXEC #a2_fixture;
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @mensaje = ERROR_MESSAGE();
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF (@codigo IS NULL AND @mensaje IS NOT NULL)
       OR (@codigo IS NOT NULL AND (@mensaje IS NULL OR @mensaje NOT LIKE CONCAT(N'%DBCODE=', REPLACE(@codigo, '_', '[_]'), N'|%')))
    BEGIN
        DECLARE @falla NVARCHAR(2048) = LEFT(CONCAT(N'TEST FAILED: ', @etiqueta, N' esperaba ', ISNULL(@codigo, N'sin error'), N'; obtuvo: ', ISNULL(@mensaje, N'sin error')), 2048);
        THROW 58099, @falla, 1;
    END
END;
GO

-- ---------------------------------------------------------------------------
-- Casos sin rechazo por THROW, en UNA transaccion con ROLLBACK final.
-- ---------------------------------------------------------------------------
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @p CHAR(34) = 'C1A20000-0000-4000-8000-0000000000';
DECLARE @uAdmin1 UNIQUEIDENTIFIER = CAST(@p + '11' AS UNIQUEIDENTIFIER), @uAdmin2 UNIQUEIDENTIFIER = CAST(@p + '12' AS UNIQUEIDENTIFIER);
DECLARE @uCoordA UNIQUEIDENTIFIER = CAST(@p + '13' AS UNIQUEIDENTIFIER), @uCoordB UNIQUEIDENTIFIER = CAST(@p + '14' AS UNIQUEIDENTIFIER);
DECLARE @uDocT UNIQUEIDENTIFIER = CAST(@p + '16' AS UNIQUEIDENTIFIER), @uDocO UNIQUEIDENTIFIER = CAST(@p + '17' AS UNIQUEIDENTIFIER);
DECLARE @uDec1 UNIQUEIDENTIFIER = CAST(@p + '19' AS UNIQUEIDENTIFIER), @uDecD UNIQUEIDENTIFIER = CAST(@p + '1B' AS UNIQUEIDENTIFIER), @uDecE UNIQUEIDENTIFIER = CAST(@p + '1C' AS UNIQUEIDENTIFIER);
DECLARE @uE1 UNIQUEIDENTIFIER = CAST(@p + '21' AS UNIQUEIDENTIFIER), @uE2 UNIQUEIDENTIFIER = CAST(@p + '22' AS UNIQUEIDENTIFIER), @uE8 UNIQUEIDENTIFIER = CAST(@p + '28' AS UNIQUEIDENTIFIER);
DECLARE @E1 UNIQUEIDENTIFIER = CAST(@p + '51' AS UNIQUEIDENTIFIER), @E2 UNIQUEIDENTIFIER = CAST(@p + '52' AS UNIQUEIDENTIFIER), @E3 UNIQUEIDENTIFIER = CAST(@p + '53' AS UNIQUEIDENTIFIER);
DECLARE @E4 UNIQUEIDENTIFIER = CAST(@p + '54' AS UNIQUEIDENTIFIER), @E5 UNIQUEIDENTIFIER = CAST(@p + '55' AS UNIQUEIDENTIFIER), @E6 UNIQUEIDENTIFIER = CAST(@p + '56' AS UNIQUEIDENTIFIER);
DECLARE @kA UNIQUEIDENTIFIER = CAST(@p + '49' AS UNIQUEIDENTIFIER), @kD UNIQUEIDENTIFIER = CAST(@p + '4B' AS UNIQUEIDENTIFIER), @kE UNIQUEIDENTIFIER = CAST(@p + '4C' AS UNIQUEIDENTIFIER);
DECLARE @PA UNIQUEIDENTIFIER = CAST(@p + '65' AS UNIQUEIDENTIFIER), @PB UNIQUEIDENTIFIER = CAST(@p + '66' AS UNIQUEIDENTIFIER);
DECLARE @G1 UNIQUEIDENTIFIER = CAST(@p + '73' AS UNIQUEIDENTIFIER), @G2 UNIQUEIDENTIFIER = CAST(@p + '74' AS UNIQUEIDENTIFIER), @G3 UNIQUEIDENTIFIER = CAST(@p + '75' AS UNIQUEIDENTIFIER);
DECLARE @G5 UNIQUEIDENTIFIER = CAST(@p + '77' AS UNIQUEIDENTIFIER), @S1 UNIQUEIDENTIFIER = CAST(@p + 'A1' AS UNIQUEIDENTIFIER);
DECLARE @R1 UNIQUEIDENTIFIER = CAST(@p + 'A9' AS UNIQUEIDENTIFIER), @R2 UNIQUEIDENTIFIER = CAST(@p + 'AA' AS UNIQUEIDENTIFIER), @R3 UNIQUEIDENTIFIER = CAST(@p + 'AB' AS UNIQUEIDENTIFIER);
DECLARE @tipoCC UNIQUEIDENTIFIER = (SELECT TOP 1 id FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @c UNIQUEIDENTIFIER = NEWID(), @mu NVARCHAR(4000), @mt NVARCHAR(4000), @ok BIT, @n INT, @sql NVARCHAR(MAX);

CREATE TABLE #dl (n INT IDENTITY(1,1), id UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, tipoIdentificacionId UNIQUEIDENTIFIER, numeroIdentificacion INT,
    primerApellido NVARCHAR(50), segundoApellido NVARCHAR(50), primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), nombreCompleto NVARCHAR(400),
    correo NVARCHAR(100), estaActivoUsuario BIT, totalRegistros INT);
CREATE TABLE #dd (id UNIQUEIDENTIFIER, idUsuario UNIQUEIDENTIFIER, tipoIdentificacionId UNIQUEIDENTIFIER, numeroIdentificacion INT,
    primerApellido NVARCHAR(50), segundoApellido NVARCHAR(50), primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), nombreCompleto NVARCHAR(400),
    correo NVARCHAR(100), estaActivoUsuario BIT, idInstitucion UNIQUEIDENTIFIER, nombreInstitucion NVARCHAR(100), idFacultad UNIQUEIDENTIFIER,
    nombreFacultad NVARCHAR(100), idPrograma UNIQUEIDENTIFIER, nombrePrograma NVARCHAR(100), idPlanEstudio UNIQUEIDENTIFIER, inpPlanEstudio NVARCHAR(20),
    idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(100));
CREATE TABLE #eg (id UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, documento NVARCHAR(20), nombreCompleto NVARCHAR(400), correo NVARCHAR(100),
    codigoEstado NVARCHAR(10), nombreEstado NVARCHAR(100), totalRegistros INT);
CREATE TABLE #as (asistencia UNIQUEIDENTIFIER, estudiante UNIQUEIDENTIFIER, grupo UNIQUEIDENTIFIER, sesion UNIQUEIDENTIFIER, presente BIT,
    estado NVARCHAR(10), observacion NVARCHAR(500), totalRegistros INT);
CREATE TABLE #mat (idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100), idGrupo UNIQUEIDENTIFIER, nombreGrupo NVARCHAR(100));
CREATE TABLE #hor (id UNIQUEIDENTIFIER, idEstudiante UNIQUEIDENTIFIER, idGrupo UNIQUEIDENTIFIER, codigoMateria NVARCHAR(50), nombreMateria NVARCHAR(100),
    grupo NVARCHAR(100), dia NVARCHAR(50), horaInicio VARCHAR(5), horaFin VARCHAR(5), docente NVARCHAR(400));
CREATE TABLE #o (idGrupo UNIQUEIDENTIFIER, codigoGrupo INT, nombreGrupo NVARCHAR(50), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(50),
    nombreAsignatura NVARCHAR(100), nombreDocente NVARCHAR(400), idPeriodoAcademico UNIQUEIDENTIFIER, nombrePeriodoAcademico NVARCHAR(50),
    fechaInicioPeriodo DATE, fechaFinPeriodo DATE, estadoPeriodo NVARCHAR(10), horario NVARCHAR(400), capacidadMaxima INT, estudiantesActivos INT,
    cuposDisponibles INT, matriculado BIT, codigoComponente NVARCHAR(3), totalRegistros INT);
CREATE TABLE #r (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT);
CREATE TABLE #dec (idCorrelacion UNIQUEIDENTIFIER, mensajeUsuarioResultado NVARCHAR(4000), mensajeTecnicoResultado NVARCHAR(4000), estadoResultado BIT,
    idUsuario UNIQUEIDENTIFIER, personaSinRolesActivos BIT, estaActivoDecano BIT);
CREATE TABLE #bus (idEstudiante UNIQUEIDENTIFIER, primerNombre NVARCHAR(50), segundoNombre NVARCHAR(50), primerApellido NVARCHAR(50),
    segundoApellido NVARCHAR(50), nombreCompleto NVARCHAR(400), numeroIdentificacion INT, correoEnmascarado NVARCHAR(120), codigoEstadoMatriculaGrupo NVARCHAR(10));
CREATE TABLE #r2 (idSolicitudRevisionAsistencia UNIQUEIDENTIFIER, nombreSolicitud NVARCHAR(50), fechaSolicitud DATE,
    codigoEstado CHAR(1), nombreEstado NVARCHAR(100), justificacionSolicitud NVARCHAR(MAX), justificacionRespuesta NVARCHAR(MAX),
    idEstudiante UNIQUEIDENTIFIER, nombreEstudiante NVARCHAR(400), idSesion UNIQUEIDENTIFIER, numeroSesion INT,
    fechaHoraInicioSesion DATETIME2(7), procedenciaTemporalSesion NVARCHAR(24), idGrupo UNIQUEIDENTIFIER, codigoGrupo INT,
    nombreGrupo NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, codigoAsignatura NVARCHAR(100), nombreAsignatura NVARCHAR(100),
    idArchivoSoporte UNIQUEIDENTIFIER, nombreSoporte NVARCHAR(250), tipoContenidoSoporte VARCHAR(50),
    tamanioSoporteBytes BIGINT, fechaRegistroSoporteUtc DATETIME2(7), totalRegistros INT);

BEGIN TRANSACTION;
BEGIN TRY
    EXEC #a2_fixture;

    -- ======================================================= A2-T-01: directorio, ADMINISTRADOR (solo su institucion)
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'culmdir', @numeroPagina = 1, @tamanoPagina = 20;
    IF (SELECT COUNT(*) FROM #dl) <> 5 OR EXISTS (SELECT 1 FROM #dl WHERE totalRegistros <> 5)
       OR NOT EXISTS (SELECT 1 FROM #dl WHERE id = @E1) OR NOT EXISTS (SELECT 1 FROM #dl WHERE id = @E3)
       OR EXISTS (SELECT 1 FROM #dl WHERE id IN (@E5, @E6))
        THROW 58101, 'TEST FAILED: A2-T-01 el administrador ve E1, E2, E3, E4 y E8 (su institucion; E5 sin vinculos y E6 de otra institucion no).', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin2, @idCorrelacion = @c, @nombre = N'culmdir';
    IF (SELECT COUNT(*) FROM #dl) <> 1 OR NOT EXISTS (SELECT 1 FROM #dl WHERE id = @E6 AND totalRegistros = 1)
        THROW 58102, 'TEST FAILED: A2-T-01 el administrador de otra institucion solo ve a E6.', 1;
    PRINT 'TEST_PASS:CULM001A2_T01_DIRECTORIO_ADMINISTRADOR';

    -- ======================================================= A2-T-02: directorio, COORDINADOR (EstudiantePrograma de sus programas)
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c, @nombre = N'culmdir';
    IF (SELECT COUNT(*) FROM #dl) <> 3 OR EXISTS (SELECT 1 FROM #dl WHERE id NOT IN (@E1, @E4, CAST(@p + '58' AS UNIQUEIDENTIFIER)))
        THROW 58103, 'TEST FAILED: A2-T-02 el coordinador de PA ve solo E1, E4 y E8.', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c, @idPrograma = @PB;
    IF (SELECT COUNT(*) FROM #dl) <> 0
        THROW 58104, 'TEST FAILED: A2-T-02 un programa ajeno da 0 filas (el filtro solo restringe dentro del ambito).', 1;
    UPDATE dbo.Coordinador SET estado = 0 WHERE usuario = @uCoordA;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c;
    UPDATE dbo.Coordinador SET estado = 1 WHERE usuario = @uCoordA;
    IF (SELECT COUNT(*) FROM #dl) <> 0
        THROW 58105, 'TEST FAILED: A2-T-02 un coordinador inactivo no ve estudiantes.', 1;
    PRINT 'TEST_PASS:CULM001A2_T02_DIRECTORIO_COORDINADOR';

    -- ======================================================= A2-T-03: directorio, DOCENTE (matriculas en sus grupos, incluidas I)
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #dl) <> 3 OR EXISTS (SELECT 1 FROM #dl WHERE id NOT IN (@E1, @E2, @E3))
        THROW 58106, 'TEST FAILED: A2-T-03 el docente titular ve E1, E2 y E3 (incluida la matricula I), no E4.', 1;
    PRINT 'TEST_PASS:CULM001A2_T03_DIRECTORIO_DOCENTE';

    -- ======================================================= A2-T-04: directorio, detalle con contextos del ambito
    INSERT INTO #dd EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @idEstudiante = @E4;
    IF (SELECT COUNT(*) FROM #dd) <> 0
        THROW 58107, 'TEST FAILED: A2-T-04 el detalle de un estudiante fuera de ambito da 0 filas.', 1;
    INSERT INTO #dd EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @idEstudiante = @E1;
    IF (SELECT COUNT(*) FROM #dd) <> 1 OR NOT EXISTS (SELECT 1 FROM #dd WHERE id = @E1 AND idGrupo = @G1 AND idPrograma = @PA)
        THROW 58108, 'TEST FAILED: A2-T-04 el docente ve el detalle de E1 solo con el contexto de su grupo (G1, no G3).', 1;
    TRUNCATE TABLE #dd;
    INSERT INTO #dd EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c, @idEstudiante = @E1;
    IF (SELECT COUNT(*) FROM #dd) <> 2 OR EXISTS (SELECT 1 FROM #dd WHERE idGrupo NOT IN (@G1, @G3))
        THROW 58109, 'TEST FAILED: A2-T-04 el coordinador de PA ve los dos contextos de E1 en su programa.', 1;
    TRUNCATE TABLE #dd;
    INSERT INTO #dd EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @idEstudiante = @E5;
    IF (SELECT COUNT(*) FROM #dd) <> 0
        THROW 58110, 'TEST FAILED: A2-T-04 un estudiante sin vinculos no aparece ni en el detalle (fail-closed).', 1;
    PRINT 'TEST_PASS:CULM001A2_T04_DIRECTORIO_DETALLE';

    -- ======================================================= A2-T-05: otros roles, orden, escape y paginacion
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDec1, @idCorrelacion = @c;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uE1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #dl) <> 0
        THROW 58111, 'TEST FAILED: A2-T-05 DECANO y ESTUDIANTE tienen ambito vacio.', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'culmdir';
    IF (SELECT id FROM #dl WHERE n = 1) <> @E1 OR (SELECT id FROM #dl WHERE n = 2) <> @E2 OR (SELECT id FROM #dl WHERE n = 3) <> @E3
       OR (SELECT id FROM #dl WHERE n = 4) <> @E4
        THROW 58112, 'TEST FAILED: A2-T-05 orden fijo primerApellido, primerNombre, numeroIdentificacion, id.', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'pct_1';
    IF (SELECT COUNT(*) FROM #dl) <> 1 OR NOT EXISTS (SELECT 1 FROM #dl WHERE id = @E1)
        THROW 58113, 'TEST FAILED: A2-T-05 el _ del filtro nombre se escapa (no es comodin).', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'%';
    IF (SELECT COUNT(*) FROM #dl) <> 0
        THROW 58114, 'TEST FAILED: A2-T-05 el % del filtro nombre se escapa (no es comodin).', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'culmdir', @numeroPagina = 2, @tamanoPagina = 2;
    IF (SELECT COUNT(*) FROM #dl) <> 2 OR EXISTS (SELECT 1 FROM #dl WHERE totalRegistros <> 5) OR (SELECT id FROM #dl WHERE n = 1) <> @E3
        THROW 58115, 'TEST FAILED: A2-T-05 la pagina 2 de tamano 2 trae E3 y E4 con totalRegistros real.', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c, @nombre = N'culmdir', @numeroPagina = 9, @tamanoPagina = 2;
    IF (SELECT COUNT(*) FROM #dl) <> 0
        THROW 58116, 'TEST FAILED: A2-T-05 una pagina posterior a la ultima da 0 filas.', 1;
    PRINT 'TEST_PASS:CULM001A2_T05_DIRECTORIO_ROLES_SEMANTICA';

    -- ======================================================= A2-T-06: estudiantes del grupo con ambito (casos sin rechazo)
    INSERT INTO #eg EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #eg) <> 3 OR NOT EXISTS (SELECT 1 FROM #eg WHERE idEstudiante = @E3 AND codigoEstado = N'I')
       OR EXISTS (SELECT 1 FROM #eg WHERE totalRegistros <> 3)
        THROW 58117, 'TEST FAILED: A2-T-06 el titular ve todas las matriculas de G1 en todos los estados.', 1;
    TRUNCATE TABLE #eg;
    INSERT INTO #eg EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #eg) <> 3
        THROW 58118, 'TEST FAILED: A2-T-06 el administrador de la institucion ve todas las matriculas.', 1;
    TRUNCATE TABLE #eg;
    INSERT INTO #eg EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #eg) <> 1 OR NOT EXISTS (SELECT 1 FROM #eg WHERE idEstudiante = @E1)
        THROW 58119, 'TEST FAILED: A2-T-06 el coordinador del programa del grupo solo ve a los estudiantes de su programa (DEC-031 §4).', 1;
    TRUNCATE TABLE #eg;
    INSERT INTO #eg EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c,
        @numeroPagina = 2, @tamanoPagina = 2;
    IF (SELECT COUNT(*) FROM #eg) <> 1
        THROW 58120, 'TEST FAILED: A2-T-06 con tamano de pagina el SP pagina.', 1;
    PRINT 'TEST_PASS:CULM001A2_T06_ESTUDIANTES_GRUPO';

    -- ======================================================= A2-T-07: asistencias del grupo con ambito (casos sin rechazo)
    INSERT INTO #as EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #as) <> 3 OR EXISTS (SELECT 1 FROM #as WHERE estudiante = @E3)
       OR NOT EXISTS (SELECT 1 FROM #as WHERE estudiante = @E2 AND presente = 0 AND estado = N'SJC')
        THROW 58121, 'TEST FAILED: A2-T-07 el titular ve las 3 asistencias registradas (sin registro = sin fila).', 1;
    TRUNCATE TABLE #as;
    INSERT INTO #as EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = @G1, @idSesion = @S1, @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #as) <> 2 OR EXISTS (SELECT 1 FROM #as WHERE sesion <> @S1)
        THROW 58122, 'TEST FAILED: A2-T-07 el filtro por sesion.', 1;
    TRUNCATE TABLE #as;
    INSERT INTO #as EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uCoordA, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #as) <> 2 OR EXISTS (SELECT 1 FROM #as WHERE estudiante <> @E1)
        THROW 58123, 'TEST FAILED: A2-T-07 el coordinador solo ve las asistencias de los estudiantes de su programa.', 1;
    TRUNCATE TABLE #as;
    INSERT INTO #as EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = @G1, @idUsuarioEjecutor = @uAdmin1, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #as) <> 3
        THROW 58124, 'TEST FAILED: A2-T-07 el administrador de la institucion ve todas las asistencias.', 1;
    PRINT 'TEST_PASS:CULM001A2_T07_ASISTENCIAS_GRUPO';

    -- ======================================================= A2-T-08: solo la matricula A cuenta como inscrita
    INSERT INTO #mat EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uE8, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mat) <> 1 OR NOT EXISTS (SELECT 1 FROM #mat WHERE idGrupo = @G5)
        THROW 58125, 'TEST FAILED: A2-T-08 materias: solo el grupo con matricula A (no I, CI, CVP ni F).', 1;
    INSERT INTO #hor EXEC dbo.usp_consultar_horario_estudiante @idUsuarioEjecutor = @uE8, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #hor) <> 1 OR NOT EXISTS (SELECT 1 FROM #hor WHERE idGrupo = @G5)
        THROW 58126, 'TEST FAILED: A2-T-08 horario: solo el grupo con matricula A.', 1;
    INSERT INTO #o EXEC dbo.usp_consultar_oferta_grupos_estudiante @busqueda = N'A2 Estado', @idCorrelacion = @c, @idUsuarioEjecutor = @uE8;
    IF (SELECT COUNT(*) FROM #o) <> 5 OR (SELECT COUNT(*) FROM #o WHERE matriculado = 1) <> 1 OR NOT EXISTS (SELECT 1 FROM #o WHERE idGrupo = @G5 AND matriculado = 1)
        THROW 58127, 'TEST FAILED: A2-T-08 la oferta marca matriculado = 1 solo en el grupo A.', 1;
    TRUNCATE TABLE #mat;
    INSERT INTO #mat EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c;
    IF (SELECT COUNT(*) FROM #mat) <> 0
        THROW 58128, 'TEST FAILED: A2-T-08 un ejecutor sin estudiante obtiene 0 filas.', 1;
    PRINT 'TEST_PASS:CULM001A2_T08_SOLO_MATRICULA_A';

    -- ======================================================= A2-T-09: solape de sesiones por las fachadas congeladas
    DECLARE @b DATETIME2 = DATEADD(HOUR, 13, CAST(DATEADD(DAY, 5, CAST(SYSUTCDATETIME() AS DATE)) AS DATETIME2));
    DECLARE @b1 DATETIME2 = DATEADD(HOUR, 1, @b), @b2 DATETIME2 = DATEADD(HOUR, 2, @b), @b3 DATETIME2 = DATEADD(HOUR, 3, @b);
    DECLARE @sA UNIQUEIDENTIFIER, @sAdj UNIQUEIDENTIFIER, @sX UNIQUEIDENTIFIER = NEWID(), @sY UNIQUEIDENTIFIER = NEWID();
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @G1, @nombre = N'QA A2 SA', @fechaHoraInicio = @b, @fechaHoraFin = @b2, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    SELECT @sA = id FROM dbo.Sesion WHERE grupo = @G1 AND nombre = N'QA A2 SA';
    IF @sA IS NULL OR NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1)
        THROW 58129, 'TEST FAILED: A2-T-09 crear una sesion sin solape.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @G1, @nombre = N'QA A2 Solapada', @fechaHoraInicio = @b1, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @G2, @nombre = N'QA A2 Solapada', @fechaHoraInicio = @b1, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #r EXEC dbo.usp_crear_sesion_v2 @idGrupo = @G2, @nombre = N'QA A2 Solapada', @fechaHoraInicio = @b1, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]017|%') <> 3
       OR EXISTS (SELECT 1 FROM dbo.Sesion WHERE nombre = N'QA A2 Solapada')
        THROW 58130, 'TEST FAILED: A2-T-09 solape en el mismo grupo y en otro grupo del docente (v1 y v2) => SES_017 sin escrituras.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @G1, @nombre = N'QA A2 Adyacente', @fechaHoraInicio = @b2, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #r EXEC dbo.usp_crear_sesion @idGrupo = @G3, @nombre = N'QA A2 Otro docente', @fechaHoraInicio = @b, @fechaHoraFin = @b2, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocO;
    SELECT @sAdj = id FROM dbo.Sesion WHERE grupo = @G1 AND nombre = N'QA A2 Adyacente';
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 1) <> 2 OR @sAdj IS NULL
        THROW 58131, 'TEST FAILED: A2-T-09 una sesion adyacente (fin = inicio) y la de otro docente a la misma hora se aceptan.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion @idSesion = @sA, @nombre = N'QA A2 SA renombrada', @fechaHoraInicio = @b, @fechaHoraFin = @b2, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sA AND nombre = N'QA A2 SA renombrada')
        THROW 58132, 'TEST FAILED: A2-T-09 actualizar una sesion sin cambiar su horario (se excluye a si misma).', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion @idSesion = @sAdj, @nombre = N'QA A2 Adyacente', @fechaHoraInicio = @b1, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion_v2 @idSesion = @sAdj, @nombre = N'QA A2 Adyacente', @fechaHoraInicio = @b1, @fechaHoraFin = @b3, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SES[_]017|%') <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sAdj AND fechaHoraInicio = @b2)
        THROW 58133, 'TEST FAILED: A2-T-09 mover una sesion sobre otra (v1 y v2) => SES_017 sin cambios.', 1;
    -- Solape heredado (dos sesiones ya cruzadas): renombrar sin cambiar el horario se acepta (N6).
    INSERT INTO dbo.Sesion (id, nombre, numero, codigo, numeroSemana, grupo, fechaHoraInicio, fechaHoraFin) VALUES
        (@sX, N'QA A2 X', 90, N'QAA2X', 1, @G2, DATEADD(DAY, 1, @b), DATEADD(DAY, 1, @b2)),
        (@sY, N'QA A2 Y', 91, N'QAA2Y', 1, @G2, DATEADD(DAY, 1, @b1), DATEADD(DAY, 1, @b3));
    DECLARE @inicioX DATETIME2 = DATEADD(DAY, 1, @b), @finX DATETIME2 = DATEADD(DAY, 1, @b2);
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_actualizar_sesion @idSesion = @sX, @nombre = N'QA A2 X renombrada', @fechaHoraInicio = @inicioX, @fechaHoraFin = @finX, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1) OR NOT EXISTS (SELECT 1 FROM dbo.Sesion WHERE id = @sX AND nombre = N'QA A2 X renombrada')
        THROW 58134, 'TEST FAILED: A2-T-09 renombrar una sesion con un solape heredado se acepta (N6).', 1;
    IF @@TRANCOUNT <> 1 THROW 58135, 'TEST FAILED: A2-T-09 altero el nivel de transaccion del llamador.', 1;
    PRINT 'TEST_PASS:CULM001A2_T09_SOLAPE_SESIONES';

    -- ======================================================= A2-T-10 / A2-T-11: retiro del reclamo propio y estado X
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c,
        @codigoEstado = N'P', @numeroPagina = 1, @tamanoPagina = 100;
    IF NOT EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia = @R1)
        THROW 58136, 'TEST FAILED: A2-T-11 precondicion: el reclamo pendiente figura en la bandeja del docente.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R1, @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REV[_]006|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Estado e ON e.id = r.estado WHERE r.id = @R1 AND e.codigo = 'P')
        THROW 58137, 'TEST FAILED: A2-T-10 retirar un reclamo ajeno => REV_006 sin cambios.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R1, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
        THROW 58138, 'TEST FAILED: A2-T-10 un perfil que no es estudiante => SEC_001.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R1, @idCorrelacion = @c, @idUsuarioEjecutor = @uE2;
    EXEC dbo.usp_obtener_mensaje_catalogo @p_codigo = 'REV_008', @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #r WHERE estadoResultado = 1 AND mensajeUsuarioResultado = @mu)
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Estado e ON e.id = r.estado WHERE r.id = @R1 AND e.codigo = 'X')
        THROW 58139, 'TEST FAILED: A2-T-10 el propietario retira su reclamo P => X con REV_008.', 1;
    TRUNCATE TABLE #r;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R1, @idCorrelacion = @c, @idUsuarioEjecutor = @uE2;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R2, @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    INSERT INTO #r EXEC dbo.usp_retirar_solicitud_revision_asistencia @idSolicitudRevision = @R3, @idCorrelacion = @c, @idUsuarioEjecutor = @uE1;
    IF (SELECT COUNT(*) FROM #r WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=REV[_]007|%') <> 3
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Estado e ON e.id = r.estado WHERE r.id = @R2 AND e.codigo = 'A')
       OR NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia r JOIN dbo.Estado e ON e.id = r.estado WHERE r.id = @R3 AND e.codigo = 'R')
        THROW 58140, 'TEST FAILED: A2-T-10 un reclamo X, A o R no se retira (REV_007) y no cambia.', 1;
    IF @@TRANCOUNT <> 1 THROW 58141, 'TEST FAILED: A2-T-10 altero el nivel de transaccion del llamador.', 1;
    PRINT 'TEST_PASS:CULM001A2_T10_RETIRO_RECLAMO';
    TRUNCATE TABLE #r2;
    INSERT INTO #r2 EXEC dbo.usp_consultar_solicitudes_revision_docente @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c,
        @codigoEstado = N'P', @numeroPagina = 1, @tamanoPagina = 100;
    IF EXISTS (SELECT 1 FROM #r2 WHERE idSolicitudRevisionAsistencia = @R1)
        THROW 58142, 'TEST FAILED: A2-T-11 un reclamo X no figura como pendiente en la bandeja del docente.', 1;
    IF EXISTS (SELECT 1 FROM sys.sql_expression_dependencies d
               WHERE OBJECT_NAME(d.referencing_id) LIKE N'usp[_]consultar[_]kpis[_]%'
                 AND d.referenced_entity_name IN (N'SolicitudRevisionAsistencia', N'uv_solicitud_revision_asistencia', N'uv_auth_solicitud_revision_asistencia'))
        THROW 58143, 'TEST FAILED: A2-T-11 un KPI que cuente reclamos debe tratar X explicitamente (revisar).', 1;
    PRINT 'TEST_PASS:CULM001A2_T11_RECLAMO_X_NO_CONTAMINA';

    -- ======================================================= A2-T-12: estado del decano (casos sin THROW)
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kD, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin1;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 1 AND estaActivoDecano = 0 AND personaSinRolesActivos = 0 AND idUsuario = @uDecD)
       OR NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @kD AND estado = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uDecD AND estado = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.uv_decano WHERE id = @kD AND estaActivoDecano = 0)
        THROW 58144, 'TEST FAILED: A2-T-12 desactivar al decano sin programas activos; con otro rol activo conserva Usuario.estado = 1.', 1;
    IF EXISTS (SELECT 1 FROM dbo.uv_usuario_perfil WHERE idUsuario = @uDecD AND codigoPerfil = 'DE')
        THROW 58145, 'TEST FAILED: A2-T-12 un decano desactivado no figura como perfil DE.', 1;
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecD, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF @ok <> 0 OR @mt NOT LIKE N'DBCODE=SEC[_]001|%'
        THROW 58146, 'TEST FAILED: A2-T-12 el RBAC DECANO rechaza al decano desactivado (SEC_001).', 1;
    TRUNCATE TABLE #dec;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kD, @estaActivo = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin1;
    EXEC dbo.usp_validar_permiso_rbac_usuario_interno @idUsuario = @uDecD, @codigoPerfilRequerido = 'DECANO', @idCorrelacion = @c,
        @mensajeUsuarioResultado = @mu OUTPUT, @mensajeTecnicoResultado = @mt OUTPUT, @estadoResultado = @ok OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 1 AND estaActivoDecano = 1) OR @ok <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @kD AND estado = 1)
        THROW 58147, 'TEST FAILED: A2-T-12 @estaActivo NULL invierte el estado (reactiva) y el RBAC vuelve a pasar.', 1;
    TRUNCATE TABLE #dec;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kE, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin1;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 1 AND personaSinRolesActivos = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uDecE AND estado = 0)
        THROW 58148, 'TEST FAILED: A2-T-12 sin otro rol activo, la persona queda inactiva (D1).', 1;
    TRUNCATE TABLE #dec;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kE, @estaActivo = 1, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin1;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 1 AND estaActivoDecano = 1)
       OR NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE id = @uDecE AND estado = 1)
        THROW 58149, 'TEST FAILED: A2-T-12 al reactivar, Usuario.estado vuelve a 1.', 1;
    TRUNCATE TABLE #dec;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kA, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin1;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=DEC[_]002|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @kA AND estado = 1)
        THROW 58150, 'TEST FAILED: A2-T-12 el decano de una facultad con programas activos no se desactiva (DEC_002).', 1;
    TRUNCATE TABLE #dec;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kD, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uAdmin2;
    INSERT INTO #dec EXEC dbo.usp_cambiar_estado_decano @idDecano = @kD, @estaActivo = 0, @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=DEC[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM #dec WHERE estadoResultado = 0 AND mensajeTecnicoResultado LIKE N'DBCODE=SEC[_]001|%')
       OR NOT EXISTS (SELECT 1 FROM dbo.Decano WHERE id = @kD AND estado = 1)
        THROW 58151, 'TEST FAILED: A2-T-12 administrador de otra institucion => DEC_001; no administrador => SEC_001.', 1;
    PRINT 'TEST_PASS:CULM001A2_T12_ESTADO_DECANO';

    -- ======================================================= A2-T-13: semillas 33
    IF (SELECT COUNT(*) FROM dbo.CatalogoParametro p
        INNER JOIN (VALUES ('MATRICULA', 'ESTADO_RETIRADA', N'I'), ('MATRICULA', 'ESTADO_INSCRITA', N'A'),
                           ('ARCHIVOS', 'LIMITE_SUBIDAS_POR_MINUTO', N'10'), ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO', N'20'),
                           ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO', N'5'), ('RECLAMO', 'ESTADO_PENDIENTE', N'P'),
                           ('RECLAMO', 'ESTADO_RETIRADO', N'X')) v (g, k, val)
            ON p.grupo = v.g AND p.clave = v.k AND p.valor = v.val AND p.valorDefecto = v.val) <> 7
        THROW 58152, 'TEST FAILED: A2-T-13 los 7 parametros sembrados por A deben tener valor = valor por defecto del backend.', 1;
    IF (SELECT COUNT(*) FROM dbo.CatalogoMensajeUsuario WHERE codigo IN ('SES_017', 'REV_006', 'REV_007', 'REV_008', 'DEC_002', 'DEC_003')) <> 6
       OR (SELECT COUNT(*) FROM dbo.CatalogoMensajeTecnico WHERE codigo IN ('SES_017', 'REV_006', 'REV_007', 'REV_008', 'DEC_002', 'DEC_003')) <> 6
        THROW 58153, 'TEST FAILED: A2-T-13 los 6 mensajes de A.2 existen en usuario y tecnico.', 1;
    PRINT 'TEST_PASS:CULM001A2_T13_SEMILLAS_33';

    -- ======================================================= A2-T-14: grants (8 SP publicos nuevos; el interno sin EXECUTE)
    IF (SELECT COUNT(*) FROM sys.database_permissions dp
        WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND dp.permission_name = N'EXECUTE' AND dp.state IN ('G', 'W')
          AND dp.major_id IN (OBJECT_ID(N'dbo.usp_consultar_directorio_estudiantes_paginado'), OBJECT_ID(N'dbo.usp_consultar_estudiantes_grupo_ambito_paginado'),
                              OBJECT_ID(N'dbo.usp_consultar_asistencias_grupo_ambito_paginado'), OBJECT_ID(N'dbo.usp_consultar_materias_estudiante'),
                              OBJECT_ID(N'dbo.usp_consultar_horario_estudiante'), OBJECT_ID(N'dbo.usp_retirar_solicitud_revision_asistencia'),
                              OBJECT_ID(N'dbo.usp_cambiar_estado_decano'), OBJECT_ID(N'dbo.usp_buscar_estudiante_por_documento_grupo'))) <> 8
       OR EXISTS (SELECT 1 FROM sys.database_permissions dp
                  WHERE dp.grantee_principal_id = DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') AND dp.state IN ('G', 'W')
                    AND dp.major_id IN (OBJECT_ID(N'dbo.usp_validar_solape_sesion_interno'), OBJECT_ID(N'dbo.usp_internal_reactivar_matricula_retirada')))
        THROW 58154, 'TEST FAILED: A2-T-14 EXECUTE del runtime sobre los 8 SP publicos nuevos y ninguno sobre los internos.', 1;
    PRINT 'TEST_PASS:CULM001A2_T14_GRANTS';

    -- ======================================================= A2-T-17: busqueda por documento (casos sin THROW)
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000031,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF (SELECT COUNT(*) FROM #bus) <> 1
       OR NOT EXISTS (SELECT 1 FROM #bus WHERE idEstudiante = @E1 AND codigoEstadoMatriculaGrupo = N'A' AND correoEnmascarado = N'c***@test.local')
       OR EXISTS (SELECT 1 FROM #bus WHERE correoEnmascarado LIKE N'%culm001a2%')
        THROW 58155, 'TEST FAILED: A2-T-17 el titular encuentra a E1 por documento exacto con correo enmascarado y su matricula A.', 1;
    TRUNCATE TABLE #bus;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000033,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000035,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF (SELECT COUNT(*) FROM #bus) <> 2 OR NOT EXISTS (SELECT 1 FROM #bus WHERE idEstudiante = @E3 AND codigoEstadoMatriculaGrupo = N'I')
       OR NOT EXISTS (SELECT 1 FROM #bus WHERE idEstudiante = @E5 AND codigoEstadoMatriculaGrupo IS NULL)
        THROW 58156, 'TEST FAILED: A2-T-17 matricula I y estudiante sin vinculos (alta pendiente, A2-C1) se encuentran.', 1;
    TRUNCATE TABLE #bus;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000036,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987999999,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 198700003,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000017,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    INSERT INTO #bus EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = @G1, @idTipoIdentificacion = @tipoCC, @numeroIdentificacion = 1987000013,
        @idCorrelacion = @c, @idUsuarioEjecutor = @uDocT;
    IF (SELECT COUNT(*) FROM #bus) <> 0
        THROW 58157, 'TEST FAILED: A2-T-17 otra institucion, documento inexistente, parcial y usuarios sin fila Estudiante dan 0 filas.', 1;
    PRINT 'TEST_PASS:CULM001A2_T17_BUSQUEDA_DOCUMENTO';

    -- ======================================================= A2-T-06b: @tamanoPagina sin limite solo en los SP de grupo
    DECLARE @G4 UNIQUEIDENTIFIER = NEWID(), @estA UNIQUEIDENTIFIER = (SELECT id FROM dbo.EstadoEstudianteGrupo WHERE codigo = N'A');
    INSERT INTO dbo.Grupo (id, asignatura, periodoAcademico, codigo, nombre, cantidadEstudiantes, cantidadEstudiantesFinalizaron,
        cantidadEstudiantesCancelaronVoluntadPropia, cantidadEstudiantesCancelaronAutomaticamente, docente)
    SELECT IIF(x.n = 1, @G4, NEWID()), CAST(@p + '6E' AS UNIQUEIDENTIFIER), CAST(@p + '71' AS UNIQUEIDENTIFIER), 760000 + x.n,
           CONCAT(N'QA A2 Masivo ', x.n), 200, 0, 0, 0, CAST(@p + '36' AS UNIQUEIDENTIFIER)
    FROM (SELECT TOP 101 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) x;
    CREATE TABLE #m (n INT, u UNIQUEIDENTIFIER, e UNIQUEIDENTIFIER);
    INSERT INTO #m (n, u, e) SELECT TOP 101 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), NEWID(), NEWID() FROM sys.all_objects;
    INSERT INTO dbo.Usuario (id, tipoIdIdentificacion, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre, correo, correoConfirmado, estado, password)
    SELECT m.u, @tipoCC, 1986000000 + m.n, N'Masivo', N'Qa', N'Est', N'A', CONCAT(N'culm001a2.masivo.', m.n, N'@test.local'), 1, 1, N'HashBackend_A2' FROM #m m;
    INSERT INTO dbo.Estudiante (id, usuario) SELECT m.e, m.u FROM #m m;
    INSERT INTO dbo.EstudianteGrupo (id, estado, estudiante, grupo) SELECT NEWID(), @estA, m.e, @G4 FROM #m m;
    TRUNCATE TABLE #eg;
    INSERT INTO #eg EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = @G4, @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @tamanoPagina = NULL;
    IF (SELECT COUNT(*) FROM #eg) <> 101
        THROW 58158, 'TEST FAILED: A2-T-06b @tamanoPagina NULL devuelve todas las filas (101).', 1;
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @tamanoPagina = NULL;
    SET @n = (SELECT COUNT(*) FROM #dl);
    TRUNCATE TABLE #dl;
    INSERT INTO #dl (id, idUsuario, tipoIdentificacionId, numeroIdentificacion, primerApellido, segundoApellido, primerNombre, segundoNombre,
        nombreCompleto, correo, estaActivoUsuario, totalRegistros)
    EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @tamanoPagina = 500;
    IF @n > 100 OR (SELECT COUNT(*) FROM #dl) <> 100 OR (SELECT MAX(totalRegistros) FROM #dl) < 104
        THROW 58159, 'TEST FAILED: A2-T-06b el directorio acota el tamano (NULL o 500 => como mucho 100).', 1;
    -- Columnas de usp_consultar_grupos_paginado (las mismas de test_usp_consultar_grupos_paginado.sql).
    CREATE TABLE #g (id UNIQUEIDENTIFIER, codigo INT, nombre NVARCHAR(100), idAsignatura UNIQUEIDENTIFIER, nombreAsignatura NVARCHAR(100),
        idDocente UNIQUEIDENTIFIER, capacidadMaximaPermitida INT, estudiantesActivos INT, cuposDisponibles INT, grupoEstaHablitado BIT,
        fechaInicioPeriodoAcademico DATETIME2, fechaFinPeriodoAcademico DATETIME2, totalRegistros INT);
    INSERT INTO #g EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @tamanoPagina = NULL;
    SET @n = (SELECT COUNT(*) FROM #g);
    DELETE FROM #g;
    INSERT INTO #g EXEC dbo.usp_consultar_grupos_paginado @idUsuarioEjecutor = @uDocT, @idCorrelacion = @c, @tamanoPagina = 500;
    IF @n > 100 OR (SELECT COUNT(*) FROM #g) > 100
        THROW 58160, 'TEST FAILED: A2-T-06b usp_consultar_grupos_paginado acota el tamano (como mucho 100).', 1;
    PRINT 'TEST_PASS:CULM001A2_T06B_TAMANO_SIN_LIMITE_SOLO_GRUPO';

    IF @@TRANCOUNT <> 1 THROW 58198, 'TEST FAILED: CULM001A2 el objeto altero el nivel de transaccion del llamador.', 1;
    ROLLBACK TRANSACTION;
    PRINT '-> Rollback transaccional ejecutado. Cero residuos.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT CONCAT('ERROR EN TEST: ', ERROR_MESSAGE());
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 58199, 'TEST FAILED: CULM001A2 dejo transacciones abiertas.', 1;
GO

-- ---------------------------------------------------------------------------
-- Rechazos por THROW (cada uno en su transaccion con la fixture): VAL_001, SEC_002, KPI_003.
-- ---------------------------------------------------------------------------
DECLARE @p NVARCHAR(40) = N'C1A20000-0000-4000-8000-0000000000';
DECLARE @tipo NVARCHAR(36) = (SELECT TOP 1 CONVERT(NVARCHAR(36), id) FROM dbo.TipoIdentificacion WHERE tipoIdentificacion = 'CC');
DECLARE @pre NVARCHAR(200) = N'DECLARE @c UNIQUEIDENTIFIER = NEWID(); ';
DECLARE @t TABLE (n INT IDENTITY(1,1), etiqueta NVARCHAR(100), sqlText NVARCHAR(MAX), codigo VARCHAR(30));
INSERT @t (etiqueta, sqlText, codigo) VALUES
 (N'A2-T-01 directorio ejecutor nulo', @pre + N'EXEC dbo.usp_consultar_directorio_estudiantes_paginado @idUsuarioEjecutor = NULL, @idCorrelacion = @c;', 'VAL_001'),
 (N'A2-T-06 estudiantes grupo docente ajeno', @pre + N'EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = ''' + @p + N'17'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-06 estudiantes grupo coordinador de otro programa', @pre + N'EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = ''' + @p + N'14'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-06 estudiantes grupo administrador de otra institucion', @pre + N'EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = ''' + @p + N'12'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-06 estudiantes grupo inexistente', @pre + N'EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = ''' + @p + N'FF'', @idUsuarioEjecutor = ''' + @p + N'16'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-06 estudiantes grupo ejecutor nulo', @pre + N'EXEC dbo.usp_consultar_estudiantes_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = NULL, @idCorrelacion = @c;', 'VAL_001'),
 (N'A2-T-07 asistencias grupo docente ajeno', @pre + N'EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = ''' + @p + N'17'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-07 asistencias grupo coordinador de otro programa', @pre + N'EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = ''' + @p + N'73'', @idUsuarioEjecutor = ''' + @p + N'14'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-07 asistencias grupo inexistente', @pre + N'EXEC dbo.usp_consultar_asistencias_grupo_ambito_paginado @idGrupo = ''' + @p + N'FF'', @idUsuarioEjecutor = ''' + @p + N'16'', @idCorrelacion = @c;', 'SEC_002'),
 (N'A2-T-08 materias ejecutor nulo', @pre + N'EXEC dbo.usp_consultar_materias_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @c;', 'VAL_001'),
 (N'A2-T-08 horario ejecutor nulo', @pre + N'EXEC dbo.usp_consultar_horario_estudiante @idUsuarioEjecutor = NULL, @idCorrelacion = @c;', 'VAL_001'),
 (N'A2-T-12 kpis del decano desactivado', @pre + N'UPDATE dbo.Decano SET estado = 0 WHERE id = ''' + @p + N'4B''; EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = ''' + @p + N'1B'', @idCorrelacion = @c;', 'KPI_003'),
 (N'A2-T-12 kpis del decano activo', @pre + N'DECLARE @k TABLE (x INT); EXEC dbo.usp_consultar_kpis_decano @idUsuarioEjecutor = ''' + @p + N'1B'', @idCorrelacion = @c;', NULL),
 (N'A2-T-17 busqueda docente no titular', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = 1987000031, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'17'';', 'SEC_002'),
 (N'A2-T-17 busqueda coordinador', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = 1987000031, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'13'';', 'SEC_002'),
 (N'A2-T-17 busqueda grupo inexistente', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'FF'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = 1987000031, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'16'';', 'SEC_002'),
 (N'A2-T-17 busqueda documento nulo', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = NULL, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'16'';', 'VAL_001'),
 (N'A2-T-17 busqueda documento cero', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = 0, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'16'';', 'VAL_001'),
 (N'A2-T-17 busqueda tipo nulo', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = NULL, @numeroIdentificacion = 1987000031, @idCorrelacion = @c, @idUsuarioEjecutor = ''' + @p + N'16'';', 'VAL_001'),
 (N'A2-T-17 busqueda ejecutor nulo', @pre + N'EXEC dbo.usp_buscar_estudiante_por_documento_grupo @idGrupo = ''' + @p + N'73'', @idTipoIdentificacion = ''' + @tipo + N''', @numeroIdentificacion = 1987000031, @idCorrelacion = @c, @idUsuarioEjecutor = NULL;', 'VAL_001');
DECLARE @i INT = 1, @max INT = (SELECT COUNT(*) FROM @t), @e NVARCHAR(100), @s NVARCHAR(MAX), @cod VARCHAR(30);
WHILE @i <= @max
BEGIN
    SELECT @e = etiqueta, @s = sqlText, @cod = codigo FROM @t WHERE n = @i;
    EXEC #a2_expect @etiqueta = @e, @sql = @s, @codigo = @cod;
    SET @i += 1;
END
IF @@TRANCOUNT <> 0 THROW 58197, 'TEST FAILED: CULM001A2 los rechazos dejaron transacciones abiertas.', 1;
PRINT 'TEST_PASS:CULM001A2_RECHAZOS_THROW';
GO

DROP PROCEDURE IF EXISTS #a2_expect;
DROP PROCEDURE IF EXISTS #a2_fixture;
IF @@TRANCOUNT <> 0 THROW 58196, 'TEST FAILED: test_culm001_a_correcciones dejo transacciones abiertas.', 1;
PRINT 'TEST END: test_culm001_a_correcciones';
GO
