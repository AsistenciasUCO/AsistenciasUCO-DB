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
