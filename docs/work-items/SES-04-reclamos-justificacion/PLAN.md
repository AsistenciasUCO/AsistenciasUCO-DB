---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-11-03
---

# PLAN — SES-04: reclamo aprobado → asistencia JUSTIFICADA (EX)

Rama `fix/ses04-reclamo-justificada` desde `develop@d82ad2f` (independiente de SES-01). Origen: backend
`SEC-BASELINE-019/PLAN-CORRECCIONES-POR-ROL.md`, decisión confirmada 2 (2026-11-02) y SES-04.

## Causa corregida (`usp_resolver_solicitud_revision_asistencia`)

| Defecto AS-IS | Corrección |
|---|---|
| Aprobar ejecutaba `UPDATE DetalleAsistencia SET asistio = 1` (presencia falsa, causal SJC intacta) | Aprobar deja `razonCausa = EX` y `asistio = 0` (JUSTIFICADA) |
| Cualquier `@accion` distinta de APROBADA se trataba como RECHAZADA | Solo `APROBADA`/`RECHAZADA` (TRIM+UPPER); otro valor → `REV_001` sin escrituras |
| Sin control de estado: se podía resolver dos veces o contradecir una decisión | Solicitud leída con `UPDLOCK, HOLDLOCK` en la transacción; solo `P` se resuelve; misma decisión = éxito idempotente sin escrituras; contradictoria → `REV_002` |
| Si faltaba el estado A/R se usaba la primera fila de `dbo.Estado` | Catálogo cerrado: falta de Estado o de `RazonCausa EX` → error técnico, sin escribir |
| Solicitud inexistente devolvía `VAL_002` (mensaje de documento de identidad) | `REV_005` |
| Sin detalle de asistencia el UPDATE no hacía nada y la solicitud quedaba aprobada | `REV_004`: no se simula la justificación |
| Se podía "aprobar" sobre una presencia | `REV_003` |
| Sin auditoría de la rectificación | `dbo.AuditoriaEvento` en la misma transacción: actor, correlación, estado previo/nuevo de solicitud y detalle, respuesta |

Se conservan: firma, resultset de 4 columnas, titularidad (`VAL_007`), RBAC DOCENTE, `XACT_ABORT ON` (REC3). El SP no
está en los manifiestos de congelamiento; la autorización expresa del responsable del proyecto (2026-11-03) cubre de
todos modos los cambios de SP de SES-01..05. No consume la ventana SES-01: la rectificación es válida tras el cierre.
El soporte es opcional en el contrato vigente (LB-004D `W2_WITHOUT_SUPPORT`), por lo que no se exige para aprobar.

## Pruebas (`test/test_ses04_reclamo_justificada.sql`, 11 IDs)

`SES04_INVALID_ACTION`, `SES04_NOT_FOUND`, `SES04_NON_OWNER`, `SES04_APPROVE_SJC_TO_EX`, `SES04_APPROVE_AUDITED`,
`SES04_APPROVE_IDEMPOTENT`, `SES04_CONTRADICTORY_REJECTED`, `SES04_REJECT_KEEPS_ATTENDANCE`, `SES04_NO_DETAIL`,
`SES04_PRESENT_NOT_JUSTIFIABLE`, `SES04_AFTER_SESSION_CLOSE`.
Ajustes: `REVIEW_RESOLVE_SUCCESS` afirmaba el defecto (`asistio = 1`) y ahora exige `EX` + `asistio = 0`;
REC3 TX-02 inyecta su falla en la nueva segunda escritura (causal EX) y sigue exigiendo reversión total.

## Despliegue y reversión
Mecanismo oficial: `usp_resolver_solicitud_revision_asistencia` + filas `REV_001..005` de `04_mensaje.sql`.
Reversión: `CREATE OR ALTER` de la versión anterior. Sin cambios de esquema ni migración de datos.
**Rectificaciones históricas** hechas con la versión anterior (SJC con `asistio = 1`) no se corrigen aquí: requieren
una decisión y un script aprobado aparte (dependencia SES-05).
