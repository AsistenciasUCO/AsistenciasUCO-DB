---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# VALIDATION — HU061-HU147-HU153-HU172-consolidado-auditoria-catalogos

| Comando | Resultado |
|---|---|
| `test/test_consolidado_auditoria_catalogos.sql` sobre el SQL Server local (2026-11-04) | `TEST_PASS` en T-061-01, T-172-01, T-147-01, T-153-01, T-P5-01, T-ASI-01 y T-PAG-03 |
| `test/test_subject_catalog.sql` y `test/test_rec2_rbac_asignatura.sql` sobre el SQL Server local | Todos los `SUBJECT_*` y `REC2_RA01` a `RA05` en `TEST_PASS` |
| `scripts/generar-catalogo-mensajes.ps1` | Catálogo regenerado con `ASI_001` (153 códigos) |
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` en un contenedor SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-11-04 | `TOTAL_EXECUTED=421`, `PASSED=420`, `FAILED=0`, `SKIPPED=1` (permitido), `CRITICAL_MISSING=0`, `DB GATE PASS`, exit 0 |

Notas:

- La primera corrida del gate marcó `SES01_AUTO_CLOSED` como faltante, aunque la prueba imprimió `TEST_STATE_PASS`. El motivo fue una línea de la salida mezclada (`ked sđTEST_EXPECTED_TECH…`), en una prueba que este work item no toca. En la segunda corrida, sobre un contenedor nuevo, pasó completa.
- T-ASI-01 no ejecuta el caso del plan de otro programa porque el seed tiene un solo programa con plan. Ese caso lo cubre RA-05 en `test_rec2_rbac_asignatura.sql`, que crea sus propios programas.

Limitación: la prueba en pantalla queda en MV-013 del ledger del backend.
