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
