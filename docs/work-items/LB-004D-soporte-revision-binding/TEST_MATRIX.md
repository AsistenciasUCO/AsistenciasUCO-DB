---
status: proposed
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# LB-004D — Matriz de pruebas

Ninguna prueba está escrita ni ejecutada. Estado de todas las filas: `NOT_RUN`. Las pruebas SQL se
escriben en RED (`test/test_lb004d_support_binding.sql`, incluido en `test_suite.sql`) **después**
de aprobar el contrato y **antes** de implementar. Cada caso usa fixture dentro de una transacción
con `ROLLBACK` y verifica `@@TRANCOUNT = 0` y que no queden filas.

## 1. SQL (D1) — repo DB

| ID | Requisito del encargo | Escenario | Esperado |
|---|---|---|---|
| DB-01 | Archivo propio y válido | W1 de un estudiante; v2 con ese `fileId` sobre su sesión | `DRAFT` → `ATTACHED`, solicitud `P`, 2 transiciones, 4 campos `estadoResultado = 1` |
| DB-02 | Archivo ajeno | Estudiante B radica con `fileId` de A | `estadoResultado = 0`, `ARC_001`, sin solicitud, A sigue `DRAFT` |
| DB-03 | Doble asociación | Segunda v2 con un `fileId` ya `ATTACHED` (otra correlación) | `ARC_001`, sin segunda solicitud |
| DB-04 | Docente titular | R1 con el usuario del `Grupo.docente`; R2 lista el reclamo con soporte | 1 fila, `relacionAcceso = DOCENTE_TITULAR`; R2 incluye `idArchivoSoporte` |
| DB-05 | Docente no titular | R1 y R2 con otro docente | 0 filas en ambos |
| DB-06 | Otros actores | R1 con otro estudiante del **mismo** grupo, administrador, coordinador y decano | 0 filas en todos (no hereda `uv_auth_grupo`) |
| DB-07 | Propietario | R1 del propietario en `DRAFT` y en `ATTACHED` | 1 fila, `PROPIETARIO`; en `ORPHAN` 0 filas |
| DB-08 | Revisión/sesión inexistente | v2 con sesión inexistente y `fileId` válido | Rechazo; archivo sigue `DRAFT` |
| DB-09 | Matrícula/grupo inválido | v2 de un estudiante no matriculado en el grupo de la sesión | Rechazo; sin solicitud; archivo `DRAFT` |
| DB-10 | Estudiante ≠ ejecutor | v2 con `@idEstudiante` de otro y ejecutor propio | `ARC_005`; sin escritura |
| DB-11 | Concurrencia attach | Dos sesiones SQL radican con el mismo `fileId` (script con dos conexiones / `sp_getapplock` de sincronización) | Exactamente 1 solicitud con soporte; la otra `ARC_001` |
| DB-12 | Concurrencia attach vs orphan | W3 y v2 concurrentes sobre el mismo `DRAFT` | Estado final `ATTACHED` **u** `ORPHAN`, nunca ambos; si `ORPHAN`, sin solicitud con soporte |
| DB-13 | Rollback | Forzar error tras el `INSERT` de la solicitud (fixture que invalida el `UPDATE`) | Sin solicitud, archivo `DRAFT`, sin transición `ADJUNCION`, `@@TRANCOUNT = 0` |
| DB-14 | Idempotencia W1 | W1 repetido idéntico; W1 mismo `fileId` con otro checksum; W1 mismo `fileId` por otro estudiante | 1 fila; segundo y tercero `ARC_002` sin cambios |
| DB-15 | Idempotencia W2 | v2 repetida con la misma correlación tras éxito | Éxito, sigue habiendo 1 solicitud |
| DB-16 | Integridad referencial | `INSERT` directo con usuario/solicitud inexistente; `ATTACHED` sin solicitud; segundo `ATTACHED` en la misma solicitud | Violación de FK / `CK` / índice único filtrado |
| DB-17 | Reclamo sin soporte | v2 sin `@idArchivoSoporte` | Solicitud `P`; R2 con columnas de soporte `NULL` |
| DB-18 | Metadata inválida | Tipo no permitido, tamaño 0, > 5 MiB, almacenado > original, checksum no hex, comprimido sin algoritmo | `ARC_003`, sin escritura |
| DB-19 | Perfil RBAC | W1/v2 con ejecutor docente | Rechazo de perfil |
| DB-20 | Reconciliación | W3 con corte posterior sobre `DRAFT`; repetido; sobre `ATTACHED`; sin `@fechaCorteUtc` | `ORPHAN`; idempotente; rechazo sin cambio; rechazo |
| DB-21 | Modo "registrado" | R3 con un JSON de ids conocidos y desconocidos | `registrado` 1/0 correcto |
| DB-22 | UTC | Fechas de W1/W2/W3 | Dentro de `[SYSUTCDATETIME() antes, después]` |
| DB-23 | v1 intacta | Suite actual completa (`test_attendance_review.sql`, `test_contract_closure.sql`, manifest Golden Path) | Igual que antes; manifest `GOLDEN_PATH_FREEZE_MANIFEST_VERIFIED` |
| DB-24 | Contrato de resultset | `test_contract_closure.sql` | W1/W2/W3 con 4 columnas canónicas; R1/R2/R3 como `READ_QUERY_RESULTSET` |
| DB-25 | Mínimo privilegio | Login temporal con `rol_asistencias_runtime` | `EXECUTE` en W1, v2, R1, R2; denegado `SELECT/INSERT/UPDATE` en tablas nuevas; W3/R3 según Q6 |
| DB-26 | Manifest LB-004D | `freeze-manifest.ps1 -Mode Verify` del manifest nuevo | Verificado |

Gates D1: `test_summary.ps1` 100 % (más los skips permitidos actuales), Golden Path, SonarCloud y
Trivy del PR en verde.

## 2. Backend (B1) — repo backend

| ID | Escenario | Nivel | Esperado |
|---|---|---|---|
| BE-01 | Subida válida: W1 llamado con owner del JWT | unit + IT SQL/MinIO/ClamAV reales | 201; fila `DRAFT`; objeto en MinIO |
| BE-02 | W1 rechazado | unit | `FileStoragePort.delete` invocado; 5xx/4xx según contrato |
| BE-03 | W1 con resultado desconocido | unit | reintento idempotente; **sin** delete |
| BE-04 | Radicación con `soporteArchivoId` propio | IT HTTP | 202; R1 del docente titular devuelve fila |
| BE-05 | `soporteArchivoId` ajeno, usado o inexistente | IT HTTP | 404 idéntico en los tres |
| BE-06 | Descarga docente titular | IT HTTP | 200; bytes originales; SHA-256 igual |
| BE-07 | Docente no titular, otro estudiante, administrador, coordinador | IT HTTP | 404; MinIO **no** consultado (spy en unit) |
| BE-08 | Checksum SQL ≠ bytes | unit | sin bytes en respuesta; 5xx genérico |
| BE-09 | Sin Bearer | IT HTTP | 401 |
| BE-10 | Nombre > 250 | unit | 400 |
| BE-11 | `GET /docente/reclamos` | IT HTTP | lista del titular con datos del soporte; vacío para no titular |
| BE-12 | Arquitectura | ArchUnit | puerto de metadata en Application; adapters JPA en Infrastructure; sin JDBC; sin bucket/objectKey fuera de Infrastructure |

## 3. Frontend (F1) — repo frontend

| ID | Escenario | Esperado |
|---|---|---|
| FE-01 | Selección PDF/PNG/JPEG; otro tipo | Aceptado / rechazado antes de enviar |
| FE-02 | Archivo > 5 MiB | Mensaje visible con el límite; sin petición |
| FE-03 | Subida | `HttpClient` con Bearer por interceptor; guarda `fileId` |
| FE-04 | Malware (400), storage (5xx), 401, 404 | Mensajes claros y distintos |
| FE-05 | Radicación con y sin soporte | Envía `soporteArchivoId` o nada; nunca `soporteUrl` |
| FE-06 | Descarga docente | Blob autenticado; sin URL de MinIO ni token en la URL |
| FE-07 | Roles | Estudiante sube/radica; docente descarga; otros sin acción |

## 4. E2E final (servicios reales)

Keycloak, SQL Server, MinIO, ClamAV, backend y Angular reales. No se declara `PASS` sin ejecutarlo.

| ID | Paso | Esperado |
|---|---|---|
| E2E-01 | Estudiante selecciona soporte | — |
| E2E-02 | Backend valida y ClamAV analiza | CLEAN |
| E2E-03 | MinIO almacena | objeto `soportes/<fileId>` |
| E2E-04 | SQL vincula | fila `ATTACHED` con la solicitud |
| E2E-05 | Docente titular consulta el reclamo | aparece con soporte |
| E2E-06 | Descarga | 200 |
| E2E-07 | SHA-256 | igual al del archivo subido |
| E2E-08 | Docente no titular | 404 |
| E2E-09 | Estudiante ajeno | 404 |
| E2E-10 | Reinicio del backend | soporte sigue disponible |
| E2E-11 | EICAR sintético | rechazado; sin objeto ni fila |
| E2E-12 | MinIO o ClamAV caído | fail closed; sin fila |
| E2E-13 | Doble radicación con el mismo `fileId` | una sola solicitud con soporte |
| E2E-14 | Fallo SQL en W1 | compensación o huérfano reconciliable |
| E2E-15 | Reclamo sin soporte | 202; docente lo ve sin soporte |
