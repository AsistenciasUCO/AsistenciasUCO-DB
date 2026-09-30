USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  DB QUALITY GATE - gestionasistenciadb';
PRINT '======================================================================';

:r /tmp/test/test_public_objects.sql
:r /tmp/test/test_contract_closure.sql
:r /tmp/test/test_user_dean_close.sql
:r /tmp/test/test_subject_catalog.sql
:r /tmp/test/test_reactive_academic.sql
:r /tmp/test/test_mass_period_close.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_usp_registrar_docente_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_transaction_ownership.sql
:r /tmp/test/test_usp_crear_actualizar_grupo.sql
:r /tmp/test/test_usp_crear_actualizar_sesion.sql
:r /tmp/test/test_usp_generar_sesiones_grupo.sql
:r /tmp/test/test_group_capacity_decoupling.sql
:r /tmp/test/test_titularidad_jerarquica.sql
:r /tmp/test/test_attendance_commands.sql
:r /tmp/test/test_attendance_review.sql
:r /tmp/test/test_usp_crear_coordinador.sql
:r /tmp/test/test_usp_resolver_solicitud_matricula.sql
:r /tmp/test/test_golden_path_immutability.sql
:r /tmp/test/test_authorized_views_rbac.sql
:r /tmp/test/test_usp_consultar_grupos_paginado.sql
:r /tmp/test/test_usp_consultar_estudiantes_paginado.sql
:r /tmp/test/test_usp_consultar_estudiantes_grupo_paginado.sql
:r /tmp/test/test_usp_consultar_docentes_paginado.sql
:r /tmp/test/test_usp_consultar_sesiones_y_asistencias_paginado.sql
:r /tmp/test/test_usp_consultar_catalogos_y_revisiones_paginado.sql

IF @@TRANCOUNT <> 0
BEGIN
    THROW 51999, 'TEST FAILED: test_suite.sql dejo transacciones abiertas.', 1;
END

PRINT 'TEST PASS: test_suite final @@TRANCOUNT = 0';
PRINT 'TEST_PASS:SUITE_TRANCOUNT_ZERO';
PRINT '======================================================================';
PRINT '  DB QUALITY GATE FINISHED';
PRINT '======================================================================';
GO
