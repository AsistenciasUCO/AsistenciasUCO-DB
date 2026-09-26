# DB-GP-001C - Test plan

| Gate ID | Archivo | Verifica |
| --- | --- | --- |
| RBAC_AUTH_VIEWS_FAIL_CLOSED_DEFINITION | test/test_authorized_views_rbac.sql | Inventario 12 vistas; DIRECT exigen `IS NOT NULL`, INHERITS referencian otra auth view; sin bypass `IS NULL` |
| RBAC_NULL_CONTEXT_NO_ROWS | idem | Contexto NULL => 0 filas en TODAS las `uv_auth_*` (cursor dinamico) + control de vistas base no vacias |
| RBAC_UNKNOWN_CONTEXT_NO_ROWS | idem | UUID inexistente => 0 filas en todas |
| RBAC_ADMIN / DECANO / COORDINADOR / DOCENTE / ESTUDIANTE_* | idem | Alcance exacto (positivo y sin fugas), fixtures obligatorios (sin PASS vacuo) |
| RBAC_INACTIVE_USER_NO_BROADER_SCOPE | idem | Administrador inactivo (estado=0 en transaccion revertida) no supera su institucion; no se inventa regla nueva |
| USP_CONSULTAR_GRUPOS_PAGINADO_CONTEXT_CLEANUP | test/test_usp_consultar_grupos_paginado.sql | Caso A: previo NULL => sigue NULL |
| ..._CONTEXT_PREVIOUS_VALUE_RESTORED | idem | Caso B: previo A, SP con B => durante B, despues A |
| ..._CONTEXT_RESTORED_ON_EXCEPTION | idem | Caso C: falla inyectada dentro del TRY => previo restaurado, vista revertida |
| ..._NO_CONTEXT_LEAK | idem | Caso D: 0 fugas en ejecuciones sucesivas, sin sleeps |
| GOLDEN_PATH_VIEW_SHAPES_FROZEN / SP_SIGNATURES_FROZEN / MUTATION_RESULTSET_FROZEN | test/test_golden_path_immutability.sql | Shapes de 5 vistas y firmas de 4 SP vs baseline |
| GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED | scripts/freeze-manifest.ps1 | SHA-256 de contrato + fuentes Golden Path |
| NO_HARDCODED_DB_PASSWORD | scripts/secret-hygiene.ps1 | Scripts, workflows, `.env.*`, config versionada; reporta archivo:linea:tipo, nunca el valor |
| SECRET_GATE_COVERS_ENV_TEMPLATES | idem | `.env.template`/`.env.example`/workflows/scripts estan en la lista escaneada |
| SECRET_GATE_DETECTS_UNSAFE_TEMPLATE / ACCEPTS_PLACEHOLDER | idem | Autoprueba causal con fixtures sinteticos TEST_ONLY generados en runtime |

Fixtures: solo valores TEST_ONLY; ningun test contiene ni imprime credenciales.
