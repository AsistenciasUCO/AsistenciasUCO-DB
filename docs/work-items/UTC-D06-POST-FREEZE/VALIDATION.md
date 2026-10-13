# VALIDATION — UTC-D06-POST-FREEZE: remediation and certification

## Executed evidence (2026-10-10)

| Environment | Command | Exit | Result |
|---|---|---:|---|
| Isolated SQL Server 2022 Developer `utc_d06_sqltest` | `./test_summary.ps1 -ContainerName utc_d06_sqltest -Password <redacted>` | 0 | `TOTAL_EXECUTED=179`, `PASSED=178`, `FAILED=0`, `SKIPPED=1`, `ALLOWED_SKIPPED=1`, `DB GATE PASS`. |
| Isolated SQL Server 2022 Developer `utc_d06_sqltest` | `./test/verify_runtime_role_login.ps1 -ContainerName utc_d06_sqltest -AdminPassword <redacted>` | 0 | Explicit required-object EXECUTE grants pass; direct DML and internal-SP execution are denied to a temporary non-admin SQL login. |
| Isolated SQL Server 2022 Developer `utc_d06_sqltest` | `./test/prepare_java_integration_fixture.ps1 -ContainerName utc_d06_sqltest -AdminPassword <redacted>` | 0 | Reproducible public-SP fixture exposes two attendance-detail rows for Java JPA/JDBC parity. |

## Migration, restore, and rollback

- **Applied only in the isolated container:** redeployed `usp_resolver_solicitud_revision_asistencia`, regenerated the post-freeze manifest, then ran the full SQL gate. No primary database was contacted.
- **Migration order for an owner-controlled environment:** deploy the D06 baseline; deploy the idempotent `Estado` seed (including `P`); deploy the corrected resolver; deploy the explicit runtime-role grants; regenerate/verify the manifest; execute the SQL gate and non-admin login certification.
- **Restore:** recreate the isolated Developer database from the approved D06 baseline and rerun the migration order above. No backup or restore operation was performed against a shared or production database.
- **Rollback:** an owner must approve and deploy the previously approved DB revision. Do not drop UTC-D06 columns/views/wrappers or reintroduce schema-wide `EXECUTE` as an emergency shortcut. The test fixture and temporary runtime login are independently removable.

## Current status

`PARTIAL / remediation complete within authorized DB scope`. The full SQL contract gate and non-administrative runtime-login certification pass. `CC-003G-01` remains a contract blocker for the two absent public providers, so the combined backend/SQL integration gate cannot be declared green.
