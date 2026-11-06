USE [gestionasistenciadb];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- HU176B (D2 rotativo): ventanas de matricula que ya deben rotar su token (uv_token_matricula_grupo.debeRotar = 1).
-- Uso exclusivo del job de rotacion del backend; sin ejecutor (consulta tecnica, sin datos personales ni credenciales).
-- Acotada por el parametro MATRICULA_QR/LOTE_ROTACION.
-- READ_QUERY_RESULTSET: NON_GOLDEN_PATH_EXTENSION (ver test/test_contract_closure.sql).
CREATE OR ALTER PROCEDURE [dbo].[usp_consultar_ventanas_matricula_por_rotar]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @lote INT = dbo.ufn_obtener_parametro_int(NULL, 'MATRICULA_QR', 'LOTE_ROTACION');

    SELECT TOP (@lote)
        idGrupo         = v.grupo,
        idDocenteEmisor = v.docenteEmisor
    FROM dbo.uv_token_matricula_grupo v
    WHERE v.debeRotar = 1
    ORDER BY v.fechaRotacionUtc ASC;
END;
GO
