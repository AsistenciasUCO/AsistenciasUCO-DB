USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- usp_consultar_candidatos_docente_programa (HU091, picker de docentes existentes)
--
-- Resultset: READ_QUERY_RESULTSET con datos MINIMOS (D4, sin correo): idDocente, idUsuario,
-- codigoTipoIdentificacion, numeroIdentificacion, nombreCompleto. Candidato = docente activo con vinculo
-- en algun programa de la MISMA institucion del programa, sin vinculo con @idPrograma. Maximo de filas por
-- parametro DOCENTE/MAX_CANDIDATOS_BUSQUEDA; minimo de caracteres DOCENTE/BUSQUEDA_MIN_CARACTERES (DOC_007).
-- La uv_docente_programa se lee sin contexto de ejecutor porque la autorizacion es explicita (RBAC +
-- titularidad del programa) y el filtro de institucion se aplica aqui.
-- ============================================================================
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_candidatos_docente_programa]
(
    @idUsuarioEjecutor  UNIQUEIDENTIFIER,
    @idCorrelacion      UNIQUEIDENTIFIER,
    @idPrograma         UNIQUEIDENTIFIER,
    @busqueda           NVARCHAR(50)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @idCorrelacionDefecto UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idCorrelacion, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idUsuarioDefecto     UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idUsuarioEjecutor, 'GENERAL', 'GUID_DEFECTO_CORRELACION');
    DECLARE @idProgramaDefecto    UNIQUEIDENTIFIER = dbo.ufn_obtener_parametro_guid(@idPrograma, 'GENERAL', 'GUID_DEFECTO_CORRELACION');

    DECLARE @maximo INT = dbo.ufn_obtener_parametro_int(NULL, 'DOCENTE', 'MAX_CANDIDATOS_BUSQUEDA');
    DECLARE @minimoCaracteres INT = dbo.ufn_obtener_parametro_int(NULL, 'DOCENTE', 'BUSQUEDA_MIN_CARACTERES');
    DECLARE @texto NVARCHAR(50) = NULLIF(TRIM(@busqueda), '');
    DECLARE @textoEscapado NVARCHAR(110) = REPLACE(REPLACE(REPLACE(@texto, '\', '\\'), '%', '\%'), '_', '\_');
    DECLARE @soloDigitos BIT = IIF(@texto IS NOT NULL AND @texto NOT LIKE '%[^0-9]%', 1, 0);
    DECLARE @patron NVARCHAR(120) = IIF(@texto IS NULL, NULL, IIF(@soloDigitos = 1, CONCAT(@textoEscapado, '%'), CONCAT('%', @textoEscapado, '%')));
    DECLARE @idInstitucion UNIQUEIDENTIFIER;

    DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
    DECLARE @estadoResultado BIT = 1;

    EXEC dbo.usp_validar_id_correlacion_esta_presente_interno
        @idCorrelacion = @idCorrelacionDefecto,
        @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
        @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
        @estadoResultado = @estadoResultado OUTPUT;

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_permiso_rbac_usuario_interno
            @idUsuario = @idUsuarioDefecto,
            @codigoPerfilRequerido = 'COORDINADOR',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1
    BEGIN
        EXEC dbo.usp_validar_titularidad_jerarquica_interno
            @idUsuario = @idUsuarioDefecto,
            @idEntidadPadre = @idProgramaDefecto,
            @tipoEntidadPadre = 'PROGRAMA',
            @idCorrelacion = @idCorrelacionDefecto,
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT,
            @estadoResultado = @estadoResultado OUTPUT;
    END

    IF @estadoResultado = 1 AND (@texto IS NULL OR LEN(@texto) < @minimoCaracteres)
    BEGIN
        EXEC dbo.usp_obtener_mensaje_catalogo
            @p_codigo = 'DOC_007',
            @mensajeUsuarioResultado = @mensajeUsuarioResultado OUTPUT,
            @mensajeTecnicoResultado = @mensajeTecnicoResultado OUTPUT;
        SET @estadoResultado = 0;
    END

    IF @estadoResultado = 0
    BEGIN
        THROW 51000, @mensajeTecnicoResultado, 1;
    END

    SELECT @idInstitucion = idInstitucion FROM dbo.uv_programa WHERE id = @idProgramaDefecto;

    SELECT TOP (@maximo)
        c.idDocente,
        c.idUsuario,
        c.codigoTipoIdentificacion,
        c.numeroIdentificacion,
        c.nombreCompleto
    FROM (
        SELECT DISTINCT d.idDocente, d.idUsuario, d.codigoTipoIdentificacion, d.numeroIdentificacion, d.nombreCompleto
        FROM dbo.uv_docente_programa d
        WHERE d.idInstitucion = @idInstitucion
          AND d.estaActivoUsuario = 1
          AND NOT EXISTS (SELECT 1 FROM dbo.DocentePrograma x WHERE x.docente = d.idDocente AND x.programa = @idProgramaDefecto)
          AND (
                (@soloDigitos = 1 AND CAST(d.numeroIdentificacion AS NVARCHAR(12)) LIKE @patron ESCAPE '\')
                OR (@soloDigitos = 0 AND d.nombreCompleto LIKE @patron ESCAPE '\')
              )
    ) c
    ORDER BY c.nombreCompleto ASC, c.idDocente ASC;
END;
GO
