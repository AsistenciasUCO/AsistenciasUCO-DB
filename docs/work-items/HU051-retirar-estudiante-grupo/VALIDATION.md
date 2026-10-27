---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# VALIDATION — HU051-retirar-estudiante-grupo

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 (ningún objeto congelado modificado) |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-27 | `TEST_PASS:R-01..R-09`, `FAILED=0`, `DB GATE PASS`, exit 0 |
| GitHub Actions `DB Quality Gate CI/CD` | en el PR hacia `develop` |

RED: commit `64c63fe`. Limitación: prueba manual en pantalla pendiente (MV-008).
