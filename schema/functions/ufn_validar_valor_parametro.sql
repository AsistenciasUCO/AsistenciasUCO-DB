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
