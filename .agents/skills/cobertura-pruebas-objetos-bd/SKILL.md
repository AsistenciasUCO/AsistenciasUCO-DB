---
name: cobertura-pruebas-objetos-bd
description: >-
  Estándar obligatorio de pruebas unitarias y cobertura completa de caminos (Happy Path, Edge Cases, Errores y Roles) para todo USP, Vista o Función creada o modificada en gestionasistenciadb.
---

# Estándar de Cobertura de Pruebas Unitarias para Objetos de Base de Datos

## Propósito y Regla Principal de Cobertura

Esta documentación establece la directiva obligatoria de pruebas unitarias para la base de datos `gestionasistenciadb`.

### Regla Fundamental
> **Por cada Procedimiento Almacenado (`usp_*` / `*_interno`), Vista (`uv_*` / `uv_auth_*`) o Función (`ufn_*` / `fn_*`) que sea creado o modificado en `schema/`, es estrictamente obligatorio crear o actualizar su script de pruebas unitarias en `test/` garantizando la cobertura de TODOS los caminos lógicos posibles.**

---

## Requisitos de Cobertura de Caminos por Tipo de Objeto

### 1. Procedimientos Almacenados (`usp_*` y `*_interno`)
Todo script de prueba en `test/test_<nombre_procedimiento>.sql` debe evaluar de forma aislada e idempotente:

* **Camino Exitoso (*Happy Path*)**:
  - Inserción/actualización con datos válidos.
  - Verificación de `@estadoResultado = 1`.
  - Verificación del mensaje del catálogo devuelto por `dbo.usp_obtener_mensaje_catalogo`.
  - Verificación de persistencia de datos en la vista o tabla correspondiente (`uv_*`).

* **Caminos de Validación y Error (*Sad Paths & Edge Cases*)**:
  - Parámetros obligatorios nulos o vacíos (`numeroIdentificacion`, `correo`, `idCorrelacion`, etc.).
  - Formatos inválidos (ej. correo electrónico con estructura incorrecta).
  - Referencias a entidades inexistentes (ej. `idGrupo` o `idUsuario` no encontrado).
  - Violación de restricciones de negocio (ej. cruce de horarios, cupo máximo alcanzado, duplicidad de registro).
  - Verificación de `@estadoResultado = 0` y el código de error de catálogo esperado (`VAL_*`, `ERR_*`).

* **Aislamiento Transaccional e Idempotencia**:
  - Garantizar que las pruebas fallen limpiamente haciendo `ROLLBACK TRANSACTION` para no dejar datos basura en la base de datos de prueba.
  - Preservación de la transacción externa (`@@TRANCOUNT`) mediante el uso adecuado de `SAVE TRANSACTION`.

---

### 2. Vistas Autorizadas y de Consulta (`uv_auth_*` y `uv_*`)
Todo script de prueba de vistas en `test/` debe validar:

* **Contexto nulo (`SESSION_CONTEXT` nulo)**:
  - Verificar que sin usuario ejecutor en la sesión, la vista retorne la totalidad de los registros por defecto (`full visibility`).

* **Aislamiento por Rol y Dominio**:
  - Simular sesión de `ADMINISTRADOR` (`AD`) y verificar que solo retorne datos de su Institución.
  - Simular sesión de `DECANO` (`DE`) y verificar que solo retorne datos de su Facultad a cargo.
  - Simular sesión de `COORDINADOR` (`CD`) y verificar que solo retorne datos de su Programa a cargo.
  - Simular sesión de `DOCENTE` (`DO`) y verificar que solo retorne datos de sus Grupos/Asignaturas asignadas.

---

### 3. Funciones Escalares y de Tabla (`ufn_*` y `fn_*`)
Todo script de prueba de funciones en `test/` debe evaluar:

* **Entradas Válidas (*Happy Path*)**:
  - Verificación del valor de retorno o resultset esperado para entradas válidas (ej. casteo correcto de GUIDs, validación exitosa de formato de correo, contraseña o número).
  - Evaluación del valor por defecto recuperado desde la tabla `Parametro` cuando aplica.

* **Tratamiento de Valores Nulos y Cadenas Vacías**:
  - Evaluación del comportamiento cuando se pasan parámetros `NULL` o cadenas vacías (retorno seguro, fallback a valor por defecto o retorno `NULL` según contrato).

* **Casos Borde y Validaciones de Formato (*Edge Cases*)**:
  - Limpieza de cadenas con espacios extras (`TRIM`).
  - Formatos de texto invalidados (ej. `ufn_validar_correo`, `ufn_validar_numero`, `ufn_validar_password`, `ufn_validar_texto`).
  - Intentos de casteo inválidos utilizando `TRY_CAST` (ej. `ufn_obtener_parametro_guid`, `ufn_obtener_parametro_int`).

---

## Integración al Orquestador y Registro de Pruebas

1. **Inclusión en `test_suite.sql`**:
   Todo nuevo script de prueba creado en `test/test_<objeto>.sql` debe registrarse obligatoriamente en `test_suite.sql`:
   ```sql
   :r /tmp/test/test_<objeto>.sql
   ```

2. **Emisión de Identificadores de Aprobación (`TEST_PASS:<ID>`)**:
   Cada escenario evaluado dentro del script SQL debe emitir un token único de éxito utilizando la sintaxis:
   ```sql
   PRINT 'TEST_PASS:NOMBRE_ESCENARIO_SUCCESS';
   ```

3. **Verificación Imperativa del Quality Gate**:
   No se declara finalizado ningún objeto o cambio sin ejecutar la compilación y la suite de pruebas:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\deploy_schema.ps1
   powershell -ExecutionPolicy Bypass -File .\test_summary.ps1
   ```
   **Criterio de Éxito:** La salida debe ser obligatoriamente `DB GATE PASS` con código de retorno `0`.
