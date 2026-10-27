---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# VALIDATION — HU053-HU054-HU055-solicitudes-ingreso-grupo

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 (ningún objeto congelado modificado) |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-27 | `TEST_PASS:S-01..S-12`, `TEST_PASS:TEST_SOLICITUD_INGRESO_GRUPO`, `FAILED=0`, `SQL_ERROR_COUNT=0`, `DB GATE PASS` |
| GitHub Actions `DB Quality Gate CI/CD` | en el PR hacia `develop` |

RED: commit `c9c6b9a`. Limitación: concurrencia de dos sesiones y prueba en pantalla pendientes (MV-008).
