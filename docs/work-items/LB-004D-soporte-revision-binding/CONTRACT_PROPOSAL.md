---
status: proposed
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# LB-004D — Contrato: soporte ↔ solicitud de revisión (arquitectura de UNA tabla)

```text
CLASE_DE_CAMBIO: CONTRACT_EXTENSION (aditivo, Expand & Contract)
ESTADO: IMPLEMENTADO EN RAMA (D1) — APROBACIÓN DEL OWNER DB (John) PENDIENTE
DECISIÓN: ADR-LB004D-001 (decisión del solicitante: LB004D_ARCHITECTURE = ONE_TABLE)
OBJETOS EXISTENTES MODIFICADOS: ninguno (ni tablas, ni SP, ni vistas, ni seeds del manifest)
GOLDEN_PATH_MANIFEST: sin cambios
MANIFEST NUEVO: docs/contracts/DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256
```

Esta versión sustituye a la propuesta de dos tablas: se elimina `ArchivoSoporteTransicion`. La
trazabilidad se conserva con las tres fechas UTC y las dos correlaciones de la propia fila. Los
nombres, tipos y códigos siguen siendo **propuesta** hasta que el owner DB los apruebe.

## 1. Cadena de autorización

```text
ArchivoSoporte.id (= fileId)
  └─ ArchivoSoporte.solicitudRevisionAsistencia ─► SolicitudRevisionAsistencia.id
        └─ .asistencia ─► Asistencia.id
              ├─ .estudianteGrupo ─► EstudianteGrupo.estudiante ─► Estudiante.usuario  (propietario académico)
              └─ .sesion ─► Sesion.grupo ─► Grupo.docente ─► Docente.usuario          (docente titular)
ArchivoSoporte.usuarioPropietario ─► Usuario.id                                        (propietario técnico = ejecutor del JWT)
```

Invariante al adjuntar: `ArchivoSoporte.usuarioPropietario` = `Estudiante.usuario` del
`EstudianteGrupo` de la asistencia de la solicitud. Un archivo nunca queda vinculado a la
solicitud de otro estudiante.

## 2. Tabla única `dbo.ArchivoSoporte`

| Columna | Tipo | Null | Regla |
|---|---|---|---|
| `id` | `UNIQUEIDENTIFIER` | NO | PK. Es el `fileId` opaco generado por backend; la DB nunca lo genera. |
| `usuarioPropietario` | `UNIQUEIDENTIFIER` | NO | FK `Usuario(id)`. Siempre `@idUsuarioEjecutor`; no existe parámetro de propietario. |
| `solicitudRevisionAsistencia` | `UNIQUEIDENTIFIER` | SÍ | FK `SolicitudRevisionAsistencia(id)`. `NULL` mientras `DRAFT`/`ORPHAN`. |
| `nombreOriginal` | `NVARCHAR(250)` | NO | Sanitizado por backend; solo presentación. Misma longitud que `@soporteNombre` v1. |
| `tipoContenido` | `VARCHAR(50)` | NO | `CK`: `application/pdf`, `image/png`, `image/jpeg`. |
| `tamanioBytes` | `BIGINT` | NO | Tamaño de los bytes **originales**; `> 0`; `<=` parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES` (validado en el SP). |
| `checksumSha256` | `CHAR(64)` | NO | SHA-256 hex minúscula de los bytes originales. Autoridad para la descarga. |
| `estado` | `VARCHAR(10)` | NO | `CK`: `DRAFT`, `ATTACHED`, `ORPHAN`. `REPLACED` queda reservado (evolución posterior; ampliar el `CK`). |
| `fechaRegistroUtc` | `DATETIME2(7)` | NO | `SYSUTCDATETIME()` al registrar. |
| `fechaAdjuncionUtc` | `DATETIME2(7)` | SÍ | `SYSUTCDATETIME()` al pasar a `ATTACHED`. |
| `fechaCambioEstadoUtc` | `DATETIME2(7)` | NO | Última transición (base de futura reconciliación). |
| `idCorrelacionRegistro` | `UNIQUEIDENTIFIER` | NO | Correlación de W1; clave de idempotencia del registro. |
| `idCorrelacionAdjuncion` | `UNIQUEIDENTIFIER` | SÍ | Correlación de W2; clave de idempotencia de la radicación. |

Convención temporal: todo `*Utc` es un instante UTC en `DATETIME2(7)` (7 decimales, igual que el
contrato UTC v2 de `Sesion`). `DATETIME2` no almacena zona: el contrato es UTC por columna y por
nombre. Se genera con `SYSUTCDATETIME()`, nunca con `GETDATE()`/`CURRENT_TIMESTAMP`.

Restricciones e índices:

- `PK_ArchivoSoporte (id)`.
- `FK_ArchivoSoporte_Usuario`, `FK_ArchivoSoporte_SolicitudRevisionAsistencia` (sin `ON DELETE CASCADE`).
- `CK_ArchivoSoporte_Estado`, `CK_ArchivoSoporte_TipoContenido`, `CK_ArchivoSoporte_Tamanio`
  (`> 0`), `CK_ArchivoSoporte_Checksum` (64 hex minúscula).
- `CK_ArchivoSoporte_EstadoVinculo`:
  `DRAFT|ORPHAN ⇒ solicitud IS NULL AND fechaAdjuncion IS NULL AND idCorrelacionAdjuncion IS NULL`;
  `ATTACHED ⇒ solicitud IS NOT NULL AND fechaAdjuncion IS NOT NULL AND idCorrelacionAdjuncion IS NOT NULL`.
- `UX_ArchivoSoporte_Solicitud`: índice único filtrado (`WHERE solicitud IS NOT NULL`) → como
  máximo un soporte activo por solicitud.
- `IX_ArchivoSoporte_UsuarioPropietario (usuarioPropietario)`.

No se persisten bucket, `objectKey`, URL, bytes ni metadata de compresión: viven en Infrastructure
(MinIO). La migración a otro proveedor no cambia `fileId` ni las relaciones académicas.

## 3. Procedimientos públicos

Todos: `SET NOCOUNT ON; SET XACT_ABORT ON;`, validación de correlación y de
`@idUsuarioEjecutor`, mensajes por catálogo (`usp_obtener_mensaje_catalogo`), sin
`SESSION_CONTEXT` ni `uv_auth_*` en las lecturas de soporte.

### W1 — `dbo.usp_registrar_archivo_soporte` (comando, 4 campos canónicos)

```text
@idArchivoSoporte UNIQUEIDENTIFIER, @nombreOriginal NVARCHAR(250), @tipoContenido VARCHAR(50),
@tamanioBytes BIGINT, @checksumSha256 CHAR(64), @idCorrelacion UNIQUEIDENTIFIER,
@idUsuarioEjecutor UNIQUEIDENTIFIER
RESULTSET: idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado
```

1. Correlación y ejecutor presentes; perfil RBAC `ESTUDIANTE`; el ejecutor es `Estudiante.usuario`.
2. Metadata válida (id, nombre, tipo permitido, `0 < tamaño <= máximo`, checksum 64 hex). Inválida →
   `estadoResultado = 0`, `ARC_003`, sin escritura.
3. Idempotencia por `@idArchivoSoporte`: no existe → `INSERT` `DRAFT`; existe con mismo
   propietario y misma metadata (tipo, tamaño, checksum, nombre) → éxito sin escritura; otro
   propietario o metadata distinta → `ARC_002` genérico (no revela a quién pertenece).
4. Concurrencia: lectura con `UPDLOCK, HOLDLOCK`; un `INSERT` concurrente que viole la PK (2627)
   reevalúa el paso 3 y devuelve el resultado idempotente, no `SYS_001`.

### W2 — `dbo.usp_radicar_solicitud_revision_asistencia_v2` (comando)

```text
@idEstudiante, @idSesion, @categoria NVARCHAR(50), @justificacion NVARCHAR(MAX),
@idArchivoSoporte UNIQUEIDENTIFIER = NULL, @idCorrelacion, @idUsuarioEjecutor
RESULTSET: idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado
```

- Sin `@soporteNombre`/`@soporteUrl`: la v2 no confía en datos de soporte del cliente.
- Validaciones de la v1 (perfil, estudiante, sesión, pertenencia al grupo de la sesión) **más**
  `Estudiante(@idEstudiante).usuario = @idUsuarioEjecutor` (`ARC_005`, hallazgo H-01).
- Con `@idArchivoSoporte`: reintento idempotente si ya está `ATTACHED`, es del ejecutor y
  `idCorrelacionAdjuncion = @idCorrelacion`; en otro caso debe existir, ser del ejecutor y estar
  `DRAFT`; si no (inexistente, ajeno, `ATTACHED`, `ORPHAN`) → `ARC_001` idéntico en todos los casos
  y sin crear la solicitud.
- Una sola transacción: `Asistencia` de respaldo (si falta) → `INSERT` solicitud `P` →
  `UPDATE ArchivoSoporte … WHERE id=@x AND estado='DRAFT' AND usuarioPropietario=@ejecutor` →
  `@@ROWCOUNT <> 1` ⇒ `ROLLBACK` + `ARC_001` → `COMMIT`. Cualquier error ⇒ rollback completo.
- Sin `@idArchivoSoporte`: igual que la v1 (soporte opcional).
- `fecha` de la solicitud conserva la semántica de la v1 (`DATE` de calendario local;
  `CAST(CURRENT_TIMESTAMP AS DATE)`). No es un instante técnico y no se migra aquí (Q10 resuelta
  por instrucción del solicitante).
- La v1 queda intacta.

### R1 — `dbo.usp_consultar_archivo_soporte_autorizado` (`READ_QUERY_RESULTSET`)

```text
@idArchivoSoporte, @idCorrelacion, @idUsuarioEjecutor
RESULTSET (0..1 fila): idArchivoSoporte, estado, nombreOriginal, tipoContenido, tamanioBytes,
  checksumSha256, fechaRegistroUtc, fechaAdjuncionUtc, idSolicitudRevisionAsistencia, relacionAcceso
```

- `PROPIETARIO` si `usuarioPropietario = @idUsuarioEjecutor` y `estado IN ('DRAFT','ATTACHED')`.
- `DOCENTE_TITULAR` si `estado = 'ATTACHED'` y `Docente.usuario = @idUsuarioEjecutor` es el
  `Grupo.docente` de la cadena §1.
- Cualquier otro caso (inexistente, otro estudiante —incluso del mismo grupo—, docente no titular,
  administrador, decano, coordinador, `ORPHAN`): **0 filas**, sin mensaje que distinga los casos.
- Parámetros nulos → `THROW` con código de catálogo (como `usp_consultar_grupos_paginado`).

### R2 — `dbo.usp_consultar_solicitudes_revision_docente` (consulta paginada)

```text
@idUsuarioEjecutor, @idCorrelacion, @codigoEstado NVARCHAR(5) = NULL (P/A/R), @numeroPagina INT = 1,
@tamanoPagina INT = 10 (1..100)
RESULTSET: idSolicitudRevisionAsistencia, nombreSolicitud, fechaSolicitud, codigoEstado, nombreEstado,
  justificacionSolicitud, justificacionRespuesta, idEstudiante, nombreEstudiante, idSesion,
  numeroSesion, fechaHoraInicioSesion, procedenciaTemporalSesion, idGrupo, codigoGrupo, nombreGrupo,
  idAsignatura, codigoAsignatura, nombreAsignatura, idArchivoSoporte, nombreSoporte,
  tipoContenidoSoporte, tamanioSoporteBytes, fechaRegistroSoporteUtc, totalRegistros
```

- Solo solicitudes cuyo `Grupo.docente` pertenece a `Docente.usuario = @idUsuarioEjecutor`
  (titularidad institucional, no solo el rol).
- Soporte por `LEFT JOIN ArchivoSoporte` (`estado = 'ATTACHED'`); `NULL` si no hay.
- `fechaHoraInicioSesion` es el `DATETIME2(7)` de `Sesion` tal cual, con `procedenciaTemporalSesion`
  (`UTC_V2`/`UTC_GENERADOR`/`UTC_OWNER` o `NULL` = indeterminada, historica): la DB no afirma UTC
  cuando no lo sabe; el consumidor decide segun esa procedencia (contrato UTC v2). `fechaSolicitud`
  es `DATE`; `fechaRegistroSoporteUtc` es un instante UTC `DATETIME2(7)`.
- Orden determinista: `fecha DESC, nombre ASC, id ASC`. Datos personales mínimos: nombre, sin correo.

### Diferido: reconciliación (Q6)

`usp_consultar_archivos_soporte_reconciliacion` y `usp_marcar_archivo_soporte_huerfano` **no** se
implementan en D1 (no son necesarios para el flujo y dependen de la ventana de producto y de la
identidad técnica, Q6). El estado `ORPHAN` existe en el `CK` y R1 ya lo trata como no accesible;
una microfase posterior añadirá solo los SP, sin cambiar la tabla.

## 4. Estados

| Desde → Hacia | Operación | Condición |
|---|---|---|
| ∅ → `DRAFT` | W1 | `fileId` nuevo; propietario = ejecutor estudiante |
| `DRAFT` → `ATTACHED` | W2 | mismo propietario; misma transacción que crea la solicitud; una vez |
| `DRAFT` → `ORPHAN` | (diferido, Q6) | ventana de producto superada o bytes inexistentes |
| `ATTACHED` → otro | — | Prohibido en D1 |

## 5. Catálogos y permisos (aditivos)

- Parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES = 5242880` (5 MiB; decisión congelada `D-LB004B1-003`).
- Mensajes `ARC_001` (soporte no disponible para radicar), `ARC_002` (registro de soporte
  rechazado), `ARC_003` (metadata de soporte inválida), `ARC_005` (estudiante no corresponde al
  ejecutor); reutiliza `GEN_004`, `GEN_002`, `SEC_001`, `SYS_001`. Archivo nuevo
  `schema/seed/15_lb004d_archivo_soporte.sql` (no se toca `03`/`04`).
- Archivo nuevo `schema/security/rol_asistencias_runtime_lb004d.sql`: `EXECUTE` de
  `rol_asistencias_runtime` solo sobre W1, W2, R1, R2; `DENY SELECT/INSERT/UPDATE/DELETE` sobre
  `dbo.ArchivoSoporte`. No se toca `rol_asistencias_runtime.sql` (hash fijado en
  `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256`).

## 6. Compatibilidad

| Consumidor | Impacto |
|---|---|
| Backend actual (v1) | Ninguno: v1, vistas y resultsets intactos. |
| Backend B1 | Migra la radicación a v2; adapters JPA para W1, R1, R2. |
| Frontend actual | Ninguno hasta F1. |
| Golden Path | Sin cambios. Manifest nuevo `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`. |
| `test_contract_closure.sql` | W1/W2 entran en la regla de 4 campos; R1/R2 se excluyen por nombre como `READ_QUERY_RESULTSET`. |

## 7. Decisiones del owner DB

| ID | Pregunta | Estado |
|---|---|---|
| Q1 | ¿Una tabla (`ONE_TABLE`)? | **Resuelta por el solicitante**; revisión de John pendiente |
| Q2 | Estado como `VARCHAR + CHECK` | Propuesto: sí |
| Q3 | Adjuntar dentro de W2 (atómico) | Propuesto: sí |
| Q4 | Cardinalidad 0..1 soporte por solicitud | Propuesto: sí (índice único filtrado) |
| Q5 | ¿Impedir segunda solicitud para la misma asistencia / plazo de 5 días hábiles? | **Abierta**; D1 no lo implementa |
| Q6 | Identidad y ventana de reconciliación `DRAFT → ORPHAN` | **Abierta**; SP diferidos |
| Q7 | Parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES` | Propuesto: sí |
| Q8 | Grants del §5 | Propuesto: sí |
| Q9 | Reclamos del estudiante / datos del estudiante que ve el docente | Estudiante diferido; docente: nombre, sin correo |
| Q10 | `fecha` de la solicitud | Resuelta: se mantiene la semántica v1 |
