---
name: procedimientos-externos-condiciones
description: >-
  Estándar canónico corporativo y reglas estructurales obligatorias para todos los procedimientos almacenados públicos u orquestadores (sin sufijo _interno) en gestionasistenciadb.
---

# Documentación Técnica de Arquitectura: Procedimientos Almacenados Públicos / Orquestadores (Sin Sufijo _interno)

## Generalidades del Estándar Canónico para Procedimientos Públicos

Esta documentación especifica la arquitectura, reglas de negocio, contrato de firma, estructura del resultset unificado y flujo de control para **todos los Procedimientos Almacenados Públicos u Orquestadores** (aquellos sin el sufijo `_interno`) en la base de datos `gestionasistenciadb`.

### Reglas Estructurales Obligatorias (Modelo Canónico)
1. **Inmutabilidad de Nombres Preexistentes**: Queda **estrictamente prohibido renombrar o alterar el nombre de los procedimientos almacenados, vistas, funciones o tablas preexistentes** en la base de datos. Todos los objetos ya creados deben conservar su nombre original sin modificaciones.
2. **Firma de Cabecera Sin Parámetros OUTPUT**:
   - Los procedimientos públicos/orquestadores NO llevan parámetros de salida (`OUTPUT`) en su firma de cabecera.
   - Todo parámetro de entrada de tipo `UNIQUEIDENTIFIER` (UUID) inicia obligatoriamente con el prefijo `id` (`@idTipoIdIdentificacion`, `@idGrupo`, `@idCorrelacion`, `@idEstudianteGrupo`, `@idGrupoSesion`, `@idEstadoAsistencia`, `@idEstudiante`, `@idSesion`).
2. **Zona de Declaración e Inicialización (`AS` ... `BEGIN`)**:
   - Declaraciones con `DECLARE` ubicadas **exclusivamente en la cabecera: después del `AS` y antes del primer `BEGIN`**.
   - Inicialización de GUIDs por defecto utilizando `dbo.ufn_obtener_parametro_guid(@variable, 'GENERAL', 'GUID_DEFECTO_CORRELACION')`.
   - Limpieza de texto únicamente mediante `TRIM(@variable)`.
   - **PROHIBIDO EL USO DE `ISNULL` O `COALESCE`**.
   - Variables locales de respuesta inicializadas internamente:
     ```sql
     DECLARE @mensajeUsuarioResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @mensajeTecnicoResultado NVARCHAR(4000) = dbo.ufn_obtener_parametro('GENERAL', 'CADENA_VACIA');
     DECLARE @estadoResultado BIT = 1;
     ```
3. **Flujo Lógico Estandarizado de Gestión de Entidades y Consulta por Vistas**:
   - **Obligatoriedad de Consulta a Través de Vistas Base (`uv_*`)**: Toda lectura o validación de existencia de información dentro del procedimiento público u orquestador debe realizarse obligatoriamente por medio de las **vistas base (`uv_*`)** (ej. `uv_docente`, `uv_estudiante_grupo`, `uv_sesion`), estando prohibido realizar `SELECT` directo a tablas físicas del MER.
   - Consultar si existe en la vista correspondiente (`uv_...`).
   - Si existe: validar estado activo y actualizar datos pertinentes.
   - Si no existe: invocar al procedimiento interno de sincronización/creación (`*_interno`).
4. **Estructura de Bloques y Documentación Paso a Paso**:
   - Inicio del cuerpo con `BEGIN SET NOCOUNT ON; BEGIN TRY ... END TRY BEGIN CATCH ... END CATCH`.
   - Comentarios estructurados por pasos (`-- PASO 1: ...`, `-- PASO 2: ...`).
   - Todo `IF` lleva explícitamente `BEGIN` y `END`.
5. **Consumo Centralizado del Catálogo de Mensajes**:
   - Invocación a `dbo.usp_obtener_mensaje_catalogo` concatenando `' Correlacion: ' + CAST(@idCorrelacionDefecto AS NVARCHAR(50))` al mensaje técnico.
   - Manejo de excepciones en bloque `CATCH` invocando `'SYS_001'` y capturando la traza mediante `dbo.ufn_obtener_detalle_error(@idCorrelacionDefecto)`.
6. **Bloque Final Obligatorio de Retorno (Resultset Unificado)**:
   ```sql
   SELECT
       idCorrelacion           = @idCorrelacionDefecto,
       mensajeUsuarioResultado = @mensajeUsuarioResultado,
       mensajeTecnicoResultado = @mensajeTecnicoResultado,
       estadoResultado         = @estadoResultado;
   ```
