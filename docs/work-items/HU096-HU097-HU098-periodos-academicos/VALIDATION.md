---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-26
---

# VALIDATION — HU096-HU097-HU098-periodos-academicos

| Comando | Resultado |
|---|---|
| `scripts/freeze-manifest.ps1 -Mode Verify` | exit 0 |
| `deploy_schema.ps1` + `test/prepare_lb004d_fixture.ps1` + `test_summary.ps1` sobre contenedor SQL Server 2022 limpio (réplica del job `DB Quality Gate CI/CD`), 2026-10-25 | `FAILED=0`, `DB GATE PASS`, exit 0 |
| GitHub Actions `DB Quality Gate CI/CD` sobre `develop` tras el merge (2026-10-26) | success |

Limitación: prueba manual en la UI pendiente salvo HU081-HU083 (validadas en pantalla por el dueño del producto).
