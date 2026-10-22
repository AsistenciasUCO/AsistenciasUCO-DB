USE [gestionasistenciadb];
GO

SET NOCOUNT ON;

PRINT '======================================================================';
PRINT '  DB QUALITY GATE - gestionasistenciadb';
PRINT '======================================================================';

:r /tmp/test/test_public_objects.sql
:r /tmp/test/test_contract_closure.sql
:r /tmp/test/test_usp_crear_facultad.sql
:r /tmp/test/test_usp_actualizar_facultad.sql
:r /tmp/test/test_usp_cambiar_estado_facultad.sql
:r /tmp/test/test_user_dean_close.sql
:r /tmp/test/test_subject_catalog.sql
:r /tmp/test/test_reactive_academic.sql
:r /tmp/test/test_mass_period_close.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_autonomo.sql
:r /tmp/test/test_usp_registrar_docente_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_usp_registrar_docente_en_grupo_autonomo.sql
:r /tmp/test/test_transaction_ownership.sql
:r /tmp/test/test_usp_sincronizar_usuario.sql
:r /tmp/test/test_usp_registrar_o_actualizar_plan_estudio.sql
:r /tmp/test/test_usp_crear_actualizar_grupo.sql
:r /tmp/test/test_usp_crear_actualizar_sesion.sql
:r /tmp/test/test_usp_validar_sesion_operacion_interno.sql
:r /tmp/test/test_maint_003k_error_priority.sql
:r /tmp/test/test_usp_generar_sesiones_grupo.sql
:r /tmp/test/test_group_capacity_decoupling.sql
:r /tmp/test/test_titularidad_jerarquica.sql
:r /tmp/test/test_attendance_commands.sql
:r /tmp/test/test_attendance_review.sql
:r /tmp/test/test_lb004d_support_binding.sql
:r /tmp/test/test_usp_crear_coordinador.sql
:r /tmp/test/test_usp_resolver_solicitud_matricula.sql
:r /tmp/test/test_golden_path_immutability.sql
:r /tmp/test/test_utc_d06_readonly_contract.sql
:r /tmp/test/test_utc_d06_procedencia_temporal.sql
:r /tmp/test/test_authorized_views_rbac.sql
:r /tmp/test/test_usp_consultar_grupos_paginado.sql
:r /tmp/test/test_uv_estudiante_programa_no_duplicates.sql

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
