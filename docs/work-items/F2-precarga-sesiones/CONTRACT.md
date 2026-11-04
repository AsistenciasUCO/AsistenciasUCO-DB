---
status: active
type: contract
scope: db
owner: db-team
last-reviewed: 2026-11-04
---

# Contrato de continuación SES-02 — precarga de sesiones

## Alcance

Esta continuación extiende las pruebas del work-item F2 y cierra un defecto para períodos vencidos. No cambia tablas, vistas, mensajes, firmas públicas ni firmas internas. El procedimiento congelado `dbo.usp_generar_sesiones_grupo` permanece intacto.

## Firmas vigentes

- `dbo.usp_precargar_sesiones_grupo(@idGrupo UNIQUEIDENTIFIER, @idCorrelacion UNIQUEIDENTIFIER, @idUsuarioEjecutor UNIQUEIDENTIFIER = NULL)`: devuelve una fila canónica con `idCorrelacion UNIQUEIDENTIFIER`, `mensajeUsuarioResultado NVARCHAR(4000)`, `mensajeTecnicoResultado NVARCHAR(4000)` y `estadoResultado BIT`.
- `dbo.usp_precargar_sesiones_grupo_interno(@idGrupo UNIQUEIDENTIFIER, @idCorrelacion UNIQUEIDENTIFIER, @sesionesCreadas INT OUTPUT, @sesionesEliminadas INT OUTPUT, @mensajeUsuarioResultado NVARCHAR(4000) OUTPUT, @mensajeTecnicoResultado NVARCHAR(4000) OUTPUT, @estadoResultado BIT OUTPUT)`: mutación atómica dentro de la transacción controlada por el público.

## Reglas verificables

1. COORDINADOR del programa o DOCENTE titular pueden precargar; un actor sin perfil recibe `SEC_001` y un actor fuera de su dominio recibe `SEC_002`, sin escritura.
2. Para el calendario semanal, solo se materializan slots futuros cuyas fechas civiles estén dentro del período académico. Si hoy es posterior a `fechaFin`, el conjunto de fechas queda vacío.
3. Repetir o ejecutar en paralelo la precarga mantiene una sesión por slot, números consecutivos únicos y códigos únicos.
4. Al cambiar el horario, solo se pueden retirar sesiones futuras `UTC_GENERADOR` sin asistencia ni clasificación. Las sesiones con evidencia, las sesiones históricas y las sesiones manuales `UTC_V2` se conservan.
5. Las fechas se interpretan en la zona civil institucional y se persisten en UTC con marca `UTC_GENERADOR`.
6. `rol_asistencias_runtime` puede ejecutar el SP público, no el interno, y no recibe DML directo en `Sesion`.

## Catálogos y límites

Se reutilizan los mensajes existentes `GEN_001`, `GEN_005`, `SES_005`, `SEC_001`, `SEC_002` y `VAL_002`. La exclusión de feriados, recesos o suspensiones no forma parte de este contrato hasta que exista una regla institucional y una fuente de calendario autorizada.

## Validación

Los escenarios se registran en `test/test_usp_precargar_sesiones_grupo.sql` y `test/test_usp_precargar_sesiones_concurrency.ps1`, ejecutados por `test_summary.ps1` y el workflow `DB Quality Gate` en CI. No se ejecutan contra la instancia SQL local compartida.
