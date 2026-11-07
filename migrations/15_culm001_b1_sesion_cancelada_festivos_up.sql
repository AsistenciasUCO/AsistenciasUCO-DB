USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP 15: CULM-001 B.1 - sesion cancelada, dias festivos y ventana con tolerancia (CONTRACT §2.14)
-- Crea TipoCancelacionSesion, DiaFestivo, CargaDiaFestivo y SesionCancelacion con sus indices y FKs (IF OBJECT_ID ...
-- IS NULL), siembra las 2 filas de TipoCancelacionSesion (MERGE por id), crea o altera las vistas de B.1 y concede
-- SELECT sobre ellas. Idempotente. No carga festivos: la BD no llama a internet; tras desplegar B.1 el job del backend
-- carga el anio actual y el siguiente y los aplica ([SUPUESTO-B-21]). Los SP, semillas y permisos de B.1 los despliega
-- deploy_schema.ps1 (CREATE OR ALTER / MERGE).
-- ============================================================================
PRINT 'MIGRACION 15 UP: tablas de B.1';
GO
-- CULM-001 B.1 (CONTRACT §2.1): catalogo del tipo de cancelacion de una sesion. Los SP distinguen el tipo por la
-- bandera esAutomatica (1 = la crea el sistema por un dia festivo; 0 = la decide el docente), nunca por el codigo.
-- Exactamente un tipo por bandera (UQ_TipoCancelacionSesion_esAutomatica). Filas en la semilla 34 (ids fijos).
IF OBJECT_ID('dbo.[TipoCancelacionSesion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.TipoCancelacionSesion (
        id            UNIQUEIDENTIFIER NOT NULL,
        codigo        NVARCHAR(20)     NOT NULL,
        nombre        NVARCHAR(50)     NOT NULL,
        esAutomatica  BIT              NOT NULL,
        CONSTRAINT PK_TipoCancelacionSesion PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_TipoCancelacionSesion_codigo UNIQUE (codigo),
        CONSTRAINT UQ_TipoCancelacionSesion_esAutomatica UNIQUE (esAutomatica)
    );
END
GO
-- CULM-001 B.1 (CONTRACT §2.2): SSOT de los dias festivos nacionales. La BD nunca llama a internet: el backend obtiene
-- el listado (proveedor principal, respaldo o calculo local) y lo carga con usp_cargar_dias_festivos[_automatico].
-- Una fila por fecha; una recarga que ya no trae un festivo lo desactiva (estaActivo = 0), nunca lo borra, porque
-- dbo.SesionCancelacion puede referenciarlo. fuente: valor de FESTIVOS/FUENTES_VALIDAS (validado en el SP).
IF OBJECT_ID('dbo.[DiaFestivo]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DiaFestivo (
        id                  UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_DiaFestivo_id DEFAULT NEWID(),
        fecha               DATE             NOT NULL,
        anio                AS CAST(YEAR(fecha) AS SMALLINT) PERSISTED,
        nombre              NVARCHAR(120)    NOT NULL,
        fuente              NVARCHAR(40)     NOT NULL,
        estaActivo          BIT              NOT NULL CONSTRAINT DF_DiaFestivo_estaActivo DEFAULT 1,
        fechaCargaUtc       DATETIME2(0)     NOT NULL,
        idCorrelacionCarga  UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_DiaFestivo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT UQ_DiaFestivo_fecha UNIQUE (fecha),
        CONSTRAINT CK_DiaFestivo_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.DiaFestivo') AND name = 'IX_DiaFestivo_anio')
    CREATE NONCLUSTERED INDEX IX_DiaFestivo_anio ON dbo.DiaFestivo (anio, estaActivo) INCLUDE (fecha, nombre, fuente);
GO
-- CULM-001 B.1 (CONTRACT §2.2): bitacora de cada carga anual de festivos (fuente, fecha, conteos y diferencias con el
-- calculo local, que calcula el backend). usuarioEjecutor NULL = job automatico.
IF OBJECT_ID('dbo.[CargaDiaFestivo]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CargaDiaFestivo (
        id                        UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_CargaDiaFestivo_id DEFAULT NEWID(),
        anio                      SMALLINT         NOT NULL,
        fuente                    NVARCHAR(40)     NOT NULL,
        totalFestivos             INT              NOT NULL,
        festivosInsertados        INT              NOT NULL,
        festivosActualizados      INT              NOT NULL,
        festivosDesactivados      INT              NOT NULL,
        diferenciasCalculoLocal   INT              NOT NULL,
        usuarioEjecutor           UNIQUEIDENTIFIER NULL,
        fechaCargaUtc             DATETIME2(0)     NOT NULL,
        idCorrelacion             UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_CargaDiaFestivo PRIMARY KEY CLUSTERED (id),
        CONSTRAINT CK_CargaDiaFestivo_conteos CHECK (totalFestivos >= 0 AND festivosInsertados >= 0 AND festivosActualizados >= 0
                                                    AND festivosDesactivados >= 0 AND diferenciasCalculoLocal >= 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.CargaDiaFestivo') AND name = 'IX_CargaDiaFestivo_anio_fecha')
    CREATE NONCLUSTERED INDEX IX_CargaDiaFestivo_anio_fecha ON dbo.CargaDiaFestivo (anio, fechaCargaUtc DESC);
GO
-- CULM-001 B.1 (CONTRACT §2.2): cancelacion de una sesion (1:0..1 con dbo.Sesion, que no se modifica: su guard 50004
-- prohibe columnas de estado). La crea usp_cancelar_sesion (tipo manual, HU047) o usp_internal_aplicar_festivos_grupo
-- (tipo automatico FESTIVO, con diaFestivo). usuarioEjecutor NULL solo en cancelaciones automaticas del job.
-- La coherencia tipo automatico <=> diaFestivo NOT NULL la garantizan los SP (invariante INV_SESION_CANCELACION_COHERENTE).
IF OBJECT_ID('dbo.[SesionCancelacion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.SesionCancelacion (
        sesion               UNIQUEIDENTIFIER NOT NULL,
        tipoCancelacion      UNIQUEIDENTIFIER NOT NULL,
        motivo               NVARCHAR(500)    NOT NULL,
        diaFestivo           UNIQUEIDENTIFIER NULL,
        usuarioEjecutor      UNIQUEIDENTIFIER NULL,
        fechaCancelacionUtc  DATETIME2(0)     NOT NULL CONSTRAINT DF_SesionCancelacion_fecha DEFAULT SYSUTCDATETIME(),
        idCorrelacion        UNIQUEIDENTIFIER NOT NULL,
        CONSTRAINT PK_SesionCancelacion PRIMARY KEY CLUSTERED (sesion),
        CONSTRAINT CK_SesionCancelacion_motivo CHECK (LEN(LTRIM(RTRIM(motivo))) > 0),
        CONSTRAINT CK_SesionCancelacion_origen CHECK (diaFestivo IS NOT NULL OR usuarioEjecutor IS NOT NULL)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.SesionCancelacion') AND name = 'IX_SesionCancelacion_diaFestivo')
    CREATE NONCLUSTERED INDEX IX_SesionCancelacion_diaFestivo ON dbo.SesionCancelacion (diaFestivo) WHERE diaFestivo IS NOT NULL;
GO
-- CULM-001 B.1 (CONTRACT §2.2): sesion cancelada y dias festivos
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_Sesion')
BEGIN
    ALTER TABLE [dbo].[SesionCancelacion] ADD CONSTRAINT [FK_SesionCancelacion_Sesion] FOREIGN KEY ([sesion]) REFERENCES [dbo].[Sesion] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_TipoCancelacionSesion')
BEGIN
    ALTER TABLE [dbo].[SesionCancelacion] ADD CONSTRAINT [FK_SesionCancelacion_TipoCancelacionSesion] FOREIGN KEY ([tipoCancelacion]) REFERENCES [dbo].[TipoCancelacionSesion] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_DiaFestivo')
BEGIN
    ALTER TABLE [dbo].[SesionCancelacion] ADD CONSTRAINT [FK_SesionCancelacion_DiaFestivo] FOREIGN KEY ([diaFestivo]) REFERENCES [dbo].[DiaFestivo] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_SesionCancelacion_Usuario')
BEGIN
    ALTER TABLE [dbo].[SesionCancelacion] ADD CONSTRAINT [FK_SesionCancelacion_Usuario] FOREIGN KEY ([usuarioEjecutor]) REFERENCES [dbo].[Usuario] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CargaDiaFestivo_Usuario')
BEGIN
    ALTER TABLE [dbo].[CargaDiaFestivo] ADD CONSTRAINT [FK_CargaDiaFestivo_Usuario] FOREIGN KEY ([usuarioEjecutor]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

PRINT 'MIGRACION 15 UP: catalogo TipoCancelacionSesion';
GO
-- CULM-001 B.1 (CONTRACT §2.1): catalogo TipoCancelacionSesion con ids fijos (patron 08_razon_causa.sql). Idempotente.
-- Los SP lo resuelven por la bandera esAutomatica, nunca por el codigo.
MERGE INTO [dbo].[TipoCancelacionSesion] AS Target
USING (VALUES
    (CAST('7C1E0B10-5E51-4C0A-9A01-000000000001' AS UNIQUEIDENTIFIER), N'DOCENTE', N'Cancelada por el docente', CAST(0 AS BIT)),
    (CAST('7C1E0B10-5E51-4C0A-9A01-000000000002' AS UNIQUEIDENTIFIER), N'FESTIVO', N'Día festivo',              CAST(1 AS BIT))
) AS Source (id, codigo, nombre, esAutomatica)
ON (Target.id = Source.id)
WHEN MATCHED THEN
    UPDATE SET Target.codigo = Source.codigo, Target.nombre = Source.nombre, Target.esAutomatica = Source.esAutomatica
WHEN NOT MATCHED THEN
    INSERT (id, codigo, nombre, esAutomatica)
    VALUES (Source.id, Source.codigo, Source.nombre, Source.esAutomatica);
GO
-- CULM-001 B.1 (CONTRACT §2.1): vista de catalogo (solo consulta, patron CAT-01) del tipo de cancelacion de sesion.
CREATE OR ALTER VIEW [dbo].[uv_tipo_cancelacion_sesion]
AS
SELECT  id = t.id,
        codigo = t.codigo,
        nombre = t.nombre,
        esAutomatica = t.esAutomatica
FROM    dbo.TipoCancelacionSesion t;
GO
-- CULM-001 B.1 (CONTRACT §2.5): dias festivos nacionales cargados (activos e inactivos).
CREATE OR ALTER VIEW [dbo].[uv_dia_festivo]
AS
SELECT  id = df.id,
        fecha = df.fecha,
        anio = df.anio,
        nombre = df.nombre,
        fuente = df.fuente,
        estaActivo = df.estaActivo,
        fechaCargaUtc = df.fechaCargaUtc,
        idCorrelacionCarga = df.idCorrelacionCarga
FROM    dbo.DiaFestivo df;
GO
-- CULM-001 B.1 (CONTRACT §2.5): bitacora de cargas de festivos; esUltimaCargaAnio = 1 en la carga mas reciente del anio.
CREATE OR ALTER VIEW [dbo].[uv_carga_dia_festivo]
AS
SELECT  id = c.id,
        anio = c.anio,
        fuente = c.fuente,
        totalFestivos = c.totalFestivos,
        festivosInsertados = c.festivosInsertados,
        festivosActualizados = c.festivosActualizados,
        festivosDesactivados = c.festivosDesactivados,
        diferenciasCalculoLocal = c.diferenciasCalculoLocal,
        idUsuarioEjecutor = c.usuarioEjecutor,
        fechaCargaUtc = c.fechaCargaUtc,
        idCorrelacion = c.idCorrelacion,
        esUltimaCargaAnio = CAST(IIF(ROW_NUMBER() OVER (PARTITION BY c.anio ORDER BY c.fechaCargaUtc DESC, c.id DESC) = 1, 1, 0) AS BIT)
FROM    dbo.CargaDiaFestivo c;
GO
-- CULM-001 B.1 (CONTRACT §2.5): una fila por sesion (sobre uv_sesion_v2, que no se modifica) con su estado de
-- cancelacion (dbo.SesionCancelacion, LEFT) y la ventana de registro con tolerancia:
--   ventanaAperturaUtc = inicio - ASISTENCIA/TOLERANCIA_MINUTOS (NULL si la procedencia temporal es INDETERMINADA)
--   ventanaCierreUtc   = fin + ASISTENCIA/MARGEN_RETARDO_MINUTOS
--   ventanaAbierta     = no cancelada, procedencia confirmada y apertura <= SYSUTCDATETIME() < cierre
-- Los dos parametros se leen una sola vez (CROSS APPLY); un parametro ausente o negativo vale 0 (regla estricta).
-- horasSesion = minutos de la sesion / 60 (0 si fin <= inicio). B.2 agrega totalTomas, tieneTomaAbierta, idTomaAbierta.
CREATE OR ALTER VIEW [dbo].[uv_sesion_estado]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        numero = s.numero,
        nombre = s.nombre,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        procedenciaTemporal = s.procedenciaTemporal,
        estaCancelada = CAST(IIF(sc.sesion IS NULL, 0, 1) AS BIT),
        idTipoCancelacion = tc.id,
        codigoTipoCancelacion = tc.codigo,
        nombreTipoCancelacion = tc.nombre,
        esCancelacionAutomatica = tc.esAutomatica,
        motivoCancelacion = sc.motivo,
        idDiaFestivo = sc.diaFestivo,
        nombreDiaFestivo = df.nombre,
        fechaCancelacionUtc = sc.fechaCancelacionUtc,
        idUsuarioCancelacion = sc.usuarioEjecutor,
        ventanaAperturaUtc = IIF(s.procedenciaTemporal IS NULL, NULL, DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio)),
        ventanaCierreUtc = DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin),
        ventanaAbierta = CAST(IIF(sc.sesion IS NULL
                                  AND s.procedenciaTemporal IS NOT NULL
                                  AND DATEADD(MINUTE, -p.toleranciaMinutos, s.fechaHoraInicio) <= SYSUTCDATETIME()
                                  AND SYSUTCDATETIME() < DATEADD(MINUTE, p.margenMinutos, s.fechaHoraFin), 1, 0) AS BIT),
        horasSesion = CAST(IIF(s.fechaHoraFin > s.fechaHoraInicio,
                               CAST(DATEDIFF(MINUTE, s.fechaHoraInicio, s.fechaHoraFin) AS DECIMAL(12,6)) / 60, 0) AS DECIMAL(12,6))
FROM    dbo.uv_sesion_v2 s
CROSS APPLY (
        SELECT  toleranciaMinutos = IIF(t.valor IS NULL OR t.valor < 0, 0, t.valor),
                margenMinutos = IIF(m.valor IS NULL OR m.valor < 0, 0, m.valor)
        FROM    (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'TOLERANCIA_MINUTOS')) t
        CROSS JOIN (SELECT valor = dbo.ufn_obtener_parametro_int(NULL, 'ASISTENCIA', 'MARGEN_RETARDO_MINUTOS')) m
) p
LEFT JOIN dbo.SesionCancelacion sc
ON      sc.sesion = s.id
LEFT JOIN dbo.uv_tipo_cancelacion_sesion tc
ON      tc.id = sc.tipoCancelacion
LEFT JOIN dbo.DiaFestivo df
ON      df.id = sc.diaFestivo;
GO
-- HU065: una fila por sesion con su estado de cumplimiento (D4, D7). Consume uv_sesion_v2 (procedencia temporal) y
-- uv_grupo_programa; no altera las vistas congeladas.
-- CULM-001 B.1 (CONTRACT §2.6): una sesion cancelada (dbo.SesionCancelacion, por el docente o por festivo) sale de la
-- vista y con ello de sesionesProgramadas, vencidas, ejecutadas, cumplimiento, progreso de calendario y tendencia.
-- Columnas sin cambio.
CREATE OR ALTER VIEW [dbo].[uv_cumplimiento_sesion_grupo]
AS
SELECT  idSesion = s.id,
        idGrupo = s.idGrupo,
        idPeriodoAcademico = gp.idPeriodoAcademico,
        idPrograma = gp.idPrograma,
        fechaHoraInicio = s.fechaHoraInicio,
        fechaHoraFin = s.fechaHoraFin,
        estaVencida = CAST(IIF(s.procedenciaTemporal IS NOT NULL AND s.fechaHoraFin <= SYSUTCDATETIME(), 1, 0) AS BIT),
        procedenciaIndeterminada = CAST(IIF(s.procedenciaTemporal IS NULL, 1, 0) AS BIT),
        tieneRegistroAsistencia = CAST(IIF(EXISTS (SELECT 1 FROM dbo.uv_asistencia a WHERE a.idSesion = s.id), 1, 0) AS BIT)
FROM    dbo.uv_sesion_v2 s
INNER JOIN dbo.uv_grupo_programa gp
ON      gp.idGrupo = s.idGrupo
WHERE   NOT EXISTS (SELECT 1 FROM dbo.SesionCancelacion sc WHERE sc.sesion = s.id)
GO

IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.uv_sesion_estado', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_sesion_estado] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_dia_festivo', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_dia_festivo] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_carga_dia_festivo', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_carga_dia_festivo] TO [rol_asistencias_runtime];
    IF OBJECT_ID(N'dbo.uv_tipo_cancelacion_sesion', N'V') IS NOT NULL GRANT SELECT ON [dbo].[uv_tipo_cancelacion_sesion] TO [rol_asistencias_runtime];
END
GO

DECLARE @tipos INT = (SELECT COUNT(*) FROM dbo.TipoCancelacionSesion);
DECLARE @cancelaciones INT = (SELECT COUNT(*) FROM dbo.SesionCancelacion);
DECLARE @festivos INT = (SELECT COUNT(*) FROM dbo.DiaFestivo);
PRINT CONCAT('MIGRACION 15 UP OK | TipoCancelacionSesion=', @tipos, ' | SesionCancelacion=', @cancelaciones,
             ' | DiaFestivo=', @festivos, ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
