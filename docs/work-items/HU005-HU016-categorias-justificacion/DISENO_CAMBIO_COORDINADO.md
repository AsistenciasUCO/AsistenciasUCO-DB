---
status: proposed
type: design
scope: db
owner: db-team
last-reviewed: 2026-11-05
---

# Diseño — cambio coordinado LB-004D: categoría del reclamo (TD-060), plazo (HU026B), soporte obligatorio y HU014

Propuesta para José Alejandro, dueño de LB-004D. **No está implementada.** Este work item (HU005/HU016) solo creó el catálogo `CategoriaJustificacion` y su consulta. No tocó ningún objeto congelado.

## Estado actual

- `dbo.CategoriaJustificacion` (id, codigo, nombre, descripcion) existe, con un seed de 6 filas: MED, CAL, ACA, FMA, LAB y OTR. Se lee por `uv_categoria_justificacion` y `GET /api/v1/categorias-justificacion`.
- El formulario del estudiante lee las categorías del catálogo. Envía el **nombre** en `categoria`, igual que antes, así que el contrato de `POST /api/v1/estudiante/reclamos` no cambia.
- `usp_radicar_solicitud_revision_asistencia_v2` recibe `@categoria NVARCHAR(50)` pero no la guarda: es TD-060.
  - El SP está en `docs/contracts/DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`, que se verifica con `scripts/lb004d-manifest.ps1`.
  - No está en `DB_DEVELOP_FREEZE_MANIFEST` ni en `DB_UTC_D06_POST_FREEZE_MANIFEST`.
- El parámetro `ASISTENCIA.DIAS_LIMITE_JUSTIFICACION = 5` está en el seed `03_parametro.sql`. Ningún SP ni el backend lo usa: la radicación hoy no valida ningún plazo.

## Cambios propuestos (un solo PR de BD, con el manifiesto regenerado una sola vez)

### 1. TD-060: guardar la categoría

- `SolicitudRevisionAsistencia.categoriaJustificacion UNIQUEIDENTIFIER NULL`, con `FK_SolicitudRevisionAsistencia_CategoriaJustificacion` hacia `CategoriaJustificacion(id)`.
  - Es nullable porque las solicitudes ya radicadas no tienen categoría. No se hace backfill: el texto original no se guardó.
  - Relación: una categoría tiene muchas solicitudes; cada solicitud tiene una categoría o ninguna.
- SP v2: resuelve `@categoria` por `nombre`, o por `codigo` para aceptar los dos durante la transición.
  - Si no existe, rechaza con un mensaje nuevo del catálogo (p. ej. `REV_0xx`). Si existe, guarda el id.
  - Así la firma del SP no cambia y el backend actual sigue funcionando.
- `usp_consultar_solicitudes_revision_docente` y la vista del detalle exponen `codigoCategoria` y `nombreCategoria`.
  - El backend los muestra en el detalle del reclamo del docente (HU036), junto a la `RazonCausa`.

### 2. HU026B: plazo para radicar

- Decisión de John (2026-11-05): **días calendario**, contados desde la fecha de la sesión, por ahora.
- El SP v2 lee `ASISTENCIA.DIAS_LIMITE_JUSTIFICACION` con la función de parámetros existente. No se escribe el número en el código.
- Si `fecha de la sesión + N días < fecha actual (America/Bogota)`, rechaza con un mensaje nuevo del catálogo.
- El valor se podrá cambiar desde el futuro componente de parámetros (decisión de John: HU168 lo espera).
- Si más adelante se cambia a días hábiles, hará falta un calendario de festivos. Queda fuera de este alcance.

### 3. Soporte obligatorio por categoría (propuesta)

- Columna nueva `CategoriaJustificacion.requiereSoporte BIT NOT NULL DEFAULT 0`, cargada por seed.
- Mapeo propuesto (pendiente de que John lo confirme):

| Código | Categoría | Exige soporte |
|---|---|---|
| MED | Médico / Salud | Sí (incapacidad o constancia médica) |
| ACA | Académico / Representación | Sí (constancia de la actividad) |
| LAB | Laboral | Sí (certificado laboral) |
| CAL | Calamidad Doméstica | No (se acepta si se adjunta) |
| FMA | Fuerza Mayor | No |
| OTR | Otro | No |

- SP v2: si `requiereSoporte = 1` y `@idArchivoSoporte IS NULL`, rechaza con un mensaje nuevo del catálogo. La subida (`usp_registrar_archivo_soporte`, antivirus, MinIO) y la descarga no cambian.
- Frontend: marca el adjunto como obligatorio según la categoría elegida, antes de enviar.
- Hay que ajustar las pruebas de BD, backend y E2E que radican sin archivo, para que usen una categoría que no exija soporte.

### 4. HU014 (justificación médica)

HU014 queda cubierta por la categoría MED más su soporte obligatorio. No necesita un formulario aparte: el mismo formulario cambia el texto de ayuda y exige el soporte cuando se elige MED.

## Lista de verificación del PR coordinado

- [ ] DDL de la columna y la FK en un script idempotente bajo `schema/tables` + migración `13_..._up/down.sql`.
- [ ] Cambios en el SP v2 y en los SP de consulta del docente, con pruebas T-060, T-026B y T-SOP en `test_lb004d_support_binding.sql`.
- [ ] Mensajes nuevos en el seed y `scripts/generar-catalogo-mensajes.ps1` regenerado.
- [ ] `scripts/lb004d-manifest.ps1` regenera `DB_LB004D_SUPPORT_BINDING_MANIFEST.sha256`, con aprobación del dueño de LB-004D.
- [ ] Backend: el detalle del docente con la categoría y el mapeo de los errores nuevos. Frontend: adjunto obligatorio por categoría.
- [ ] Cerrar TD-060 en `TECHNICAL_DEBT.md`. HU026B y HU014 pasan a Fase 3 en el HU-CATALOG.
