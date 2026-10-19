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

Estado: **PASS** en la base local principal (`gestionasistenciadb`, contenedor `sql_server_asistencias`)
el 2026-10-19; ver [VALIDATION](VALIDATION.md). Los casos viven en
`test/test_lb004d_support_binding.sql` (una transaccion con `ROLLBACK`, sin datos persistentes; incluido
en `test_suite.sql` y registrado como `LB004D_*` critico en `test_summary.ps1`) y
`test/test_lb004d_concurrency.ps1` (dos conexiones, fixtures con marcador unico eliminados en `finally`).

| ID | Requisito del encargo | Prueba | Estado |
|---|---|---|---|
| DB-01 | Archivo propio y valido | `W1_VALID`, `W2_ATTACH` (DRAFT -> ATTACHED, solicitud `P`, correlaciones, fechas UTC) | PASS |
| DB-02 | Archivo ajeno | `W2_FOREIGN_FILE_REJECTED` (ARC_001, sin solicitud, B sigue DRAFT) | PASS |
| DB-03 | Doble asociacion | `W2_DOUBLE_ATTACH_REJECTED` | PASS |
| DB-04 | Docente titular | `R1_TEACHER_TITULAR`, `R2_TEACHER_SCOPE_AND_SUPPORT` | PASS |
| DB-05 | Docente no titular | `R1_DENIED_TEACHER_NOT_TITULAR`, `R2_OTHER_TEACHER_ZERO_ROWS` | PASS |
| DB-06 | Otros actores | `R1_DENIED_*`: estudiante del mismo grupo, de otro grupo, administrador, coordinador, decano | PASS |
| DB-07 | Propietario | `R1_OWNER_DRAFT`, `R1_OWNER_ATTACHED`, `R1_ORPHAN_NOT_ACCESSIBLE` | PASS |
| DB-08 | Sesion inexistente | `W2_MISSING_SESSION` (archivo sigue DRAFT) | PASS |
| DB-09 | Matricula invalida | `W2_NOT_ENROLLED` | PASS |
| DB-10 | Estudiante != ejecutor | `W2_STUDENT_NOT_EXECUTOR` (ARC_005) | PASS |
| DB-11 | Concurrencia attach | `test_lb004d_concurrency.ps1`: una ganadora, otra ARC_001 | PASS |
| DB-12 | Attach vs orphan | N/A en D1: el marcado `ORPHAN` por SP esta diferido (Q6) | NOT_APPLICABLE |
| DB-13 | Rollback | `W2_ATOMIC_ROLLBACK` (la solicitud se revierte si el vinculo no queda verificado) | PASS |
| DB-14 | Idempotencia W1 | `W1_IDEMPOTENT_RETRY`, `W1_CONFLICT_*`, concurrencia W1 | PASS |
| DB-15 | Idempotencia W2 | `W2_RETRY_SAME_CORRELATION_IDEMPOTENT` | PASS |
| DB-16 | Integridad referencial | `INTEGRITY_FK_*`, `INTEGRITY_CK_*`, `INTEGRITY_ONE_SUPPORT_PER_REQUEST` | PASS |
| DB-17 | Reclamo sin soporte | `W2_NO_SUPPORT_*`, `R2_WITHOUT_SUPPORT_AND_UTC_PRECISION` | PASS |
| DB-18 | Metadata invalida | `W1_INVALID_METADATA` (tipo, 0, > 5 MiB, checksum, nombre) | PASS |
| DB-19 | Perfil RBAC | `W1_NON_STUDENT_PROFILE`, `W2_NON_STUDENT_PROFILE` | PASS |
| DB-20/21 | Reconciliacion | Diferida (Q6): sin SP W3/R3 en D1 | NOT_APPLICABLE |
| DB-22 | UTC | `UTC_V2_DATETIME2_7`: `DATETIME2(7)`, fechas dentro de `[SYSUTCDATETIME() antes, despues]`, 7 decimales de `Sesion` intactos en R2 | PASS |
| DB-23 | v1 intacta | `V1_UNCHANGED` + suite completa + manifest Golden Path | PASS |
| DB-24 | Contrato de resultset | `test_contract_closure.sql`: W1/W2 con 4 columnas canonicas; R1/R2 excluidos por nombre | PASS |
| DB-25 | Minimo privilegio | `RUNTIME_LEAST_PRIVILEGE` (usuario del rol: EXECUTE si, SELECT sobre la tabla denegado) | PASS |
| DB-26 | Manifest LB-004D | `scripts/lb004d-manifest.ps1 -Mode Verify` | PASS |

Gates D1: `test_summary.ps1` = `DB GATE PASS` (247 pruebas, 0 fallos, 1 skip permitido). SonarCloud y Trivy
del PR: ver el PR (no se declaran PASS sin evidencia remota).

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
