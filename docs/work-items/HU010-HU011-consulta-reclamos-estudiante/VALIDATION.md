---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# VALIDATION — HU010-HU011-consulta-reclamos-estudiante

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 (ningún objeto congelado modificado) |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre contenedor SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-26 | `TEST_PASS:TEST_CONSULTAS_RECLAMOS_ESTUDIANTE`, `FAILED=0`, `DB GATE PASS`, exit 0 |
| Réplica del gate tras `git merge origin/develop` (KPIs, PR #50), 2026-10-27 | `FREEZE_EXIT=0`, `TEST_PASS:TEST_CONSULTAS_RECLAMOS_ESTUDIANTE`, `FAILED=0`, `DB GATE PASS`; conflicto resuelto en `test_contract_closure.sql` conservando las exclusiones de ambos lados |
| GitHub Actions `DB Quality Gate CI/CD` | en el PR hacia `develop` |

RED: commit `e40edcf` (prueba sin SP). Limitación: prueba manual en la UI pendiente (MV-008).
