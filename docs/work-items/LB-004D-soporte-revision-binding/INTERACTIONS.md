---
status: proposed
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# LB-004D — Esquema de interacciones

MinIO **no** participa en ninguna transacción SQL. Cada flujo indica qué queda si falla en cada
punto y quién lo compensa. Objetos SQL según [CONTRACT_PROPOSAL](CONTRACT_PROPOSAL.md).

## 1. Subida del soporte (estudiante)

```mermaid
sequenceDiagram
    autonumber
    actor E as Estudiante (Angular)
    participant B as Backend
    participant C as ClamAV
    participant M as MinIO (privado)
    participant S as SQL Server
    E->>B: POST /api/v1/archivos/subir (Bearer, multipart)
    B->>B: JWT → idUsuario; extensión + MIME + magic; ≤ 5 MiB; nombre ≤ 250
    B->>C: INSTREAM
    C-->>B: CLEAN (INFECTED → 400; error/timeout → 500, fail closed)
    B->>B: compresión (si ahorra ≥ 10 %), SHA-256 de los bytes originales, fileId = UUID v4
    B->>M: put soportes/<fileId> + metadata técnica
    B->>S: W1 usp_registrar_archivo_soporte(fileId, nombre, tipo, tamanio, sha256, idCorrelacion, idUsuarioEjecutor)
    S-->>B: 4 campos canónicos (DRAFT)
    B-->>E: 201 { fileId, nombre, url relativa, tamanio }
```

| Falla | Estado resultante | Compensación |
|---|---|---|
| Validación o ClamAV | Nada escrito | — |
| `put` MinIO | Nada escrito | — |
| W1 responde `estadoResultado = 0` (rechazo definitivo) | Objeto sin fila | Backend `FileStoragePort.delete` best-effort; si falla, huérfano técnico → reconciliación (§4) |
| W1 con error de transporte o timeout (resultado desconocido) | Objeto con o sin fila | Backend reintenta W1 una vez con la **misma** correlación y metadata (idempotente). **No** borra los bytes sin conocer el resultado. Si sigue desconocido → 5xx y reconciliación |
| Respuesta HTTP perdida | `DRAFT` válido | El cliente reintenta la subida → nuevo `fileId`; el anterior acabará `ORPHAN` |

## 2. Radicación con soporte opcional (estudiante)

```mermaid
sequenceDiagram
    autonumber
    actor E as Estudiante
    participant B as Backend
    participant S as SQL Server
    E->>B: POST /api/v1/asistencias/revisiones { sesionId, categoria, justificacion, soporteArchivoId? }
    B->>B: JWT → idUsuario → idEstudiante (InstitutionalScopePort)
    B->>S: W2 usp_radicar_solicitud_revision_asistencia_v2(..., @idArchivoSoporte, idCorrelacion, idUsuarioEjecutor)
    Note over S: BEGIN TRAN · INSERT Solicitud (P) · UPDATE ArchivoSoporte DRAFT→ATTACHED (WHERE estado='DRAFT' AND propietario=ejecutor) · COMMIT
    S-->>B: 4 campos canónicos
    B-->>E: 202 (éxito) · 404 (soporte no disponible) · 400 (validación)
```

- MinIO no se toca: los bytes ya existen.
- Cualquier error → `ROLLBACK` completo; el archivo sigue `DRAFT` y puede reintentarse.
- Dos radicaciones simultáneas con el mismo `fileId`: solo una obtiene `@@ROWCOUNT = 1`; la otra
  hace `ROLLBACK` y recibe `ARC_001`.
- Reintento con la misma correlación tras un éxito: idempotente, sin segunda solicitud.

## 3. Consulta y descarga (docente titular o propietario)

```mermaid
sequenceDiagram
    autonumber
    actor D as Docente titular
    participant B as Backend
    participant S as SQL Server
    participant M as MinIO
    D->>B: GET /api/v1/docente/reclamos (Bearer)
    B->>S: R2 usp_consultar_solicitudes_revision_docente(idUsuarioEjecutor, …)
    S-->>B: reclamos del docente + idArchivoSoporte / nombre / tipo / tamaño
    D->>B: GET /api/v1/archivos/{fileId} (Bearer)
    B->>S: R1 usp_consultar_archivo_soporte_autorizado(fileId, idUsuarioEjecutor)
    alt 0 filas
        B-->>D: 404 (sin consultar MinIO)
    else PROPIETARIO o DOCENTE_TITULAR
        B->>M: get soportes/<fileId> (lectura acotada)
        B->>B: inflate acotado si comprimido · SHA-256 == checksum SQL
        B-->>D: 200 bytes originales · Content-Type de SQL
    end
```

- La autorización se resuelve en SQL **antes** de pedir bytes a MinIO.
- Checksum distinto o tamaño distinto → no se sirven bytes (5xx genérico, incidente de
  integridad registrado con correlación). El código HTTP exacto se fija en B1.
- Fila sin objeto en MinIO → igual tratamiento de integridad; el reconciliador puede marcarlo
  `SIN_BYTES` solo si estaba `DRAFT`. Un `ATTACHED` sin bytes es un incidente, nunca se oculta
  cambiando su estado.
- `owner-subject` de MinIO queda como control técnico adicional, no como autoridad.

## 4. Reconciliación (DIFERIDA — Q6; no implementada en D1)

```mermaid
sequenceDiagram
    autonumber
    participant R as Reconciliador (identidad técnica, Q6)
    participant S as SQL Server
    participant M as MinIO
    R->>S: R3 DRAFT con fechaCambioEstado < fechaCorteUtc (ventana aprobada)
    S-->>R: lista de fileId
    R->>S: W3 marcar ORPHAN (WHERE estado='DRAFT')
    Note over R,S: si la v2 adjuntó antes, @@ROWCOUNT = 0 y el archivo se conserva
    R->>M: listar soportes/ (objetos sin fila: huérfanos técnicos)
    R->>S: R3 modo @idsArchivoSoporte → registrado = 0
    R->>M: delete solo de ORPHAN o no registrados, cuando la política de purga lo autorice
```

- La edad del objeto MinIO nunca es la única autoridad.
- Sin ventana aprobada no hay `@fechaCorteUtc` y nada se marca.
- El diseño del worker (claim/lease, reintentos) es una microfase posterior (`STORAGE_LIFECYCLE`).
