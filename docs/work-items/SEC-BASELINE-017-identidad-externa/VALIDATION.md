# VALIDATION — SEC-BASELINE-017

Fecha: 2026-10-26. Entorno: SQL Server 2022 (contenedor desechable, esquema completo desplegado con `deploy_schema.ps1`).

| Prueba | Comando | Resultado |
|---|---|---|
| Prueba nueva | `sqlcmd -b -i test/test_sec_baseline_identidad_externa.sql` | PASS (`EXTERNAL_IDENTITY_LINK/CONFLICTS/REVOCATION`) |
| Migración | `06_..._up` → `down` → `up` → `up` | PASS (idempotente; índice filtrado y FK presentes) |
| Suite completa | `test_summary.ps1` (con `prepare_lb004d_fixture.ps1`) | PASS: executed=301, passed=300, failed=0, critical_missing=0 |
| Contrato 4 columnas | `test_contract_closure.sql` (dentro de la suite) | PASS tras reducir ambos SP al resultado canónico |

Casos cubiertos: primera vinculación, repetición idempotente (incluso con otro correo), usuario inexistente, usuario inactivo,
emisor vacío, dos identidades sobre una cuenta, una identidad sobre dos cuentas, otro emisor, revocación, revocación idempotente,
no reutilización tras revocar, revocar inexistente y nueva identidad tras revocar.

No ejecutado aquí: carrera concurrente real entre dos sesiones (cubierta solo por los índices únicos y la captura 2601/2627).
