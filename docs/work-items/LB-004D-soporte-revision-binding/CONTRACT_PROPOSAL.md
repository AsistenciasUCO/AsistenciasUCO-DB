---
status: proposed
type: work-item
scope: database
owner: database-team
system: gestionasistenciadb
last-reviewed: 2026-10-19
---

# LB-004D — Propuesta contractual: soporte ↔ solicitud de revisión

```text
CLASE_DE_CAMBIO: CONTRACT_EXTENSION (aditivo, Expand & Contract)
ESTADO: PROPOSED — NOT_READY hasta aprobación del owner DB
DECISIÓN: ADR-LB004D-001 (alternativa A)
OBJETOS EXISTENTES MODIFICADOS: ninguno (excepto grants y seeds de catálogo, aditivos)
GOLDEN_PATH_MANIFEST: sin cambios
MANIFEST NUEVO: docs/contracts/DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256 (D1)
```

Los nombres, tipos y códigos son **propuesta** para que el owner los apruebe o ajuste. Ninguna
línea de este documento está implementada.

## 1. Cadena de autorización

```text
ArchivoSoporte.id (= fileId)
  └─ ArchivoSoporte.solicitudRevisionAsistencia ─► SolicitudRevisionAsistencia.id
        └─ .asistencia ─► Asistencia.id
              ├─ .estudianteGrupo ─► EstudianteGrupo.estudiante ─► Estudiante.usuario  (propietario académico)
              └─ .sesion ─► Sesion.grupo ─► Grupo.docente ─► Docente.usuario          (docente titular)
ArchivoSoporte.usuarioPropietario ─► Usuario.id                                        (propietario técnico = ejecutor del JWT)
```

Invariante de coherencia al adjuntar: `ArchivoSoporte.usuarioPropietario` = `Estudiante.usuario` del
`EstudianteGrupo` de la asistencia de la solicitud. Un archivo nunca queda vinculado a la solicitud
de otro estudiante.

## 2. Tablas nuevas

### 2.1 `dbo.ArchivoSoporte`

| Columna | Tipo | Null | Regla |
|---|---|---|---|
| `id` | `UNIQUEIDENTIFIER` | NO | PK. Es el `fileId` generado por backend; la DB nunca lo genera. |
| `usuarioPropietario` | `UNIQUEIDENTIFIER` | NO | FK `Usuario(id)`. Siempre `@idUsuarioEjecutor`; no existe parámetro de propietario. |
| `solicitudRevisionAsistencia` | `UNIQUEIDENTIFIER` | SÍ | FK `SolicitudRevisionAsistencia(id)`. `NULL` mientras `DRAFT`/`ORPHAN`. |
| `estado` | `VARCHAR(10)` | NO | `CK_ArchivoSoporte_Estado`: `DRAFT`, `ATTACHED`, `ORPHAN`, `REPLACED` (ver Q2). |
| `nombreOriginal` | `NVARCHAR(250)` | NO | Nombre sanitizado por backend. Misma longitud que `@soporteNombre` v1. Solo presentación. |
| `tipoContenido` | `VARCHAR(50)` | NO | `CK`: `application/pdf`, `image/png`, `image/jpeg` (verificado por magic bytes en backend). |
| `tamanioOriginalBytes` | `BIGINT` | NO | `> 0`; `<=` parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES` validado en el SP. |
| `tamanioAlmacenadoBytes` | `BIGINT` | NO | `> 0` y `<= tamanioOriginalBytes`. |
| `comprimido` | `BIT` | NO | |
| `algoritmoCompresion` | `VARCHAR(20)` | SÍ | `CK`: `(comprimido = 0 AND algoritmo IS NULL) OR (comprimido = 1 AND algoritmo = 'DEFLATE')`; si `comprimido = 0`, `tamanioAlmacenado = tamanioOriginal`. |
| `checksumSha256` | `CHAR(64)` | NO | SHA-256 de los bytes **originales**, hex minúscula (`CK` de patrón binario). Autoritativo para la descarga. |
| `fechaRegistroUtc` | `DATETIME2(3)` | NO | `SYSUTCDATETIME()` al registrar el `DRAFT`. |
| `fechaAdjuncionUtc` | `DATETIME2(3)` | SÍ | `SYSUTCDATETIME()` al pasar a `ATTACHED`. |
| `fechaCambioEstadoUtc` | `DATETIME2(3)` | NO | Última transición. Base de la reconciliación. |
| `idCorrelacionRegistro` | `UNIQUEIDENTIFIER` | NO | Correlación del registro; clave de idempotencia de W1. |
| `idCorrelacionAdjuncion` | `UNIQUEIDENTIFIER` | SÍ | Correlación de la radicación v2; clave de idempotencia de W2. |

Restricciones:

- `CK_ArchivoSoporte_EstadoVinculo`:
  `DRAFT|ORPHAN ⇒ solicitud IS NULL AND fechaAdjuncion IS NULL`;
  `ATTACHED ⇒ solicitud IS NOT NULL AND fechaAdjuncion IS NOT NULL AND idCorrelacionAdjuncion IS NOT NULL`.
  `REPLACED` reservado (ver §4).
- `UX_ArchivoSoporte_Solicitud_Attached`: índice único filtrado sobre
  `solicitudRevisionAsistencia WHERE estado = 'ATTACHED'` → como máximo un soporte activo por
  solicitud (Q4). Que un `fileId` se asocie a una sola solicitud lo garantiza la PK (columna única).
- `IX_ArchivoSoporte_Estado_FechaCambio (estado, fechaCambioEstadoUtc)` para reconciliación.
- `IX_ArchivoSoporte_UsuarioPropietario (usuarioPropietario)`.
- FKs en `schema/tables/zz_foreign_keys.sql`, sin `ON DELETE CASCADE`.

No se persisten bucket, `objectKey`, URL ni bytes.

### 2.2 `dbo.ArchivoSoporteTransicion` (append-only)

| Columna | Tipo | Null | Regla |
|---|---|---|---|
| `id` | `UNIQUEIDENTIFIER` | NO | PK, `NEWID()`. |
| `archivoSoporte` | `UNIQUEIDENTIFIER` | NO | FK `ArchivoSoporte(id)`. |
| `estadoAnterior` | `VARCHAR(10)` | SÍ | `NULL` solo en el registro inicial. |
| `estadoNuevo` | `VARCHAR(10)` | NO | Mismo `CK` de estados. |
| `solicitudRevisionAsistencia` | `UNIQUEIDENTIFIER` | SÍ | Solicitud afectada (en `ATTACHED`). |
| `motivo` | `VARCHAR(30)` | NO | `CK`: `REGISTRO`, `ADJUNCION`, `VENTANA_SUPERADA`, `SIN_BYTES`, `REEMPLAZO`. |
| `idUsuarioEjecutor` | `UNIQUEIDENTIFIER` | NO | Ejecutor (estudiante o identidad técnica del reconciliador, Q6). |
| `idCorrelacion` | `UNIQUEIDENTIFIER` | NO | |
| `fechaUtc` | `DATETIME2(3)` | NO | `SYSUTCDATETIME()`. |

Se descarta `AuditoriaEvento` porque su forma es de evento HTTP (`httpMethod`, `path`,
`httpStatus` obligatorios) y pertenece a la auditoría del backend.

## 3. Procedimientos públicos nuevos

Todos: `SET NOCOUNT ON; SET XACT_ABORT ON;`, validación de correlación y de
`@idUsuarioEjecutor` obligatorio, mensajes por catálogo (`usp_obtener_mensaje_catalogo`).

### W1 — `dbo.usp_registrar_archivo_soporte_borrador` (comando)

```text
@idArchivoSoporte        UNIQUEIDENTIFIER
@nombreOriginal          NVARCHAR(250)
@tipoContenido           VARCHAR(50)
@tamanioOriginalBytes    BIGINT
@tamanioAlmacenadoBytes  BIGINT
@comprimido              BIT
@algoritmoCompresion     VARCHAR(20) = NULL
@checksumSha256          CHAR(64)
@idCorrelacion           UNIQUEIDENTIFIER
@idUsuarioEjecutor       UNIQUEIDENTIFIER
RESULTSET: idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado
```

Reglas, en orden:

1. Correlación presente; ejecutor presente; perfil RBAC `ESTUDIANTE`; el ejecutor corresponde a
   una fila de `Estudiante.usuario`.
2. Metadata válida (tipo permitido, tamaños y coherencia de compresión, checksum de 64 hex,
   nombre no vacío). Inválida → `estadoResultado = 0`, sin escritura.
3. Idempotencia por `@idArchivoSoporte`:
   - no existe → `INSERT` `DRAFT` + transición `REGISTRO`;
   - existe con el mismo propietario y la misma metadata (checksum, tamaños, tipo) → éxito sin
     escritura (reintento);
   - existe con otro propietario o metadata distinta → `estadoResultado = 0` con mensaje genérico
     `ARC_002`, sin revelar a quién pertenece.
4. Concurrencia: lectura con `UPDLOCK, HOLDLOCK`; si un `INSERT` concurrente provoca error 2627
   (PK), el `CATCH` reevalúa el paso 3 y devuelve el resultado idempotente, no `SYS_001`.

### W2 — `dbo.usp_radicar_solicitud_revision_asistencia_v2` (comando)

```text
@idEstudiante        UNIQUEIDENTIFIER
@idSesion            UNIQUEIDENTIFIER
@categoria           NVARCHAR(50)
@justificacion       NVARCHAR(MAX)
@idArchivoSoporte    UNIQUEIDENTIFIER = NULL   -- opcional: SUPPORT_OPTIONAL = YES
@idCorrelacion       UNIQUEIDENTIFIER
@idUsuarioEjecutor   UNIQUEIDENTIFIER
RESULTSET: idCorrelacion, mensajeUsuarioResultado, mensajeTecnicoResultado, estadoResultado  (idéntico a v1)
```

- Sin `@soporteNombre`/`@soporteUrl`: la v2 no confía en datos de soporte del cliente.
- Validaciones de la v1 (perfil `ESTUDIANTE`, estudiante, sesión, pertenencia al grupo de la
  sesión) **más** `Estudiante(@idEstudiante).usuario = @idUsuarioEjecutor` (H-01).
- Con `@idArchivoSoporte`:
  - reintento idempotente: el archivo ya está `ATTACHED`, es del ejecutor y
    `idCorrelacionAdjuncion = @idCorrelacion` → éxito sin crear otra solicitud;
  - en otro caso debe existir, ser del ejecutor y estar en `DRAFT`; si no (inexistente, ajeno,
    `ATTACHED`, `ORPHAN`, `REPLACED`) → `estadoResultado = 0` con el **mismo** mensaje `ARC_001`
    para todos los casos y sin crear la solicitud.
- Transacción única: crear `Asistencia` de respaldo si falta (igual que v1) → `INSERT`
  solicitud `P` → `UPDATE ArchivoSoporte SET estado='ATTACHED', … WHERE id=@x AND estado='DRAFT'
  AND usuarioPropietario=@idUsuarioEjecutor` → si `@@ROWCOUNT <> 1` (carrera perdida) `ROLLBACK`
  y `ARC_001` → `INSERT` transición `ADJUNCION` → `COMMIT`.
- Cualquier error → `ROLLBACK` completo: ni solicitud ni cambio de estado; el archivo queda `DRAFT`.
- Sin `@idArchivoSoporte`: igual a v1 (reclamo sin soporte).
- `fecha` de la solicitud: misma semántica que v1 (ver Q10).

La v1 queda intacta. El backend migra a v2; el retiro de la v1 es una decisión posterior.

### R1 — `dbo.usp_consultar_archivo_soporte_autorizado` (consulta, `READ_QUERY_RESULTSET`)

```text
@idArchivoSoporte   UNIQUEIDENTIFIER
@idCorrelacion      UNIQUEIDENTIFIER
@idUsuarioEjecutor  UNIQUEIDENTIFIER
RESULTSET (0..1 fila): idArchivoSoporte, estado, nombreOriginal, tipoContenido,
  tamanioOriginalBytes, tamanioAlmacenadoBytes, comprimido, algoritmoCompresion, checksumSha256,
  fechaRegistroUtc, fechaAdjuncionUtc, idSolicitudRevisionAsistencia, relacionAcceso
```

- `relacionAcceso = 'PROPIETARIO'` si `usuarioPropietario = @idUsuarioEjecutor` y `estado IN
  ('DRAFT','ATTACHED')`.
- `relacionAcceso = 'DOCENTE_TITULAR'` si `estado = 'ATTACHED'` y existe `Docente d` con
  `d.usuario = @idUsuarioEjecutor` y `d.id = Grupo.docente` en la cadena §1.
- En cualquier otro caso, 0 filas: archivo inexistente, otro estudiante, docente no titular,
  administrador, decano, coordinador, `ORPHAN`, `REPLACED`. No hay mensaje que distinga los casos.
- Une tablas base dentro del SP. **No** usa `SESSION_CONTEXT` ni `uv_auth_*` (H-03).
- Parámetros nulos → `THROW` con código de catálogo (como `usp_consultar_grupos_paginado`).

### R2 — `dbo.usp_consultar_solicitudes_revision_docente` (consulta paginada)

```text
@idUsuarioEjecutor  UNIQUEIDENTIFIER
@idCorrelacion      UNIQUEIDENTIFIER
@codigoEstado       NVARCHAR(5) = NULL      -- P, A, R
@numeroPagina       INT = 1
@tamanoPagina       INT = 10
RESULTSET: idSolicitudRevisionAsistencia, nombreSolicitud, fechaSolicitud, codigoEstado,
  nombreEstado, justificacionSolicitud, justificacionRespuesta, idEstudiante, nombreEstudiante,
  idSesion, numeroSesion, fechaHoraInicioSesion (semántica temporal de UTC-D06), idGrupo, codigoGrupo, idAsignatura,
  nombreAsignatura, idArchivoSoporte, nombreSoporte, tipoContenidoSoporte, tamanioSoporteBytes,
  totalRegistros
```

- Solo solicitudes cuyo `Grupo.docente` corresponde a `Docente.usuario = @idUsuarioEjecutor`.
- Columnas de soporte por `LEFT JOIN ArchivoSoporte … estado = 'ATTACHED'`: `NULL` si el reclamo
  no tiene soporte.
- Respalda `GET /docente/reclamos` (hoy `FeatureUnavailable`). Las columnas exactas se alinean con
  el contrato HTTP de B1 y con `SolicitudRevisionItem` del frontend. Datos personales mínimos:
  nombre, sin correo (Q9).
- La variante para el estudiante (`GET /estudiante/reclamos`) queda en Q9.

### W3/R3 — Reconciliación (contrato definido; implementación sujeta a Q6)

`dbo.usp_consultar_archivos_soporte_reconciliacion` (consulta):

```text
@estado              VARCHAR(10)        -- DRAFT | ORPHAN
@fechaCorteUtc       DATETIME2(3)       -- la calcula el llamador con la ventana aprobada
@maximoRegistros     INT
@idsArchivoSoporte   NVARCHAR(MAX) = NULL  -- JSON array opcional: modo "¿están registrados?"
@idCorrelacion, @idUsuarioEjecutor
RESULTSET: idArchivoSoporte, estado, fechaRegistroUtc, fechaCambioEstadoUtc, registrado (BIT)
```

`dbo.usp_marcar_archivo_soporte_huerfano` (comando, 4 campos canónicos):

```text
@idArchivoSoporte, @motivo ('VENTANA_SUPERADA' | 'SIN_BYTES'), @fechaCorteUtc,
@idCorrelacion, @idUsuarioEjecutor
```

- Solo `DRAFT` con `fechaCambioEstadoUtc < @fechaCorteUtc` (o `SIN_BYTES`) → `ORPHAN` +
  transición. Idempotente: ya `ORPHAN` → éxito sin escritura. `ATTACHED` → rechazo, sin cambio.
- `UPDATE … WHERE estado = 'DRAFT'` evita la carrera con una radicación concurrente: si la v2
  adjuntó primero, `@@ROWCOUNT = 0` y el archivo se conserva.
- La DB no fija la ventana: si el llamador no envía `@fechaCorteUtc`, el SP rechaza.

## 4. Estados y transiciones

| Desde → Hacia | Operación | Condición |
|---|---|---|
| ∅ → `DRAFT` | W1 | `fileId` nuevo; propietario = ejecutor estudiante |
| `DRAFT` → `ATTACHED` | W2 (v2) | mismo propietario; solicitud creada en la misma transacción; una sola vez |
| `DRAFT` → `ORPHAN` | W3 | ventana superada o bytes inexistentes; nunca por edad del objeto MinIO |
| `ATTACHED` → `REPLACED` | — | `POST_ATTACH_REPLACEMENT: OUT_OF_SCOPE`. El estado existe en el `CK`, pero **ningún SP de D1** hace esta transición. |
| `ATTACHED` → cualquier otro | — | Prohibido en D1 |
| `ORPHAN`/`REPLACED` → otro | — | Terminal en D1 |

Reemplazo antes de radicar: el estudiante sube un archivo nuevo (otro `fileId`); el `DRAFT`
anterior no se adjunta y termina `ORPHAN` por reconciliación.

## 5. Retención

- `ATTACHED`: se conserva indefinidamente hasta que exista una política aprobada.
- `ORPHAN`: candidato a purga de bytes por el backend (`FileStoragePort.delete`); la fila SQL se
  conserva como evidencia. El momento de la purga es `NUMERIC_RETENTION: DECISION_REQUIRED`.
- No se fija ningún plazo en este contrato. La ventana `DRAFT → ORPHAN` es
  `PRODUCT_DECISION_REQUIRED` y llega como `@fechaCorteUtc`.

## 6. Catálogos y permisos (aditivos)

- Parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES = 5242880` (5 MiB, decisión congelada
  `D-LB004B1-003` del backend; no es un valor nuevo).
- Mensajes nuevos (texto a redactar por el owner):
  `ARC_001` soporte no disponible para radicar (inexistente, ajeno o ya usado; mismo texto para
  todos), `ARC_002` registro de soporte rechazado, `ARC_003` metadata de soporte inválida,
  `ARC_004` transición de estado no permitida, `ARC_005` estudiante no corresponde al ejecutor.
- `rol_asistencias_runtime`: `EXECUTE` solo en W1, W2 (v2), R1, R2. Sin acceso a tablas.
- W3/R3: identidad técnica separada (Q6); `rol_asistencias_runtime` no los ejecuta salvo decisión.

## 7. Compatibilidad

| Consumidor | Impacto |
|---|---|
| Backend actual (v1) | Ninguno: v1, vistas y resultsets intactos. |
| Backend B1 | Migra la radicación a v2 y añade adapters JPA para W1, R1, R2 (y W3/R3 si Q6). |
| Frontend actual | Ninguno hasta F1; sigue enviando `soporteNombre/soporteUrl`, que el backend ya no transmite a v2. |
| Golden Path / manifest | Sin cambios. Manifest nuevo `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`. |
| `test_contract_closure.sql` | W1/W2/W3 entran en la regla de 4 campos; R1/R2/R3 como `READ_QUERY_RESULTSET`. |

## 8. Decisiones que debe tomar el owner DB

| ID | Pregunta | Recomendación |
|---|---|---|
| Q1 | ¿Se aprueba la alternativa A (2 tablas nuevas)? | Sí |
| Q2 | ¿Estado como `VARCHAR + CHECK` o catálogo propio (`EstadoArchivoSoporte`)? | `CHECK`: son estados técnicos de ciclo de vida, no catálogo de negocio |
| Q3 | ¿Adjuntar dentro de `usp_radicar_…_v2` (atómico) o con un SP separado posterior? | v2: la v1 no devuelve el id de la solicitud y dos transacciones permitirían un reclamo sin su soporte |
| Q4 | ¿Cardinalidad 0..1 soporte activo por solicitud? | Sí (el contrato HTTP tiene un solo `soporteArchivoId`) |
| Q5 | ¿Se impide una segunda solicitud pendiente para la misma asistencia? ¿Se aplica el plazo de 5 días hábiles? | Decisión de negocio; sin respuesta, D1 no lo implementa |
| Q6 | ¿Qué identidad ejecuta la reconciliación (perfil técnico, rol SQL separado)? | Rol SQL separado con `EXECUTE` solo sobre W3/R3; sin respuesta, W3/R3 se difieren |
| Q7 | ¿Se acepta el parámetro `ARCHIVO.TAMANIO_MAXIMO_BYTES`? | Sí |
| Q8 | ¿Se aprueban los grants del §6? | Sí |
| Q9 | ¿Entra en D1 la consulta de reclamos del estudiante? ¿Qué datos del estudiante ve el docente? | Diferir la del estudiante; docente: nombre, sin correo |
| Q10 | ¿La v2 mantiene la `fecha` local de la v1 o pasa a UTC? | Mantener la semántica de la v1; migración UTC en un work item de MAINT-003 |
