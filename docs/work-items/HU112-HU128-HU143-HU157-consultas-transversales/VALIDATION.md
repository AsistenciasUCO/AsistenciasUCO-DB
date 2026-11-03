---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# VALIDATION — HU112-HU128-HU143-HU157-consultas-transversales

| Comando | Resultado |
|---|---|
| `test/test_consultas_transversales_hu112_hu157.sql` sobre el SQL Server local (2026-11-02) | 8/8 `TEST_PASS` (T-112-01, T-128-01, T-143-01, T-157-01, T-157-02, T-SEC-03, T-PAG-02, T-INT-01) |
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre un contenedor SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-11-03 | `TOTAL_EXECUTED=396`, `PASSED=395`, `FAILED=0`, `SKIPPED=1`, `CRITICAL_MISSING=0`, `DB GATE PASS`, exit 0 |
| GitHub Actions `DB Quality Gate CI/CD` y SonarCloud | success en el PR #79 (2026-11-03; Database Deployment & Quality Gate, SonarCloud), mergeado en `develop` |

Notas:

- El primer intento del gate (2026-11-02) terminó en `Login timeout expired` del contenedor porque corría al mismo tiempo que los gates del backend y del frontend. Repetido solo, pasó completo.
- La BD local de desarrollo tiene un SP suelto, `usp_consultar_asignaturas_paginado`, que no está en `schema/` (se eliminó en el PR #69) y hace fallar `PUBLIC_CANONICAL_RESULTSET` allí. Por eso el gate se valida en un contenedor limpio, no en `sql_server_asistencias`.

Limitación: la prueba en pantalla queda en MV-012 del backend.
