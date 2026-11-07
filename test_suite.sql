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
:r /tmp/test/test_uv_tipo_programa_contrato.sql
:r /tmp/test/test_uv_area_contrato.sql
:r /tmp/test/test_user_dean_close.sql
:r /tmp/test/test_subject_catalog.sql
:r /tmp/test/test_rec2_rbac_asignatura.sql
:r /tmp/test/test_reactive_academic.sql
:r /tmp/test/test_mass_period_close.sql
:r /tmp/test/test_usp_registrar_estudiante_en_grupo_usuario_no_existente.sql
:r /tmp/test/test_transaction_ownership.sql
:r /tmp/test/test_usp_sincronizar_usuario.sql
:r /tmp/test/test_usp_registrar_o_actualizar_plan_estudio.sql
:r /tmp/test/test_usp_plan_estudio_estado_semestres.sql
:r /tmp/test/test_usp_periodo_academico_gestion.sql
:r /tmp/test/test_consultas_coordinador_programa.sql
:r /tmp/test/test_consultas_decano_facultad.sql
:r /tmp/test/test_consultas_transversales_hu112_hu157.sql
:r /tmp/test/test_consolidado_auditoria_catalogos.sql
:r /tmp/test/test_consultas_reclamos_estudiante.sql
:r /tmp/test/test_usp_retirar_estudiante_grupo.sql
:r /tmp/test/test_solicitud_ingreso_grupo.sql
:r /tmp/test/test_usp_consultar_perfil_usuario.sql
:r /tmp/test/test_runtime_grants_backend_inventory.sql
:r /tmp/test/test_usp_consultar_historial_grupos_docente_programa.sql
:r /tmp/test/test_usp_consultar_resumen_docentes_programa.sql
:r /tmp/test/test_usp_consultar_oferta_grupos_estudiante.sql
:r /tmp/test/test_hu008_regla_inscripcion_programa.sql
:r /tmp/test/test_int_hu01_reactivar_matricula_retirada.sql
:r /tmp/test/test_usp_crear_actualizar_grupo.sql
:r /tmp/test/test_usp_crear_actualizar_sesion.sql
:r /tmp/test/test_usp_validar_sesion_operacion_interno.sql
:r /tmp/test/test_maint_003k_error_priority.sql
:r /tmp/test/test_usp_generar_sesiones_grupo.sql
:r /tmp/test/test_group_capacity_decoupling.sql
:r /tmp/test/test_titularidad_jerarquica.sql
:r /tmp/test/test_attendance_commands.sql
:r /tmp/test/test_ses01_ventana_asistencia.sql
:r /tmp/test/test_attendance_review.sql
:r /tmp/test/test_ses04_reclamo_justificada.sql
:r /tmp/test/test_rec3_falla_intermedia_transaccion.sql
:r /tmp/test/test_lb004d_support_binding.sql
:r /tmp/test/test_usp_crear_coordinador.sql
:r /tmp/test/test_usp_actualizar_coordinador.sql
:r /tmp/test/test_usp_corregir_identidad_usuario.sql
:r /tmp/test/test_usp_cambiar_estado_coordinador.sql
:r /tmp/test/test_hu121_hu122_esquema_coordinador.sql
:r /tmp/test/test_sec_baseline_identidad_externa.sql
:r /tmp/test/test_migracion_docente_programa.sql
:r /tmp/test/test_usp_vincular_docente_programa.sql
:r /tmp/test/test_usp_consultar_docentes_programa.sql
:r /tmp/test/test_usp_consultar_candidatos_docente_programa.sql
:r /tmp/test/test_usp_actualizar_docente_programa.sql
:r /tmp/test/test_usp_cambiar_estado_docente_programa.sql
:r /tmp/test/test_cruce_horario_docente.sql
:r /tmp/test/test_usp_guardar_horarios_grupo.sql
:r /tmp/test/test_usp_consultar_oferta_creacion_grupo_docente.sql
:r /tmp/test/test_usp_precargar_sesiones_grupo.sql
:r /tmp/test/test_golden_path_immutability.sql
:r /tmp/test/test_utc_d06_readonly_contract.sql
:r /tmp/test/test_utc_d06_procedencia_temporal.sql
:r /tmp/test/test_authorized_views_rbac.sql
:r /tmp/test/test_usp_consultar_grupos_paginado.sql
:r /tmp/test/test_usp_crear_programa_academico.sql
:r /tmp/test/test_usp_actualizar_programa_academico.sql
:r /tmp/test/test_usp_cambiar_estado_programa_academico.sql
:r /tmp/test/test_usp_consultar_programas_academicos.sql
:r /tmp/test/test_uv_estudiante_programa_no_duplicates.sql
:r /tmp/test/test_usp_consultar_detalle_solicitud_revision_docente.sql
:r /tmp/test/test_usp_consultar_sesiones_y_asistencias_paginado.sql
:r /tmp/test/test_ufn_clasificar_permanencia.sql
:r /tmp/test/test_uv_resumen_asistencia_estudiante_grupo.sql
:r /tmp/test/test_usp_consultar_kpis_coordinador.sql
:r /tmp/test/test_usp_consultar_alerta_temprana_programa.sql
:r /tmp/test/test_usp_consultar_bitacora_estudiante_programa.sql
:r /tmp/test/test_usp_consultar_ficha_estudiante_programa.sql
:r /tmp/test/test_usp_resolvers_decano.sql
:r /tmp/test/test_usp_consultar_kpis_decano.sql
:r /tmp/test/test_usp_consultar_comparativa_programas_facultad.sql
:r /tmp/test/test_usp_consultar_aforo_grupos_facultad.sql
:r /tmp/test/test_usp_resolvers_institucion_admin.sql
:r /tmp/test/test_usp_consultar_kpis_institucion.sql
:r /tmp/test/test_usp_consultar_comparativa_facultades.sql
:r /tmp/test/test_usp_consultar_tendencia_ausentismo.sql
:r /tmp/test/test_usp_registrar_notificacion_saliente.sql
:r /tmp/test/test_usp_reservar_notificaciones_salientes.sql
:r /tmp/test/test_usp_marcar_notificacion_entregada.sql
:r /tmp/test/test_usp_registrar_fallo_notificacion.sql
:r /tmp/test/test_usp_depurar_notificaciones_salientes.sql
:r /tmp/test/test_notificacion_migracion_catalogo.sql
:r /tmp/test/test_notif002a_plantillas_contacto.sql
:r /tmp/test/test_ident001_correo_verificacion.sql
:r /tmp/test/test_usp_abrir_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_cerrar_ventana_matricula_grupo.sql
:r /tmp/test/test_usp_rotar_token_matricula_grupo.sql
:r /tmp/test/test_usp_validar_token_matricula_publico.sql
:r /tmp/test/test_usp_matricular_estudiante_por_token.sql
:r /tmp/test/test_culm001_a_retiro_solicitudes.sql

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
