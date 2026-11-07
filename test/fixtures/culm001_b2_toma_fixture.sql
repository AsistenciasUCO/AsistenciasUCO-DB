USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 B.2 (CONTRACT §2.16.3, [SUPUESTO-B-20]): helper de pruebas para la columna obligatoria DetalleAsistencia.toma.
-- Procedimientos TEMPORALES (#...): viven solo en la sesion de sqlcmd que carga este archivo (test_suite.sql lo carga al
-- inicio), no aparecen en sys.procedures de la BD y no requieren permisos ni limpieza.
--   #culm001_b2_crear_toma @idSesion, @idToma OUTPUT   -> devuelve la toma 1 de la sesion; si no existe la crea como la crea
--                                                         el backfill: MANUAL (usaCodigoQr = 0), CERRADA (estaAbierta = 0),
--                                                         esImplicita = 1, docente del grupo, apertura = inicio, cierre = fin.
--   #culm001_b2_crear_tomas @sesionesJSON              -> lo mismo para un conjunto [{"idSesion":"uuid"}, ...].
--   #culm001_b2_limpiar_sesiones @sesionesJSON         -> borra, en este orden, DetalleAsistencia -> TokenAsistenciaToma ->
--                                                         TomaAsistencia -> SesionCancelacion -> Asistencia de esas sesiones
--                                                         (las filas que dependan de Asistencia las borra antes el llamador);
--                                                         el DELETE de dbo.Sesion lo hace el llamador.
-- Las pruebas que se ejecutan fuera de test_suite.sql (fixtures maint_003g y dev_pagination) llevan el mismo orden de
-- borrado en linea, porque no comparten esta sesion.
IF OBJECT_ID(N'tempdb..#culm001_b2_crear_toma') IS NOT NULL DROP PROCEDURE #culm001_b2_crear_toma;
GO
CREATE PROCEDURE #culm001_b2_crear_toma
    @idSesion UNIQUEIDENTIFIER,
    @idToma   UNIQUEIDENTIFIER = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @idToma = (SELECT t.id FROM dbo.TomaAsistencia t WHERE t.sesion = @idSesion AND t.numero = 1);
    IF @idToma IS NULL
    BEGIN
        SET @idToma = NEWID();
        INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc,
                                        fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
        SELECT @idToma, s.id, 1,
               (SELECT m.id FROM dbo.ModoTomaAsistencia m WHERE m.usaCodigoQr = 0),
               (SELECT e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0),
               1, g.docente, CAST(s.fechaHoraInicio AS DATETIME2(0)),
               CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio, s.fechaHoraFin, s.fechaHoraInicio) AS DATETIME2(0)),
               0, NEWID(), NULL
        FROM dbo.Sesion s
        INNER JOIN dbo.Grupo g ON g.id = s.grupo
        WHERE s.id = @idSesion;
        IF @@ROWCOUNT <> 1
            THROW 57900, 'CULM001_B2_FIXTURE: #culm001_b2_crear_toma recibio una sesion inexistente.', 1;
    END
END;
GO

IF OBJECT_ID(N'tempdb..#culm001_b2_crear_tomas') IS NOT NULL DROP PROCEDURE #culm001_b2_crear_tomas;
GO
CREATE PROCEDURE #culm001_b2_crear_tomas
    @sesionesJSON NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.TomaAsistencia (id, sesion, numero, modo, estado, esImplicita, docenteApertura, fechaAperturaUtc,
                                    fechaCierreUtc, totalAusentesMarcados, idCorrelacionApertura, idCorrelacionCierre)
    SELECT NEWID(), s.id, 1,
           (SELECT m.id FROM dbo.ModoTomaAsistencia m WHERE m.usaCodigoQr = 0),
           (SELECT e.id FROM dbo.EstadoTomaAsistencia e WHERE e.estaAbierta = 0),
           1, g.docente, CAST(s.fechaHoraInicio AS DATETIME2(0)),
           CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio, s.fechaHoraFin, s.fechaHoraInicio) AS DATETIME2(0)),
           0, NEWID(), NULL
    FROM dbo.Sesion s
    INNER JOIN dbo.Grupo g ON g.id = s.grupo
    WHERE s.id IN (SELECT j.idSesion FROM OPENJSON(@sesionesJSON) WITH (idSesion UNIQUEIDENTIFIER '$.idSesion') j)
      AND NOT EXISTS (SELECT 1 FROM dbo.TomaAsistencia t WHERE t.sesion = s.id AND t.numero = 1);
END;
GO

IF OBJECT_ID(N'tempdb..#culm001_b2_limpiar_sesiones') IS NOT NULL DROP PROCEDURE #culm001_b2_limpiar_sesiones;
GO
CREATE PROCEDURE #culm001_b2_limpiar_sesiones
    @sesionesJSON NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @s TABLE (id UNIQUEIDENTIFIER PRIMARY KEY);
    INSERT INTO @s (id)
    SELECT DISTINCT j.idSesion FROM OPENJSON(@sesionesJSON) WITH (idSesion UNIQUEIDENTIFIER '$.idSesion') j WHERE j.idSesion IS NOT NULL;

    DELETE da FROM dbo.DetalleAsistencia da INNER JOIN dbo.Asistencia a ON a.id = da.asistencia WHERE a.sesion IN (SELECT id FROM @s);
    DELETE da FROM dbo.DetalleAsistencia da INNER JOIN dbo.TomaAsistencia t ON t.id = da.toma WHERE t.sesion IN (SELECT id FROM @s);
    DELETE tk FROM dbo.TokenAsistenciaToma tk INNER JOIN dbo.TomaAsistencia t ON t.id = tk.toma WHERE t.sesion IN (SELECT id FROM @s);
    DELETE FROM dbo.TomaAsistencia WHERE sesion IN (SELECT id FROM @s);
    DELETE FROM dbo.SesionCancelacion WHERE sesion IN (SELECT id FROM @s);
    DELETE a FROM dbo.Asistencia a
    WHERE a.sesion IN (SELECT id FROM @s)
      AND NOT EXISTS (SELECT 1 FROM dbo.SolicitudRevisionAsistencia sra WHERE sra.asistencia = a.id);
END;
GO

PRINT 'CULM001_B2_TOMA_FIXTURE_LOADED';
GO
