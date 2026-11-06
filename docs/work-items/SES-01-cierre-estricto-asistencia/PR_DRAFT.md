# PR — SES-01 (DB): ventana estricta de registro de asistencia

**Base:** `develop` · **Rama:** `fix/ses01-cierre-estricto-asistencia` · **Orden de integración:** 1/3 (DB → Backend → Frontend)

## Alcance funcional
El registro ordinario (`usp_registrar_asistencias_sesion`) y el autónomo (`usp_registrar_asistencia_estudiante_autonomo`) solo escriben con la sesión activa: `fechaHoraInicio <= SYSUTCDATETIME() < fechaHoraFin`, con procedencia UTC confirmada. Sin tolerancia posterior al cierre. La rectificación posterior es solo por reclamos (SES-04).

## Causa corregida
Ninguno de los dos SP comparaba el instante de escritura con el horario: una sesión cerrada o futura aceptaba asistencias por API directa.

## Contrato
- Firmas y resultset de 4 columnas: **sin cambio**.
- Nuevo SP interno `usp_validar_sesion_ventana_registro_interno` (sin grant runtime): lee la sesión con `UPDLOCK, HOLDLOCK` dentro de la transacción del llamador.
- Lote: valida antes de escribir (PASO 4.0) y de nuevo antes del `COMMIT` (PASO 4.2). Autónomo: ahora con transacción propia o savepoint.
- Nuevos mensajes `SES_007` (no iniciada), `SES_008` (cerrada), `SES_009` (procedencia INDETERMINADA).
- Sin columnas nuevas en `dbo.Sesion`.

## Excepción de congelamiento
`usp_registrar_asistencias_sesion` está congelado (DB-GP-001C). Excepción **autorizada expresamente por el responsable funcional del proyecto** (2026-11-03), registrada en `DB_DEVELOP_FREEZE_ADDENDUM.md`; supersesión en `DB_UTC_D06_POST_FREEZE_MANIFEST.sha256` (`a0372fd6…` → `7217604b…`) y `freeze-manifest.ps1`.
**@johnjduque: se solicita su revisión formal como owner DB antes de fusionar.**

## Pruebas
- RED/GREEN: `test/test_ses01_ventana_asistencia.sql` — 12 IDs `SES01_*` (antes del inicio, inicio exacto, durante, justo antes del fin, fin exacto, +2 h, INDETERMINADA, histórico intacto, autónomo ×3, bloqueo retenido).
- Regresión: `test_attendance_commands.sql` y `ATTENDANCE_CONCURRENT_UPSERT` con sesiones activas `UTC_V2`; golden path (firmas, resultset, manifiesto).
- Local: `PARSEONLY` PASS y `freeze-manifest -Mode Verify` PASS. La suite contra la instancia local está **NOT_RUN** (la política del entorno bloquea desplegar SP en `sql_server_asistencias`, incluso en transacción revertida). **La certificación es el CI de este PR.**

## Despliegue y reversión
Despliegue solo por el mecanismo oficial, en este orden: `usp_validar_sesion_ventana_registro_interno`, los dos SP públicos y las filas `SES_007..009` de `04_mensaje.sql` (sin re-ejecutar seeds que pisen valores vivos). Reversión: `CREATE OR ALTER` de las versiones anteriores de los dos SP. Los mensajes nuevos pueden quedarse.

## Dependencias
Backend `alejovh12/AsistenciasUCO#?` (409 + mapeo `SES_00x`) y Frontend `shesho22/AsistenciasUCO-Frontend#?`.

## Limitaciones
- La carrera en el instante de cierre entre dos conexiones se garantiza por diseño (bloqueo + revalidación); no hay una prueba de dos conexiones.
- E2E y navegador se ejecutan después del merge y despliegue.
