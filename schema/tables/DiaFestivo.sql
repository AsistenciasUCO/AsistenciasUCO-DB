USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
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
