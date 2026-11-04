---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# VALIDATION — SES-01 (DB)

Rama `fix/ses01-cierre-estricto-asistencia`. Commits: `f1ff9d6` (RED), `99c3649` (fix), `af00b7c` (docs).

| Verificación | Comando / medio | Resultado |
|---|---|---|
| Sintaxis T-SQL de los 3 SP, seed de mensajes, prueba nueva, prueba de asistencia y fixture Java | `SET PARSEONLY ON` vía `sqlcmd` en `sql_server_asistencias` (no compila ni ejecuta; no modifica la base) | PASS (exit 0, sin errores) |
| Manifiesto de congelamiento | `./scripts/freeze-manifest.ps1 -Mode Verify` | PASS: `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11` |
| Suite DB completa (`test_summary.ps1`, incluye 12 IDs `SES01_*` y la regresión de asistencia) | CI del PR (contenedor efímero de GitHub Actions: `deploy_schema.ps1` + `test_summary.ps1`) | **NOT_RUN** localmente; pendiente del CI |
| Ejecución local de la suite contra `sql_server_asistencias` | — | **NOT_RUN**: requiere desplegar los SP en la base compartida; un intento de despliegue transitorio (transacción con `ROLLBACK`) fue bloqueado por la política de permisos. El cambio no se aplica hasta la aprobación del owner DB |
| Carrera en el instante de cierre entre dos conexiones | — | **NOT_RUN** como prueba ejecutable; garantizado por diseño (validación bajo `UPDLOCK, HOLDLOCK` dentro de la transacción y revalidación antes del `COMMIT`); `SES01_WINDOW_LOCK_HELD` verifica el bloqueo |

Limitaciones: `PARSEONLY` no valida nombres de objetos ni semántica. La validación funcional real es el gate del CI.

## Seguimiento del CI del PR #81

En el log del run `41757554598` (SHA `47a5fcc04a4b6fe90d33d366d33563487abdbe6f`), el caso `SES01_AUTO_CLOSED` devolvió la fila canónica con `DBCODE=SES_008`, conservó la correlación, pasó `TEST_STATE_PASS` y no dejó escrituras ni transacciones abiertas. El único fallo fue que el marcador esperado apareció como `o.TEST_EXPECTED_TECH:SES01_AUTO_CLOSED`; el parser exigía `TEST_EXPECTED_TECH:` al inicio absoluto de la línea.

La causa del fallo del gate queda aislada al prefijo literal conservado en la captura combinada de `docker exec`/SQLCMD (`2>&1`) y al anclaje estricto del parser. El log no permite atribuir con certeza esos dos caracteres a SQLCMD, Docker o a la combinación de streams; no hay evidencia de que los emita el procedimiento almacenado. No se cambió el SQL ni se relajaron las aserciones de negocio.

`test_summary.ps1` acepta únicamente el prefijo observado `o.` delante del marcador técnico oficial. Exige una sola apertura y cierre ordenados, una expectativa de usuario, una expectativa técnica, una aserción de estado y una fila canónica; para SES-01 verifica estado, texto del catálogo, `DBCODE` y correlación. La aserción SQL existente sigue comprobando ausencia de escritura y transacción sin residuos.

| Verificación | Comando / medio | Resultado |
|---|---|---|
| Parser de resultados sintético (LF/CRLF y prefijo observado) | `powershell -NoProfile -ExecutionPolicy Bypass -File .\test_summary.ps1 -ParserSelfTestOnly` | PASS: salida limpia y `o.` aceptadas; estado falsificado, fila/marcador duplicado, bloque incompleto, catálogo/código incorrectos y correlación distinta rechazados |
| Manifiesto de congelamiento tras el cambio del parser | `./scripts/freeze-manifest.ps1 -Mode Verify` | PASS: `FREEZE_MANIFEST_OK entries=10 post_freeze_superseded=4 post_freeze_work_item=11` |
| Database Deployment & Quality Gate para el nuevo SHA | CI del PR #81 | PENDIENTE |
