USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- MIGRACION UP 22: CULM-001 D.3 - parametros editables por el administrador (HU168; CONTRACT v2 §4.2)
-- Crea CatalogoParametroEdicion y CambioParametro (IF OBJECT_ID ... IS NULL) con sus indices y FKs, restaura el historial
-- exportado por el down (zz_archivo_CambioParametro_culm001_d3) y lo elimina, y crea o altera ufn_validar_valor_parametro,
-- uv_parametro_edicion, uv_cambio_parametro, usp_actualizar_parametro, usp_consultar_parametros_paginado y
-- usp_consultar_cambios_parametro_paginado. Siembra (MERGE, sin pisar valores administrados) los parametros PARAMETROS/*,
-- los mensajes PRM_001..PRM_012 y la lista blanca de edicion, y concede EXECUTE/SELECT al rol runtime. Idempotente.
-- El texto de los objetos es el de schema/ (los mismos archivos que despliega deploy_schema.ps1).
-- ============================================================================
PRINT 'MIGRACION 22 UP: tablas, funcion, vistas, SP y semillas de D.3';
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, [SUPUESTO-D-03], DEC-042): tabla satelite 1:1 de CatalogoParametro con la lista blanca de
-- edicion, el rango, la presentacion y la regla cruzada de cada parametro editable por el administrador (HU168). No toca la
-- forma de nueve columnas de CatalogoParametro (DB_BASELINE_CONTRACT). Una fila por parametro; sin fila = no editable.
-- Los grupos de PARAMETROS/GRUPOS_NO_EDITABLES nunca se editan, aunque la fila diga esEditable = 1 (lo impone el SP).
-- valoresPermitidos: lista separada por comas con pertenencia exacta. parametroDebeSerMenorQue: regla cruzada estricta
-- (valor de este parametro < valor del referenciado). Las filas las siembra 53_culm001_d3_parametro_edicion.sql.
IF OBJECT_ID('dbo.[CatalogoParametroEdicion]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CatalogoParametroEdicion (
        parametro                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_CatalogoParametroEdicion PRIMARY KEY CLUSTERED,
        esEditable                BIT              NOT NULL CONSTRAINT DF_CPE_esEditable DEFAULT 0,
        valorMinimo               DECIMAL(19,4)    NULL,
        valorMaximo               DECIMAL(19,4)    NULL,
        valoresPermitidos         NVARCHAR(500)    NULL,
        parametroDebeSerMenorQue  UNIQUEIDENTIFIER NULL,
        etiqueta                  NVARCHAR(120)    NOT NULL,
        descripcion               NVARCHAR(500)    NOT NULL,
        unidad                    NVARCHAR(30)     NULL,
        categoriaVisual           NVARCHAR(60)     NOT NULL,
        orden                     SMALLINT         NOT NULL CONSTRAINT DF_CPE_orden DEFAULT 0,
        CONSTRAINT CK_CPE_Rango CHECK (valorMinimo IS NULL OR valorMaximo IS NULL OR valorMinimo <= valorMaximo),
        CONSTRAINT CK_CPE_NoAutoReferencia CHECK (parametroDebeSerMenorQue IS NULL OR parametroDebeSerMenorQue <> parametro)
    );
END
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, [SUPUESTO-D-04]): historial inmutable de cambios de parametros hechos por el administrador
-- (HU168). Lo escribe usp_actualizar_parametro en la misma transaccion que el UPDATE de CatalogoParametro: valor anterior y
-- nuevo, motivo, ejecutor y correlacion. Solo se inserta; no se actualiza ni se borra (el down de la migracion 22 lo archiva).
IF OBJECT_ID('dbo.[CambioParametro]', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CambioParametro (
        id                 UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_CambioParametro PRIMARY KEY CLUSTERED,
        parametro          UNIQUEIDENTIFIER NOT NULL,
        valorAnterior      NVARCHAR(4000)   NOT NULL,
        valorNuevo         NVARCHAR(4000)   NOT NULL,
        motivo             NVARCHAR(500)    NOT NULL,
        idUsuarioEjecutor  UNIQUEIDENTIFIER NOT NULL,
        idCorrelacion      UNIQUEIDENTIFIER NOT NULL,
        fechaCambioUtc     DATETIME2(7)     NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.CambioParametro') AND name = 'IX_CambioParametro_Parametro_Fecha')
    CREATE NONCLUSTERED INDEX IX_CambioParametro_Parametro_Fecha ON dbo.CambioParametro (parametro, fechaCambioUtc DESC);
GO
USE [gestionasistenciadb];
GO
-- CULM-001 D.3 (CONTRACT v2 §4.2): edicion de parametros por el administrador (HU168).
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CatalogoParametroEdicion_CatalogoParametro')
BEGIN
    ALTER TABLE [dbo].[CatalogoParametroEdicion] ADD CONSTRAINT [FK_CatalogoParametroEdicion_CatalogoParametro] FOREIGN KEY ([parametro]) REFERENCES [dbo].[CatalogoParametro] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CatalogoParametroEdicion_MenorQue')
BEGIN
    ALTER TABLE [dbo].[CatalogoParametroEdicion] ADD CONSTRAINT [FK_CatalogoParametroEdicion_MenorQue] FOREIGN KEY ([parametroDebeSerMenorQue]) REFERENCES [dbo].[CatalogoParametro] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CambioParametro_CatalogoParametro')
BEGIN
    ALTER TABLE [dbo].[CambioParametro] ADD CONSTRAINT [FK_CambioParametro_CatalogoParametro] FOREIGN KEY ([parametro]) REFERENCES [dbo].[CatalogoParametro] ([id]);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_CambioParametro_Usuario')
BEGIN
    ALTER TABLE [dbo].[CambioParametro] ADD CONSTRAINT [FK_CambioParametro_Usuario] FOREIGN KEY ([idUsuarioEjecutor]) REFERENCES [dbo].[Usuario] ([id]);
END
GO

-- Restaura el historial que archivo el down de esta migracion (si existe) y retira el archivo.
IF OBJECT_ID(N'dbo.zz_archivo_CambioParametro_culm001_d3', N'U') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        INSERT INTO dbo.CambioParametro (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
        SELECT a.id, a.parametro, a.valorAnterior, a.valorNuevo, a.motivo, a.idUsuarioEjecutor, a.idCorrelacion, a.fechaCambioUtc
        FROM dbo.zz_archivo_CambioParametro_culm001_d3 a
        WHERE NOT EXISTS (SELECT 1 FROM dbo.CambioParametro c WHERE c.id = a.id);
        DROP TABLE dbo.zz_archivo_CambioParametro_culm001_d3;';
END
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- ufn_validar_valor_parametro (CULM-001 D.3, CONTRACT v2 §4.2, OBS-3)
--
-- Valida el valor propuesto de un parametro editable. Devuelve NULL si cumple o el codigo del mensaje de rechazo:
--   PRM_006  hay lista de valores permitidos y el valor no pertenece a ella (pertenencia exacta, sensible a mayusculas);
--   PRM_004  el tipo del parametro esta en PARAMETROS/TIPOS_NUMERICOS y el valor no es numerico, o esta ademas en
--            PARAMETROS/TIPOS_ENTEROS y tiene parte decimal; o el valor esta vacio o supera 4000 caracteres;
--   PRM_005  numerico fuera del rango [@min, @max] (limites inclusivos; un limite NULL no restringe).
-- Sin ramas por literales de tipo: los tipos numericos y enteros se leen del catalogo de parametros.
-- ============================================================================
CREATE OR ALTER FUNCTION [dbo].[ufn_validar_valor_parametro]
(
    @tipoDato    VARCHAR(20),
    @valor       NVARCHAR(4000),
    @min         DECIMAL(19,4),
    @max         DECIMAL(19,4),
    @permitidos  NVARCHAR(500)
)
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @valorLimpio NVARCHAR(4000) = TRIM(@valor);
    DECLARE @numero      DECIMAL(19,4);
    DECLARE @esNumerico  BIT = IIF(EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'TIPOS_NUMERICOS'), ',') t
                                           WHERE TRIM(t.value) = @tipoDato), 1, 0);
    DECLARE @esEntero    BIT = IIF(EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'TIPOS_ENTEROS'), ',') t
                                           WHERE TRIM(t.value) = @tipoDato), 1, 0);

    -- (3) Longitud 1-4000 para cualquier tipo
    IF @valorLimpio IS NULL OR LEN(@valorLimpio) < 1 OR LEN(@valorLimpio) > 4000
        RETURN 'PRM_004';

    -- (1) Lista de valores permitidos: pertenencia exacta
    IF @permitidos IS NOT NULL AND LEN(TRIM(@permitidos)) > 0
    BEGIN
        IF EXISTS (SELECT 1 FROM STRING_SPLIT(@permitidos, ',') p WHERE TRIM(p.value) COLLATE Latin1_General_BIN2 = @valorLimpio COLLATE Latin1_General_BIN2)
            RETURN NULL;
        RETURN 'PRM_006';
    END

    -- (2) Tipos numericos: numero valido, entero si corresponde y dentro del rango
    IF @esNumerico = 1
    BEGIN
        IF @valorLimpio LIKE N'%[^0-9.+-]%'
            RETURN 'PRM_004';
        SET @numero = TRY_CONVERT(DECIMAL(19,4), @valorLimpio);
        IF @numero IS NULL
            RETURN 'PRM_004';
        IF @esEntero = 1 AND @numero <> FLOOR(@numero)
            RETURN 'PRM_004';
        IF (@min IS NOT NULL AND @numero < @min) OR (@max IS NOT NULL AND @numero > @max)
            RETURN 'PRM_005';
    END

    RETURN NULL;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): parametros activos con su regla de edicion y su ultimo cambio. Una fila por
-- parametro activo. esEditable es efectivo: fila de edicion con esEditable = 1 Y grupo fuera de PARAMETROS/GRUPOS_NO_EDITABLES
-- (un grupo protegido nunca es editable aunque la fila lo diga). Sin fila de edicion: etiqueta = clave, descripcion vacia,
-- categoriaVisual = grupo y esEditable = 0. Solo la leen los SP usp_consultar_parametros_paginado y usp_actualizar_parametro.
CREATE OR ALTER VIEW [dbo].[uv_parametro_edicion]
AS
SELECT  p.id,
        p.grupo,
        p.clave,
        p.valor,
        p.valorDefecto,
        p.tipoDato,
        esEditable = CAST(IIF(ISNULL(e.esEditable, 0) = 1 AND g.esGrupoProtegido = 0, 1, 0) AS BIT),
        e.valorMinimo,
        e.valorMaximo,
        e.valoresPermitidos,
        etiqueta = ISNULL(e.etiqueta, CAST(p.clave AS NVARCHAR(120))),
        descripcion = ISNULL(e.descripcion, N''),
        e.unidad,
        categoriaVisual = ISNULL(e.categoriaVisual, CAST(p.grupo AS NVARCHAR(60))),
        orden = ISNULL(e.orden, CAST(0 AS SMALLINT)),
        p.fechaModificacion,
        fechaUltimoCambioUtc = c.fechaCambioUtc,
        nombreUltimoActor = c.nombreEjecutor,
        esGrupoProtegido = g.esGrupoProtegido,
        e.parametroDebeSerMenorQue
FROM    dbo.uv_parametro p
LEFT JOIN dbo.CatalogoParametroEdicion e
ON      e.parametro = p.id
CROSS APPLY (
        SELECT esGrupoProtegido = CAST(IIF(EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES'), ',') n
                                                   WHERE TRIM(n.value) = p.grupo), 1, 0) AS BIT)
) g
OUTER APPLY (
        SELECT TOP 1 cp.fechaCambioUtc, nombreEjecutor = u.nombreCompleto
        FROM    dbo.CambioParametro cp
        LEFT JOIN dbo.uv_usuario u
        ON      u.id = cp.idUsuarioEjecutor
        WHERE   cp.parametro = p.id
        ORDER BY cp.fechaCambioUtc DESC, cp.id
) c;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): historial de cambios de parametros con el parametro y el ejecutor.
-- Solo lo lee usp_consultar_cambios_parametro_paginado (perfil ADMINISTRADOR).
CREATE OR ALTER VIEW [dbo].[uv_cambio_parametro]
AS
SELECT  cp.id,
        idParametro = cp.parametro,
        p.grupo,
        p.clave,
        cp.valorAnterior,
        cp.valorNuevo,
        cp.motivo,
        cp.idUsuarioEjecutor,
        nombreEjecutor = u.nombreCompleto,
        cp.idCorrelacion,
        cp.fechaCambioUtc
FROM    dbo.CambioParametro cp
INNER JOIN dbo.CatalogoParametro p
ON      p.id = cp.parametro
LEFT JOIN dbo.uv_usuario u
ON      u.id = cp.idUsuarioEjecutor;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): parametros de la edicion de parametros. Ninguno es editable.
-- Patron 29_parametros_matricula_qr.sql: idempotente y sin pisar el valor administrado (WHEN MATCHED solo actualiza
-- tipoDato y valorDefecto). El backend tiene en codigo un valor por defecto igual a la semilla (DEC-018).
--   PARAMETROS/GRUPOS_NO_EDITABLES: grupos que el administrador nunca edita (red, tiempo, constantes de dominio y
--     parametros de gobierno); gana sobre la lista blanca de CatalogoParametroEdicion (OBS-9).
--   PARAMETROS/TIPOS_NUMERICOS y TIPOS_ENTEROS: tipos de CatalogoParametro.tipoDato validados como numero y como entero
--     (ufn_validar_valor_parametro, sin literales de tipo en el codigo).
--   PARAMETROS/LONGITUD_MINIMA_MOTIVO: longitud minima del motivo del cambio (PRM_009); el maximo es la columna (500).
MERGE INTO [dbo].[CatalogoParametro] AS Target
USING (VALUES
    ('PARAMETROS', 'GRUPOS_NO_EDITABLES',    N'RED,TIEMPO,GENERAL,REGISTRO,IDENTIDAD,RECLAMO,TOMA_ASISTENCIA,PARAMETROS,AUDITORIA,PAGINACION,MATRICULA', 'STRING',
                                             N'RED,TIEMPO,GENERAL,REGISTRO,IDENTIDAD,RECLAMO,TOMA_ASISTENCIA,PARAMETROS,AUDITORIA,PAGINACION,MATRICULA'),
    ('PARAMETROS', 'TIPOS_NUMERICOS',        N'INT,DECIMAL', 'STRING', N'INT,DECIMAL'),
    ('PARAMETROS', 'TIPOS_ENTEROS',          N'INT',         'STRING', N'INT'),
    ('PARAMETROS', 'LONGITUD_MINIMA_MOTIVO', N'10',          'INT',    N'10')
) AS Source (grupo, clave, valor, tipoDato, valorDefecto)
ON (Target.grupo = Source.grupo AND Target.clave = Source.clave)
WHEN MATCHED THEN
    UPDATE SET Target.tipoDato = Source.tipoDato, Target.valorDefecto = Source.valorDefecto, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (grupo, clave, valor, tipoDato, valorDefecto, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.grupo, Source.clave, Source.valor, Source.tipoDato, Source.valorDefecto, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, HU168): mensajes de la edicion de parametros por el administrador. Idempotente (MERGE por
-- codigo). PRM_010 lo emite solo el backend (proveedor de parametros distinto de sqlserver) y vive aqui por ser SSOT de mensajes.
MERGE INTO [dbo].[CatalogoMensajeUsuario] AS Target
USING (VALUES
    ('PRM_001', 'SUCCESS',          'BAJO',  N'Parámetro actualizado.'),
    ('PRM_002', 'BUSINESS_ERROR',   'MEDIO', N'El parámetro no existe.'),
    ('PRM_003', 'BUSINESS_ERROR',   'MEDIO', N'Este parámetro no se puede editar.'),
    ('PRM_004', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe ser de tipo {}.'),
    ('PRM_005', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe estar entre {} y {}.'),
    ('PRM_006', 'VALIDATION_ERROR', 'BAJO',  N'El valor debe ser uno de: {}.'),
    ('PRM_007', 'VALIDATION_ERROR', 'BAJO',  N'«{}» debe ser menor que «{}».'),
    ('PRM_008', 'BUSINESS_ERROR',   'MEDIO', N'Otro usuario modificó el parámetro. Recarga y vuelve a intentarlo.'),
    ('PRM_009', 'VALIDATION_ERROR', 'BAJO',  N'Indica un motivo de al menos {} caracteres.'),
    ('PRM_010', 'BUSINESS_ERROR',   'MEDIO', N'La edición de parámetros no está disponible con el catálogo de configuración activo.'),
    ('PRM_011', 'SUCCESS',          'BAJO',  N'El valor no cambió.'),
    ('PRM_012', 'BUSINESS_ERROR',   'MEDIO', N'La edición de parámetros requiere una sola institución activa.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO

MERGE INTO [dbo].[CatalogoMensajeTecnico] AS Target
USING (VALUES
    ('PRM_001', 'SUCCESS',          'BAJO',  N'CatalogoParametro actualizado y CambioParametro registrado.'),
    ('PRM_002', 'BUSINESS_ERROR',   'MEDIO', N'CatalogoParametro no tiene un parametro activo con ese id.'),
    ('PRM_003', 'BUSINESS_ERROR',   'MEDIO', N'Parametro en un grupo de PARAMETROS/GRUPOS_NO_EDITABLES o sin fila editable en CatalogoParametroEdicion.'),
    ('PRM_004', 'VALIDATION_ERROR', 'BAJO',  N'Valor invalido para tipoDato [{}] (no numerico, con decimales en un tipo entero, vacio o de mas de 4000 caracteres).'),
    ('PRM_005', 'VALIDATION_ERROR', 'BAJO',  N'Valor fuera del rango [{}, {}] de CatalogoParametroEdicion.'),
    ('PRM_006', 'VALIDATION_ERROR', 'BAJO',  N'Valor fuera de valoresPermitidos [{}] (pertenencia exacta).'),
    ('PRM_007', 'VALIDATION_ERROR', 'BAJO',  N'Regla cruzada estricta violada: [{}] debe ser menor que [{}].'),
    ('PRM_008', 'BUSINESS_ERROR',   'MEDIO', N'fechaModificacionEsperada distinta de CatalogoParametro.fechaModificacion (concurrencia optimista).'),
    ('PRM_009', 'VALIDATION_ERROR', 'BAJO',  N'Motivo vacio o menor que PARAMETROS/LONGITUD_MINIMA_MOTIVO ({}) tras recortar.'),
    ('PRM_010', 'BUSINESS_ERROR',   'MEDIO', N'El catalogo de parametros activo del backend no es sqlserver: la edicion en BD no es la fuente de verdad.'),
    ('PRM_011', 'SUCCESS',          'BAJO',  N'El valor propuesto es igual al almacenado; no se escribio nada.'),
    ('PRM_012', 'BUSINESS_ERROR',   'MEDIO', N'[SUPUESTO-D-16] La instalacion no tiene exactamente una Institucion activa; los parametros no tienen ambito por institucion.')
) AS Source (codigo, tipoMensaje, severidad, contenido)
ON (Target.codigo = Source.codigo)
WHEN MATCHED THEN
    UPDATE SET Target.tipoMensaje = Source.tipoMensaje, Target.severidad = Source.severidad, Target.contenido = Source.contenido, Target.fechaModificacion = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (codigo, tipoMensaje, severidad, contenido, estaActivo, fechaCreacion, fechaModificacion)
    VALUES (Source.codigo, Source.tipoMensaje, Source.severidad, Source.contenido, 1, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_actualizar_parametro (CULM-001 D.3, HU168; CONTRACT v2 §4.2)
--
-- Clasificacion: NON_GOLDEN_PATH_EXTENSION, comando con tupla canonica + idParametro, grupo, clave, valorAnterior,
-- valorNuevo y fechaModificacion (NULL si estadoResultado = 0).
--
-- El administrador edita el valor de un parametro de negocio de la lista blanca (CatalogoParametroEdicion). Pasos:
-- correlacion -> ejecutor -> RBAC ADMINISTRADOR -> una sola Institucion activa ([SUPUESTO-D-16], PRM_012) -> motivo con al
-- menos PARAMETROS/LONGITUD_MINIMA_MOTIVO caracteres tras recortar (PRM_009) -> fila de CatalogoParametro bloqueada
-- (UPDLOCK, HOLDLOCK), activa (PRM_002) -> grupo fuera de PARAMETROS/GRUPOS_NO_EDITABLES y fila editable (PRM_003) ->
-- fechaModificacion igual a la esperada, comparacion exacta en DATETIME (PRM_008) -> ufn_validar_valor_parametro
-- (PRM_004/005/006) -> reglas cruzadas estrictas en las dos direcciones (PRM_007) -> valor igual (PRM_011: exito sin
-- escritura) -> UPDATE valor y fechaModificacion + INSERT CambioParametro en la misma transaccion.
-- Transaccion propia o SAVE TRANSACTION. Las ramas de rechazo no escriben: solo confirman la transaccion propia (sin
-- ROLLBACK, compatible con INSERT ... EXEC). Las filas relacionadas por la regla cruzada se bloquean tambien para que dos
-- ediciones simultaneas de un par no violen la regla.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_actualizar_parametro]
(
    @idParametro               UNIQUEIDENTIFIER,
    @valor                     NVARCHAR(4000),
    @fechaModificacionEsperada DATETIME,
    @motivo                    NVARCHAR(500),
    @idCorrelacion             UNIQUEIDENTIFIER,
    @idUsuarioEjecutor         UNIQUEIDENTIFIER = NULL
)
AS
    DECLARE @idCorrelacionDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioEjecutorDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idParametroDefecto       UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idParametro, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;

    DECLARE @transaccionPropia      BIT = 0;
    DECLARE @savepointCreado        BIT = 0;
    DECLARE @estadoTransaccionCatch INT;

    DECLARE @valorLimpio      NVARCHAR(4000) = TRIM(@valor);
    DECLARE @motivoLimpio     NVARCHAR(500) = TRIM(@motivo);
    DECLARE @longitudMinima   INT = dbo.ufn_obtener_parametro_int(NULL, 'PARAMETROS', 'LONGITUD_MINIMA_MOTIVO');
    DECLARE @grupo            VARCHAR(100);
    DECLARE @clave            VARCHAR(100);
    DECLARE @tipoDato         VARCHAR(20);
    DECLARE @valorAnterior    NVARCHAR(4000);
    DECLARE @fechaActual      DATETIME;
    DECLARE @esEditable       BIT;
    DECLARE @valorMinimo      DECIMAL(19,4);
    DECLARE @valorMaximo      DECIMAL(19,4);
    DECLARE @permitidos       NVARCHAR(500);
    DECLARE @idReferido       UNIQUEIDENTIFIER;
    DECLARE @claveReferida    VARCHAR(100);
    DECLARE @valorReferido    DECIMAL(19,4);
    DECLARE @claveDependiente VARCHAR(100);
    DECLARE @numeroNuevo      DECIMAL(19,4);
    DECLARE @fechaNueva       DATETIME = NULL;
    DECLARE @codigoRechazo    VARCHAR(20) = NULL;
    DECLARE @param1           NVARCHAR(500) = NULL;
    DECLARE @param2           NVARCHAR(500) = NULL;
    DECLARE @sinCambios       BIT = 0;
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        -- PASO 1: correlacion y ejecutor obligatorios
        EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND @idUsuarioEjecutor IS NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_002', @p_param1 = 'idUsuarioEjecutor',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 2: RBAC (ADMINISTRADOR)
        IF @estadoResultado = 1
        BEGIN
            EXEC dbo.usp_validar_permiso_rbac_usuario_interno
                @idUsuario = @idUsuarioEjecutorDefecto,
                @codigoPerfilRequerido = 'ADMINISTRADOR',
                @idCorrelacion = @idCorrelacionDefecto,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
                @estadoResultado = @estadoResultado OUTPUT;
        END

        -- PASO 3: [SUPUESTO-D-16] despliegue monoinstitucional: exactamente una Institucion activa (PRM_012)
        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 4: motivo con la longitud minima parametrizada (PRM_009)
        IF @estadoResultado = 1 AND (@motivoLimpio IS NULL OR @longitudMinima IS NULL OR LEN(@motivoLimpio) < @longitudMinima)
        BEGIN
            SET @param1 = CONVERT(NVARCHAR(20), @longitudMinima);
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_009', @p_param1 = @param1,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            SET @estadoResultado = 0;
        END

        -- PASO 5: transaccion y evaluacion bajo el bloqueo de la fila del parametro
        IF @estadoResultado = 1
        BEGIN
            IF @@TRANCOUNT = 0
            BEGIN
                BEGIN TRANSACTION;
                SET @transaccionPropia = 1;
            END
            ELSE
            BEGIN
                SAVE TRANSACTION sp_actualizar_parametro;
                SET @savepointCreado = 1;
            END

            SELECT @grupo = p.grupo, @clave = p.clave, @tipoDato = p.tipoDato, @valorAnterior = CONVERT(NVARCHAR(4000), p.valor), @fechaActual = p.fechaModificacion
            FROM dbo.CatalogoParametro p WITH (UPDLOCK, HOLDLOCK)
            WHERE p.id = @idParametroDefecto AND p.estaActivo = 1;

            IF @clave IS NULL
                SET @codigoRechazo = 'PRM_002';

            IF @codigoRechazo IS NULL
            BEGIN
                SELECT @esEditable = e.esEditable, @valorMinimo = e.valorMinimo, @valorMaximo = e.valorMaximo,
                       @permitidos = e.valoresPermitidos, @idReferido = e.parametroDebeSerMenorQue
                FROM dbo.CatalogoParametroEdicion e
                WHERE e.parametro = @idParametroDefecto;

                IF ISNULL(@esEditable, 0) = 0
                   OR EXISTS (SELECT 1 FROM STRING_SPLIT(dbo.ufn_obtener_parametro('PARAMETROS', 'GRUPOS_NO_EDITABLES'), ',') n WHERE TRIM(n.value) = @grupo)
                    SET @codigoRechazo = 'PRM_003';
            END

            IF @codigoRechazo IS NULL AND (@fechaModificacionEsperada IS NULL OR @fechaActual <> @fechaModificacionEsperada)
                SET @codigoRechazo = 'PRM_008';

            IF @codigoRechazo IS NULL
            BEGIN
                SET @codigoRechazo = dbo.ufn_validar_valor_parametro(@tipoDato, @valorLimpio, @valorMinimo, @valorMaximo, @permitidos);
                IF @codigoRechazo = 'PRM_004'
                    SET @param1 = @tipoDato;
                ELSE IF @codigoRechazo = 'PRM_005'
                BEGIN
                    SET @param1 = IIF(@valorMinimo IS NULL, N'-', IIF(@valorMinimo = FLOOR(@valorMinimo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMinimo)), CONVERT(NVARCHAR(40), @valorMinimo)));
                    SET @param2 = IIF(@valorMaximo IS NULL, N'-', IIF(@valorMaximo = FLOOR(@valorMaximo), CONVERT(NVARCHAR(40), CONVERT(BIGINT, @valorMaximo)), CONVERT(NVARCHAR(40), @valorMaximo)));
                END
                ELSE IF @codigoRechazo = 'PRM_006'
                    SET @param1 = @permitidos;
            END

            -- Reglas cruzadas estrictas (PRM_007): este < referido y cada dependiente < este
            IF @codigoRechazo IS NULL
            BEGIN
                SET @numeroNuevo = TRY_CONVERT(DECIMAL(19,4), @valorLimpio);
                IF @numeroNuevo IS NOT NULL AND @idReferido IS NOT NULL
                BEGIN
                    SELECT @claveReferida = r.clave, @valorReferido = TRY_CONVERT(DECIMAL(19,4), r.valor)
                    FROM dbo.CatalogoParametro r WITH (UPDLOCK, HOLDLOCK)
                    WHERE r.id = @idReferido;
                    IF @valorReferido IS NOT NULL AND @numeroNuevo >= @valorReferido
                    BEGIN
                        SET @codigoRechazo = 'PRM_007';
                        SET @param1 = @clave;
                        SET @param2 = @claveReferida;
                    END
                END
                IF @codigoRechazo IS NULL AND @numeroNuevo IS NOT NULL
                BEGIN
                    SELECT TOP 1 @claveDependiente = d.clave
                    FROM dbo.CatalogoParametroEdicion de
                    INNER JOIN dbo.CatalogoParametro d WITH (UPDLOCK, HOLDLOCK) ON d.id = de.parametro
                    WHERE de.parametroDebeSerMenorQue = @idParametroDefecto
                      AND TRY_CONVERT(DECIMAL(19,4), d.valor) >= @numeroNuevo
                    ORDER BY d.clave;
                    IF @claveDependiente IS NOT NULL
                    BEGIN
                        SET @codigoRechazo = 'PRM_007';
                        SET @param1 = @claveDependiente;
                        SET @param2 = @clave;
                    END
                END
            END

            -- Valor igual: exito sin escritura (PRM_011)
            IF @codigoRechazo IS NULL AND @valorLimpio COLLATE Latin1_General_BIN2 = @valorAnterior COLLATE Latin1_General_BIN2
                SET @sinCambios = 1;

            IF @codigoRechazo IS NULL AND @sinCambios = 0
            BEGIN
                UPDATE dbo.CatalogoParametro
                SET valor = @valorLimpio, fechaModificacion = SYSUTCDATETIME()
                WHERE id = @idParametroDefecto;

                SELECT @fechaNueva = fechaModificacion FROM dbo.CatalogoParametro WHERE id = @idParametroDefecto;

                INSERT INTO dbo.CambioParametro (id, parametro, valorAnterior, valorNuevo, motivo, idUsuarioEjecutor, idCorrelacion, fechaCambioUtc)
                VALUES (NEWID(), @idParametroDefecto, @valorAnterior, @valorLimpio, @motivoLimpio, @idUsuarioEjecutorDefecto, @idCorrelacionDefecto, SYSUTCDATETIME());

                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PRM_001',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE IF @sinCambios = 1
            BEGIN
                SET @fechaNueva = @fechaActual;
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = 'PRM_011',
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
            END
            ELSE
            BEGIN
                EXEC dbo.usp_obtener_mensaje_catalogo
                    @p_codigo = @codigoRechazo, @p_param1 = @param1, @p_param2 = @param2,
                    @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                    @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
                SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', @idCorrelacionDefecto);
                SET @estadoResultado = 0;
            END

            -- La rama de rechazo no escribe: solo se confirma la transaccion propia (libera los bloqueos).
            IF @transaccionPropia = 1
            BEGIN
                IF XACT_STATE() = 1
                    COMMIT TRANSACTION;
                ELSE IF XACT_STATE() = -1
                    ROLLBACK TRANSACTION;
                SET @transaccionPropia = 0;
            END
        END
    END TRY
    BEGIN CATCH
        SET @estadoTransaccionCatch = XACT_STATE();
        IF @transaccionPropia = 1
        BEGIN
            IF @estadoTransaccionCatch <> 0
                ROLLBACK TRANSACTION;
        END
        ELSE IF @savepointCreado = 1 AND @estadoTransaccionCatch = 1
            ROLLBACK TRANSACTION sp_actualizar_parametro;

        -- Transaccion externa condenada que no nos pertenece: se propaga al propietario
        IF @transaccionPropia = 0 AND @estadoTransaccionCatch = -1
            THROW;

        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH

    SELECT
        idCorrelacion           = @idCorrelacionDefecto,
        mensajeUsuarioResultado = @mensajeUsuarioResultado,
        mensajeTecnicoResultado = @mensajeTecnicoResultado,
        estadoResultado         = @estadoResultado,
        idParametro             = IIF(@estadoResultado = 1, @idParametroDefecto, NULL),
        grupo                   = IIF(@estadoResultado = 1, @grupo, NULL),
        clave                   = IIF(@estadoResultado = 1, @clave, NULL),
        valorAnterior           = IIF(@estadoResultado = 1, @valorAnterior, NULL),
        valorNuevo              = IIF(@estadoResultado = 1, IIF(@sinCambios = 1, @valorAnterior, @valorLimpio), NULL),
        fechaModificacion       = IIF(@estadoResultado = 1, @fechaNueva, NULL);
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_parametros_paginado (CULM-001 D.3, HU168, F-ADM-012; CONTRACT v2 §4.2)
--
-- Parametros activos legibles y agrupados para el administrador: etiqueta, descripcion, valor, unidad, rango, valores
-- permitidos, ultimo cambio y si son editables. @soloEditables = 1 (defecto) excluye los tecnicos y los de grupos protegidos;
-- 0 los incluye de solo lectura. Filtros: @grupo exacto y @texto (contiene, sobre grupo, clave, etiqueta y descripcion).
-- Orden: categoriaVisual, orden, clave. Pagina y tamano validados con PAGINACION/TAMANO_MAXIMO (PAG_001).
--
-- Resultset: READ_QUERY_RESULTSET (filas + totalRegistros), NO el resultset canonico de 4 columnas. Las fallas de validacion
-- se propagan con THROW (VAL_001 / SEC_001 / PAG_001 / PRM_012). Solo perfil ADMINISTRADOR. [SUPUESTO-D-16]: con mas de una
-- Institucion activa falla con PRM_012 y sin filas (los parametros no tienen institucion).
-- SESSION_CONTEXT: lo fija el interno de validacion; se captura el previo y SIEMPRE se restaura.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_parametros_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT,
    @grupo              VARCHAR(100)  = NULL,
    @texto              NVARCHAR(200) = NULL,
    @soloEditables      BIT           = 1
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @grupoFiltro             VARCHAR(100) = NULLIF(TRIM(@grupo), '');
    DECLARE @textoFiltro             NVARCHAR(200) = NULLIF(TRIM(@texto), '');
    DECLARE @soloEditablesFiltro     BIT = ISNULL(@soloEditables, 1);
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    -- Consulta de solo lectura: sin XACT_ABORT para no invalidar la transaccion del llamador ante un THROW de validacion.
    BEGIN TRY
        -- PASO 1: Correlacion, ejecutor, perfil ADMINISTRADOR y paginacion; fija el contexto (usp_validar_consulta_paginada_interno)
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        -- PASO 2: [SUPUESTO-D-16] una sola Institucion activa (PRM_012)
        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        -- PASO 3: Consulta y retorno de resultados
        SELECT
            v.id,
            v.grupo,
            v.clave,
            valor = CONVERT(NVARCHAR(4000), v.valor),
            valorDefecto = CONVERT(NVARCHAR(4000), v.valorDefecto),
            v.tipoDato,
            v.esEditable,
            v.valorMinimo,
            v.valorMaximo,
            v.valoresPermitidos,
            v.etiqueta,
            v.descripcion,
            v.unidad,
            v.categoriaVisual,
            v.orden,
            v.fechaModificacion,
            v.fechaUltimoCambioUtc,
            v.nombreUltimoActor,
            v.esGrupoProtegido,
            totalRegistros = COUNT(*) OVER()
        FROM dbo.uv_parametro_edicion v
        WHERE
            (@soloEditablesFiltro = 0 OR v.esEditable = 1)
            AND (@grupoFiltro IS NULL OR v.grupo = @grupoFiltro)
            AND (@textoFiltro IS NULL
                 OR CHARINDEX(@textoFiltro, v.grupo) > 0
                 OR CHARINDEX(@textoFiltro, v.clave) > 0
                 OR CHARINDEX(@textoFiltro, v.etiqueta) > 0
                 OR CHARINDEX(@textoFiltro, v.descripcion) > 0)
        ORDER BY v.categoriaVisual ASC, v.orden ASC, v.clave ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_cambios_parametro_paginado (CULM-001 D.3, HU168; CONTRACT v2 §4.2, parte diferible)
--
-- Historial de cambios de un parametro (CambioParametro) del mas reciente al mas antiguo: valor anterior y nuevo, motivo,
-- ejecutor, correlacion y fecha UTC. El parametro debe existir (PRM_002). Solo perfil ADMINISTRADOR; [SUPUESTO-D-16]: con
-- mas de una Institucion activa falla con PRM_012. Resultset READ_QUERY_RESULTSET (filas + totalRegistros); las fallas de
-- validacion se propagan con THROW. Sin XACT_ABORT; restaura el SESSION_CONTEXT.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_cambios_parametro_paginado]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idParametro        UNIQUEIDENTIFIER,
    @numeroPagina       INT,
    @tamanoPagina       INT
)
AS
    DECLARE @idUsuario               UNIQUEIDENTIFIER;
    DECLARE @offset                  INT;
    DECLARE @idCorrelacionDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @contextoPrevio          SQL_VARIANT = SESSION_CONTEXT(N'idUsuarioEjecutor');
    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado         BIT = 1;
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        EXEC dbo.usp_validar_consulta_paginada_interno
            @idUsuarioEjecutor = @idUsuarioEjecutor,
            @idCorrelacion = @idCorrelacion,
            @codigoPerfilRequerido = 'ADMINISTRADOR',
            @numeroPagina = @numeroPagina,
            @tamanoPagina = @tamanoPagina,
            @idUsuarioValidado = @idUsuario OUTPUT,
            @offset = @offset OUTPUT,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;

        IF @estadoResultado = 1 AND (SELECT COUNT(1) FROM dbo.uv_institucion WHERE estaActivaInstitucion = 1) <> 1
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_012',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 1 AND (@idParametro IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.uv_parametro WHERE id = @idParametro))
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'PRM_002',
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SET @estadoResultado = 0;
        END

        IF @estadoResultado = 0
        BEGIN
            THROW 51000, @mensajeTecnicoResultado, 1;
        END;

        SELECT
            c.id,
            c.idParametro,
            c.grupo,
            c.clave,
            c.valorAnterior,
            c.valorNuevo,
            c.motivo,
            c.idUsuarioEjecutor,
            c.nombreEjecutor,
            c.idCorrelacion,
            c.fechaCambioUtc,
            totalRegistros = COUNT(*) OVER()
        FROM dbo.uv_cambio_parametro c
        WHERE c.idParametro = @idParametro
        ORDER BY c.fechaCambioUtc DESC, c.id ASC
        OFFSET @offset ROWS
        FETCH NEXT @tamanoPagina ROWS ONLY;

        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'idUsuarioEjecutor', @value = @contextoPrevio, @read_only = 0;
        THROW;
    END CATCH;
END;
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2, [SUPUESTO-D-03], HU168): lista blanca inicial de parametros editables por el administrador,
-- con rango, valores permitidos, regla cruzada estricta y presentacion. MERGE por (grupo, clave) contra CatalogoParametro:
-- solo se siembran filas de parametros que existen (los de D.2 y D.5, ARCHIVOS/MAXIMO_SOPORTES_POR_RECLAMO y CARGA_MASIVA/*,
-- entran cuando esos paquetes siembran su parametro y se vuelve a desplegar). Los parametros que NO aparecen aqui (RED,
-- TIEMPO, URL y secretos de festivos, estados, lotes, URL base del frontend, codigos de razon, etc.) no tienen fila y por tanto
-- no son editables. Los grupos de PARAMETROS/GRUPOS_NO_EDITABLES tampoco lo son aunque tuvieran fila.
-- Re-desplegar actualiza la regla y la presentacion (son codigo), nunca el valor del parametro.
MERGE INTO [dbo].[CatalogoParametroEdicion] AS Target
USING (
    SELECT  p.id AS parametro, v.esEditable, v.valorMinimo, v.valorMaximo, v.valoresPermitidos, m.id AS parametroDebeSerMenorQue,
            v.etiqueta, v.descripcion, v.unidad, v.categoriaVisual, v.orden
    FROM (VALUES
        ('ASISTENCIA',    'TOLERANCIA_MINUTOS',                   CONVERT(BIT, 1), CONVERT(DECIMAL(19,4), 0),      CONVERT(DECIMAL(19,4), 60),      NULL,                 NULL, NULL,
            N'Tolerancia de apertura', N'Minutos antes del inicio de la sesión en que ya se puede registrar asistencia.', N'minutos', N'Asistencia', CONVERT(SMALLINT, 10)),
        ('ASISTENCIA',    'MARGEN_RETARDO_MINUTOS',               1, 0,      120,     NULL,                 NULL, NULL,
            N'Margen de retardo', N'Minutos después del fin de la sesión en que todavía se puede registrar asistencia.', N'minutos', N'Asistencia', 20),
        ('ASISTENCIA',    'DIAS_LIMITE_JUSTIFICACION',            1, 1,      30,      NULL,                 NULL, NULL,
            N'Plazo para justificar', N'Días calendario, desde el fin de la sesión, en que el estudiante puede radicar una excusa.', N'días', N'Asistencia', 30),
        ('ASISTENCIA',    'UMBRAL_ALERTA_ADVERTENCIA',            1, 1,      99,      NULL,                 'ASISTENCIA', 'UMBRAL_ALERTA_PERDIDA',
            N'Umbral de advertencia', N'Porcentaje de inasistencia desde el cual el estudiante queda en riesgo. Debe ser menor que el umbral de pérdida.', N'%', N'Asistencia', 40),
        ('ASISTENCIA',    'UMBRAL_ALERTA_PERDIDA',                1, 1,      100,     NULL,                 NULL, NULL,
            N'Umbral de pérdida', N'Porcentaje de inasistencia desde el cual el estudiante pierde la asignatura.', N'%', N'Asistencia', 50),
        ('MATRICULA_QR',  'HABILITADA',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Matrícula por QR habilitada', N'Permite o suspende la matrícula de estudiantes por código QR.', NULL, N'Matrícula por QR', 10),
        ('MATRICULA_QR',  'ROTACION_SEGUNDOS',                    1, 15,     300,     NULL,                 NULL, NULL,
            N'Rotación del código QR de matrícula', N'Cada cuántos segundos cambia el código QR de matrícula.', N'segundos', N'Matrícula por QR', 20),
        ('MATRICULA_QR',  'TOLERANCIA_SEGUNDOS',                  1, 0,      300,     NULL,                 NULL, NULL,
            N'Tolerancia del código QR de matrícula', N'Segundos en que el código anterior sigue siendo válido tras rotar.', N'segundos', N'Matrícula por QR', 30),
        ('MATRICULA_QR',  'DURACION_MAXIMA_MINUTOS',              1, 5,      240,     NULL,                 NULL, NULL,
            N'Duración máxima de la ventana de matrícula', N'Minutos máximos que puede estar abierta una ventana de matrícula por QR.', N'minutos', N'Matrícula por QR', 40),
        ('MATRICULA_QR',  'LIMITE_IP_POR_MINUTO',                 1, 5,      1000,    NULL,                 NULL, NULL,
            N'Límite por IP en matrícula', N'Solicitudes por minuto permitidas desde una misma IP al validar o usar el código de matrícula.', N'por minuto', N'Matrícula por QR', 50),
        ('MATRICULA_QR',  'LIMITE_REGISTROS_TOKEN_POR_MINUTO',    1, 1,      200,     NULL,                 NULL, NULL,
            N'Límite de registros por código', N'Matrículas por minuto permitidas con un mismo código QR.', N'por minuto', N'Matrícula por QR', 60),
        ('ASISTENCIA_QR', 'HABILITADA',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Asistencia por QR habilitada', N'Permite o suspende el registro de asistencia por código QR o PIN.', NULL, N'Asistencia por QR', 10),
        ('ASISTENCIA_QR', 'ROTACION_SEGUNDOS',                    1, 15,     300,     NULL,                 NULL, NULL,
            N'Rotación del código QR de asistencia', N'Cada cuántos segundos cambia el código QR de asistencia.', N'segundos', N'Asistencia por QR', 20),
        ('ASISTENCIA_QR', 'TOLERANCIA_SEGUNDOS',                  1, 0,      300,     NULL,                 NULL, NULL,
            N'Tolerancia del código QR de asistencia', N'Segundos en que el código anterior sigue siendo válido tras rotar.', N'segundos', N'Asistencia por QR', 30),
        ('ASISTENCIA_QR', 'LIMITE_IP_POR_MINUTO',                 1, 5,      1000,    NULL,                 NULL, NULL,
            N'Límite por IP en asistencia', N'Solicitudes por minuto permitidas desde una misma IP al registrar asistencia por QR.', N'por minuto', N'Asistencia por QR', 40),
        ('ASISTENCIA_QR', 'LIMITE_FALLIDOS_IP_POR_MINUTO',        1, 50,     5000,    NULL,                 NULL, NULL,
            N'Límite de intentos fallidos por IP', N'Intentos fallidos por minuto permitidos desde una misma IP antes de bloquearla.', N'por minuto', N'Asistencia por QR', 50),
        ('ASISTENCIA_QR', 'LIMITE_TOKEN_POR_MINUTO',              1, 10,     2000,    NULL,                 NULL, NULL,
            N'Límite por código de asistencia', N'Registros por minuto permitidos con un mismo código QR de asistencia.', N'por minuto', N'Asistencia por QR', 60),
        ('ASISTENCIA_QR', 'LIMITE_ESTUDIANTE_POR_MINUTO',         1, 1,      60,      NULL,                 NULL, NULL,
            N'Límite por estudiante', N'Intentos por minuto permitidos a un mismo estudiante al registrar asistencia por QR.', N'por minuto', N'Asistencia por QR', 70),
        ('FESTIVOS',      'HABILITADO',                           1, NULL,   NULL,    N'true,false',        NULL, NULL,
            N'Carga automática de festivos', N'Activa o suspende el job que carga los días festivos y cancela las sesiones de esos días.', NULL, N'Días festivos', 10),
        ('FESTIVOS',      'PROVEEDOR_PRINCIPAL',                  1, NULL,   NULL,    N'CALENDARIOS_NACIONALES,FERIADOS_IO,CALCULO_LOCAL', NULL, NULL,
            N'Proveedor principal de festivos', N'Fuente que se consulta primero para obtener los festivos del año.', NULL, N'Días festivos', 20),
        ('FESTIVOS',      'TIMEOUT_SEGUNDOS',                     1, 1,      60,      NULL,                 NULL, NULL,
            N'Tiempo de espera del proveedor', N'Segundos máximos de espera al consultar el proveedor de festivos.', N'segundos', N'Días festivos', 30),
        ('FESTIVOS',      'ANIOS_ADELANTE',                       1, 0,      3,       NULL,                 NULL, NULL,
            N'Años por adelantado', N'Cuántos años futuros se cargan además del año actual.', N'años', N'Días festivos', 40),
        ('FESTIVOS',      'MINIMO_POR_ANIO',                      1, 10,     30,      NULL,                 'FESTIVOS', 'MAXIMO_POR_ANIO',
            N'Mínimo de festivos por año', N'Cantidad mínima de festivos para considerar válida una carga anual. Debe ser menor que el máximo.', N'festivos', N'Días festivos', 50),
        ('FESTIVOS',      'MAXIMO_POR_ANIO',                      1, 10,     40,      NULL,                 NULL, NULL,
            N'Máximo de festivos por año', N'Cantidad máxima de festivos para considerar válida una carga anual.', N'festivos', N'Días festivos', 60),
        ('ARCHIVO',       'TAMANIO_MAXIMO_BYTES',                 1, 262144, 5242880, NULL,                 NULL, NULL,
            N'Tamaño máximo de un soporte', N'Bytes máximos de cada archivo de soporte de un reclamo. No supera el límite de carga del servidor.', N'bytes', N'Soportes', 10),
        ('ARCHIVOS',      'LIMITE_SUBIDAS_POR_MINUTO',            1, 1,      60,      NULL,                 NULL, NULL,
            N'Límite de subidas por minuto', N'Archivos por minuto que puede subir un mismo usuario.', N'por minuto', N'Soportes', 20),
        ('ARCHIVOS',      'MAXIMO_SOPORTES_POR_RECLAMO',          1, 1,      10,      NULL,                 NULL, NULL,
            N'Máximo de soportes por reclamo', N'Cantidad máxima de archivos de soporte en un mismo reclamo.', N'soportes', N'Soportes', 30),
        ('CARGA_MASIVA',  'MAXIMO_FILAS',                         1, 1,      500,     NULL,                 NULL, NULL,
            N'Máximo de filas por carga', N'Filas máximas de un archivo de carga masiva de cuentas.', N'filas', N'Carga masiva', 10),
        ('CARGA_MASIVA',  'LIMITE_POR_MINUTO',                    1, 1,      20,      NULL,                 NULL, NULL,
            N'Límite de cargas por minuto', N'Cargas masivas por minuto permitidas a un mismo usuario.', N'por minuto', N'Carga masiva', 20),
        ('CARGA_MASIVA',  'TAMANIO_MAXIMO_BYTES',                 1, 10240,  2097152, NULL,                 NULL, NULL,
            N'Tamaño máximo del archivo de carga', N'Bytes máximos del archivo CSV de una carga masiva.', N'bytes', N'Carga masiva', 30)
    ) AS v (grupo, clave, esEditable, valorMinimo, valorMaximo, valoresPermitidos, grupoMenor, claveMenor, etiqueta, descripcion, unidad, categoriaVisual, orden)
    INNER JOIN [dbo].[CatalogoParametro] p ON p.grupo = v.grupo AND p.clave = v.clave
    LEFT JOIN [dbo].[CatalogoParametro] m ON m.grupo = v.grupoMenor AND m.clave = v.claveMenor
) AS Source
ON (Target.parametro = Source.parametro)
WHEN MATCHED THEN
    UPDATE SET Target.esEditable = Source.esEditable, Target.valorMinimo = Source.valorMinimo, Target.valorMaximo = Source.valorMaximo,
               Target.valoresPermitidos = Source.valoresPermitidos, Target.parametroDebeSerMenorQue = Source.parametroDebeSerMenorQue,
               Target.etiqueta = Source.etiqueta, Target.descripcion = Source.descripcion, Target.unidad = Source.unidad,
               Target.categoriaVisual = Source.categoriaVisual, Target.orden = Source.orden
WHEN NOT MATCHED THEN
    INSERT (parametro, esEditable, valorMinimo, valorMaximo, valoresPermitidos, parametroDebeSerMenorQue, etiqueta, descripcion, unidad, categoriaVisual, orden)
    VALUES (Source.parametro, Source.esEditable, Source.valorMinimo, Source.valorMaximo, Source.valoresPermitidos, Source.parametroDebeSerMenorQue,
            Source.etiqueta, Source.descripcion, Source.unidad, Source.categoriaVisual, Source.orden);
GO
USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- CULM-001 D.3 (CONTRACT v2 §4.2): permisos de ejecucion de la edicion de parametros por el administrador (HU168). Solo
-- EXECUTE sobre los tres SP publicos; sin DML ni SELECT directo sobre CatalogoParametroEdicion ni CambioParametro (las
-- vistas uv_parametro_edicion y uv_cambio_parametro las cubre el bucle uv_* de rol_asistencias_runtime.sql). Aditivo e
-- idempotente.
IF DATABASE_PRINCIPAL_ID(N'rol_asistencias_runtime') IS NULL
    CREATE ROLE [rol_asistencias_runtime] AUTHORIZATION [dbo];
GO

IF OBJECT_ID(N'dbo.usp_actualizar_parametro', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_actualizar_parametro] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_parametros_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_parametros_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.usp_consultar_cambios_parametro_paginado', N'P') IS NOT NULL
    GRANT EXECUTE ON [dbo].[usp_consultar_cambios_parametro_paginado] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_parametro_edicion', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_parametro_edicion] TO [rol_asistencias_runtime];
GO
IF OBJECT_ID(N'dbo.uv_cambio_parametro', N'V') IS NOT NULL
    GRANT SELECT ON [dbo].[uv_cambio_parametro] TO [rol_asistencias_runtime];
GO

DECLARE @editables INT = (SELECT COUNT(*) FROM dbo.CatalogoParametroEdicion WHERE esEditable = 1);
DECLARE @historial INT = (SELECT COUNT(*) FROM dbo.CambioParametro);
PRINT CONCAT('MIGRACION 22 UP OK | CatalogoParametroEdicion editables=', @editables, ' | CambioParametro=', @historial, ' | @@TRANCOUNT=', @@TRANCOUNT);
GO
