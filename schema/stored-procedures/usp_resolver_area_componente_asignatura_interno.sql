USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_resolver_area_componente_asignatura_interno (P5, 2026-11-04)
--
-- Resuelve el area y el componente de una asignatura por coincidencia EXACTA (sin distinguir mayusculas ni espacios
-- extremos) con el codigo o el nombre registrados en uv_area y uv_componente. Decision de John (2026-11-04): nunca se
-- asigna un area o un componente "cualquiera"; si el valor no existe en la tabla se rechaza con GEN_001.
-- Lo comparten usp_crear_asignatura (ambos obligatorios) y usp_actualizar_asignatura (opcionales: si el valor llega
-- vacio, no se resuelve y el OUTPUT queda NULL para conservar el actual).
-- Solo lectura: no abre transaccion. Expone el triplete OUTPUT (skill procedimientos-internos-condiciones).
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_resolver_area_componente_asignatura_interno]
(
    @area                    NVARCHAR(100),
    @componente              NVARCHAR(100),
    @obligatorios            BIT,
    @idCorrelacion           UNIQUEIDENTIFIER,
    @idArea                  UNIQUEIDENTIFIER OUTPUT,
    @idComponente            UNIQUEIDENTIFIER OUTPUT,
    @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT,
    @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT,
    @estadoResultado         BIT OUTPUT
)
AS
    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @areaDefecto          NVARCHAR(100) = UPPER(TRIM(@area));
    DECLARE @componenteDefecto    NVARCHAR(100) = UPPER(TRIM(@componente));
    DECLARE @entidadFaltante      NVARCHAR(50);

    SELECT
        @idArea = NULL,
        @idComponente = NULL,
        @mensajeUsuarioResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @mensajeTecnicoResultado = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA'),
        @estadoResultado = 1;

BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- PASO 1: Area por codigo o nombre exactos
        IF @areaDefecto IS NOT NULL AND @areaDefecto <> ''
        BEGIN
            SELECT @idArea = a.id FROM dbo.uv_area a
            WHERE UPPER(TRIM(a.codigo)) = @areaDefecto OR UPPER(TRIM(a.nombre)) = @areaDefecto;
        END
        IF @idArea IS NULL AND (@obligatorios = 1 OR (@areaDefecto IS NOT NULL AND @areaDefecto <> ''))
        BEGIN
            SET @entidadFaltante = N'área de conocimiento';
        END

        -- PASO 2: Componente por codigo o nombre exactos (BAS, INS, ESP)
        IF @entidadFaltante IS NULL AND @componenteDefecto IS NOT NULL AND @componenteDefecto <> ''
        BEGIN
            SELECT @idComponente = c.id FROM dbo.uv_componente c
            WHERE UPPER(TRIM(c.codigo)) = @componenteDefecto OR UPPER(TRIM(c.nombre)) = @componenteDefecto;
        END
        IF @entidadFaltante IS NULL AND @idComponente IS NULL
           AND (@obligatorios = 1 OR (@componenteDefecto IS NOT NULL AND @componenteDefecto <> ''))
        BEGIN
            SET @entidadFaltante = N'componente de formación';
        END

        -- PASO 3: Rechazo si alguno no existe (GEN_001)
        IF @entidadFaltante IS NOT NULL
        BEGIN
            EXEC dbo.usp_obtener_mensaje_catalogo
                @p_codigo = 'GEN_001',
                @p_param1 = @entidadFaltante,
                @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
                @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
            SET @mensajeTecnicoResultado = CONCAT(@mensajeTecnicoResultado, ' Correlacion: ', CAST(@idCorrelacionDefecto AS NVARCHAR(50)));
            SELECT @estadoResultado = 0, @idArea = NULL, @idComponente = NULL;
        END
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'SYS_001',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @mensajeTecnicoResultado = dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto);
        SET @estadoResultado = 0;
    END CATCH
END;
GO
