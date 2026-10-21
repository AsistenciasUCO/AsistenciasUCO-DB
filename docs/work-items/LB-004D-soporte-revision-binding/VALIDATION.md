---
status: active
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# VALIDATION — LB-004D D1 (ONE_TABLE)

Fecha: 2026-10-19. Entorno: SQL Server 2022 Developer, contenedor `sql_server_asistencias`, base
`gestionasistenciadb` (la unica base local; **no se creo ninguna segunda base ni contenedor SQL**).
Base del cambio: `develop` `7d9c050` + rama D0 `4e5e218`.

```text
LB004D_ARCHITECTURE: ONE_TABLE
LB004D_CONTRACT_APPROVED: NO (revision de John pendiente)
DUPLICATE_LOCAL_DB_CREATED: NO
```

## Despliegue local aditivo

1. Respaldo previo verificado: `BACKUP DATABASE ... WITH CHECKSUM, COPY_ONLY` + `RESTORE VERIFYONLY`
   (`The backup set on file 1 is valid`, 2202 paginas) en `/var/opt/mssql/backup` del contenedor.
2. Archivos aplicados individualmente (sin recrear nada): `ArchivoSoporte.sql`, `zz_foreign_keys.sql`,
   `15_lb004d_archivo_soporte.sql`, los cuatro SP y `rol_asistencias_runtime_lb004d.sql`.
   Idempotencia: `ArchivoSoporte.sql` y `zz_foreign_keys.sql` se ejecutaron mas de una vez sin error;
   los SP usan `CREATE OR ALTER`; el seed usa `MERGE`.
3. Deriva previa de la base local (no causada por LB-004D): `usp_crear_facultad` /
   `usp_crear_facultad_interno` (HU116, ya en `develop`) no estaban desplegados y detenian la suite
   (`too many arguments specified`). Se aplicaron esos dos archivos del repo para alinear la base
   con `develop`; no se aplico el despliegue completo.
4. No se ejecuto `DROP`, `docker compose down -v`, restauracion ni cambio de credenciales o puertos.

## Resultados

| Comprobacion | Comando | Resultado |
|---|---|---|
| RED (antes de desplegar) | `test_lb004d_support_binding.sql` con la tabla ausente | `TEST FAILED: LB004D_SCHEMA_SHAPE` (rojo esperado) |
| GREEN SQL | mismo archivo tras el despliegue | 17 `TEST_PASS:LB004D_*`, exit 0 |
| Concurrencia (2 conexiones) | `test/test_lb004d_concurrency.ps1` | W1 concurrente idempotente, W2 una sola ganadora, fixture limpiado: PASS |
| Suite completa | `test_summary.ps1` | `DB GATE PASS`: 247 PASSED, 0 FAILED, 1 skip permitido, `SQL_ERROR_COUNT=0` |
| Golden Path | `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED` | PASS (`FREEZE_MANIFEST_OK entries=10`) |
| Manifest LB-004D | `scripts/lb004d-manifest.ps1 -Mode Verify` | `LB004D_MANIFEST_OK entries=9` |
| Higiene de secretos | gates `NO_HARDCODED_DB_PASSWORD`, `SECRET_GATE_*` en la suite | PASS |

## Hallazgo tecnico registrado durante la validacion

`@@ROWCOUNT` de un `UPDATE` no es una postcondicion fiable cuando un trigger `INSTEAD OF` anula la
escritura: `usp_radicar_solicitud_revision_asistencia_v2` verifica por lectura que el soporte quedo
`ATTACHED` a la solicitud nueva y, si no, revierte la solicitud (`ARC_001`). Cubierto por
`LB004D_W2_ATOMIC_ROLLBACK`.

## No ejecutado en este entorno (honesto)

| Gate | Estado | Motivo |
|---|---|---|
| Despliegue en base vacia (`deploy_schema.ps1` completo) | NOT_RUN localmente | Requeriria una segunda base; lo cubre el job de CI con SQL Server efimero |
| SonarCloud / Trivy | NOT_RUN localmente | Corren en el CI del PR; no se declaran PASS sin evidencia remota |
| Reconciliacion `DRAFT -> ORPHAN` por SP | DEFERIDA | Q6 (ventana de producto e identidad tecnica) |
