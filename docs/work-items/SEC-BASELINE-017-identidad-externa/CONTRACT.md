---
status: proposed
type: work-item
scope: database
owner: database-team
last-reviewed: 2026-10-26
---

# SEC-BASELINE-017 — Vínculo persistente de identidad externa (OIDC) → `Usuario.id`

## Problema
El backend de AsistenciasUCO adopta Security Baseline 0.1.7 (Keycloak central). Una identidad OIDC se identifica por
`issuer + subject`. Hasta ahora el backend volvía a localizar al usuario por correo en cada petición: el correo no es un
identificador inmutable y un cambio de correo en el IdP podía apropiar una cuenta.

## Decisión
El correo institucional verificado se usa **solo en la vinculación inicial**. Después, `(emisor, sujeto)` ↔ `Usuario.id`
se persiste y se resuelve por ese vínculo. El UUID institucional no se sustituye por el correo en ningún objeto del Domain.

## Objetos (aditivos; no modifican objetos congelados ni el baseline)
| Objeto | Tipo | Notas |
|---|---|---|
| `dbo.IdentidadExterna` | tabla | PK `id`; FK `usuario → Usuario(id)`; `UNIQUE(emisor, sujeto)`; índice único filtrado `(usuario, emisor) WHERE estado = 1` |
| `dbo.uv_identidad_externa` | vista | Lectura del vínculo para el runtime (SELECT concedido a `rol_asistencias_runtime`) |
| `dbo.usp_vincular_identidad_externa` | SP público | Resultado canónico de 4 columnas. Idempotente; rechaza (GEN_003) identidad ya ocupada/revocada o cuenta con otra identidad vigente del mismo emisor; GEN_001 si el usuario no existe o está inactivo |
| `dbo.usp_revocar_identidad_externa` | SP público | Resultado canónico de 4 columnas. Idempotente; conserva la fila con `estado = 0`; GEN_001 si no existe |
| `rol_asistencias_runtime_sec_baseline.sql` | seguridad | `EXEC` de los dos SP; `DENY` DML directo sobre la tabla |
| `migrations/06_sec_baseline_identidad_externa_{up,down}.sql` | migración | Idempotente; `down` es destructivo para los vínculos (respaldar antes) |

## Reglas de negocio garantizadas por la DB
1. Una identidad externa ocupa una sola cuenta (vigente o revocada). Reutilizarla exige una decisión explícita.
2. Una cuenta tiene como máximo una identidad vigente por emisor.
3. Repetir la vinculación idéntica no duplica filas.
4. Una identidad revocada no se reactiva ni se reasigna.
5. No se almacenan tokens ni secretos; `correoVinculacion` es evidencia de la vinculación inicial.

## Compatibilidad
Sin cambios de firma en objetos existentes. El backend en modo `legacy` no usa esta tabla.

## Rollback
`migrations/06_sec_baseline_identidad_externa_down.sql` (respaldar `dbo.IdentidadExterna` si se necesita la evidencia).
