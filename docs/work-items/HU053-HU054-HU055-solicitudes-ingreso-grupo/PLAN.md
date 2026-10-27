---
status: active
type: work-item
scope: db
owner: db-team
last-reviewed: 2026-10-27
---

# PLAN — HU053-HU054-HU055-solicitudes-ingreso-grupo: solicitudes de ingreso a un grupo

## Identidad y objetivo

- Objetivo: el estudiante solicita el ingreso a un grupo; el docente titular acepta (con cupo matricula, sin cupo queda en lista de espera) o rechaza con motivo; el docente puede aceptar a cualquiera de la lista de espera cuando se libera cupo; el estudiante puede retirar su solicitud abierta. Sin vencimiento.
- **Cambio de esquema aprobado por John el 2026-10-27** (skill `consistencia-tablas`, D1): tabla nueva `SolicitudIngresoGrupo` y estados `E` (en espera) y `X` (retirada) en `dbo.Estado`.
- Rama apilada sobre `feature/HU051-retirar-estudiante-grupo` (la prueba usa `usp_retirar_estudiante_grupo` para liberar cupo).
- Contrato HTTP y validación de las 3 capas: work item homónimo del backend.

## Análisis de impacto (consistencia-tablas)

| Área | Impacto |
|---|---|
| Tablas existentes | **Ninguna se modifica.** Solo se agregan FKs **desde** `SolicitudIngresoGrupo` hacia `Estudiante`, `Grupo`, `Estado`, `Docente` y `EstudianteGrupo` (`zz_foreign_keys.sql`, entradas 42-46). |
| Objetos congelados | Ninguno tocado; `scripts/freeze-manifest.ps1 -Mode Verify` = 0. |
| Vistas `uv_*` / `uv_auth_*` | Sin cambios. Las matrículas creadas al aceptar son filas normales de `EstudianteGrupo`. |
| SP existentes | Se **reutiliza sin modificar** `usp_registrar_estudiante_en_grupo_interno` (valida cupo, cruce de horario y duplicados). `usp_resolver_solicitud_matricula` (coordinador, stub) queda igual. |
| Semillas | `22_estados_solicitud_ingreso_grupo.sql` (E, X con ids fijos, referenciados por el índice filtrado); `23_mensajes_solicitud_ingreso_grupo.sql` (`SIG_001..SIG_015`). |
| `dbo.Estado` compartido | Los reclamos (`SolicitudRevisionAsistencia`) siguen usando P/A/R; la suite completa de reclamos sigue en verde. |
| Pruebas | `test/test_solicitud_ingreso_grupo.sql` (S-01..S-12); exclusiones de lectura y del comando con columna extra en `test_contract_closure.sql`. |

## Objetos de base de datos

| Objeto | Cambio |
|---|---|
| `schema/tables/SolicitudIngresoGrupo.sql` | Nueva tabla + `UX_SolicitudIngresoGrupo_Abierta` (única filtrada P/E por estudiante y grupo) + `IX_SolicitudIngresoGrupo_Grupo_Estado_Fecha` |
| `usp_registrar_solicitud_ingreso_grupo` | Nuevo (estudiante) |
| `usp_resolver_solicitud_ingreso_grupo` | Nuevo (docente titular; `UPDLOCK, HOLDLOCK` del grupo; columna extra `codigoEstadoResultante`) |
| `usp_retirar_solicitud_ingreso_grupo` | Nuevo (estudiante propietario) |
| `usp_consultar_solicitudes_ingreso_grupo_docente`, `usp_consultar_solicitudes_ingreso_estudiante`, `usp_consultar_destinatarios_solicitud_ingreso_grupo` | Nuevos (lectura) |
| `schema/security/rol_asistencias_runtime_hu053_hu055.sql` | `GRANT EXECUTE` aditivo (THROW 52183..52188) |

## Reglas aplicadas (AGENTS.md)

- Ámbito en tablas base dentro de cada SP (estudiante propietario por `Estudiante.usuario`; docente titular por `Grupo.docente → Docente.usuario`).
- Fecha local para "período terminado" con `TIEMPO.ZONA_HORARIA_SQLSERVER` (como HU051).
- Mensajes por catálogo; sin textos quemados.

## Rollback

`DROP` de los 6 SP, de las 5 FKs y de la tabla; borrar los estados E/X y los mensajes `SIG_*`. Ninguna tabla existente requiere reversión.
