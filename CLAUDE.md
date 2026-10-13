# CLAUDE.md

Guía operativa del repositorio de base de datos para Claude Code y asistentes de IA.

> **Fuente de verdad:** Este archivo es un índice operativo. La gobernanza normativa, principios obligatorios y precedencia están estipulados en [AGENTS.md](AGENTS.md). **Si algo aquí discrepa con AGENTS.md o con el contrato de baseline, gana AGENTS.md.**

---

## ⚡ Comandos Clave (PowerShell)

### Entorno Docker Automatizado (Recomendado)
```powershell
# Levantar SQL Server, esperar estado healthy, desplegar esquema y correr pruebas
.\run_local_env.ps1 -All

# Solo iniciar contenedor y esperar healthcheck
.\run_local_env.ps1 -Up

# Desplegar esquema sobre el contenedor activo
.\run_local_env.ps1 -Deploy

# Correr suite de pruebas sobre el contenedor activo
.\run_local_env.ps1 -Test

# Detener el contenedor
.\run_local_env.ps1 -Down

# Detener y limpiar volúmenes de datos (reinicio limpio desde cero)
.\run_local_env.ps1 -Clean
```

### Ejecución Manual de Scripts
```powershell
# 1. Despliegue directo del esquema en contenedor SQL Server
.\deploy_schema.ps1

# Despliegue con parámetros explícitos
.\deploy_schema.ps1 -ContainerName "sqlserver" -Password "TuPasswordSeguro123!"

# 2. Ejecución directa y resumen de la suite de pruebas unitarias
.\test_summary.ps1

# Ejecutar pruebas apuntando a un contenedor específico
.\test_summary.ps1 -ContainerName "sqlserver" -Password "TuPasswordSeguro123!"

# 3. Congelamiento y verificación de hashes de manifiestos
.\scripts\freeze-manifest.ps1
```

---

## 🧭 Enrutamiento Rápido de Documentación

Antes de sugerir o modificar código SQL, consulta los documentos de referencia:

| Si vas a trabajar en... | Lee primero: |
| :--- | :--- |
| **Procedimientos Almacenados** | [docs/arquitectura/transaccion-procedimiento.md](docs/arquitectura/transaccion-procedimiento.md)<br>[docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md](docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md)<br>[docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md](docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md) |
| **Contrato Maestro / Baseline** | [docs/contracts/DB_BASELINE_CONTRACT.md](docs/contracts/DB_BASELINE_CONTRACT.md) |
| **Catálogo de Errores y Mensajes** | [docs/catalogos/catalogo-mensajes.md](docs/catalogos/catalogo-mensajes.md) |
| **Parámetros Globales** | [docs/catalogos/catalogo-parametros.md](docs/catalogos/catalogo-parametros.md) |
| **Mapeo con Endpoints de API** | [docs/arquitectura/especificacion_sp_endpoints.md](docs/arquitectura/especificacion_sp_endpoints.md) |
| **Diagrama de Entidad-Relación** | [docs/modelos/ModeloEntidadRelacion.md](docs/modelos/ModeloEntidadRelacion.md) |

---

## 🛠️ Convenciones de Desarrollo T-SQL

- **Separación Interno / Público:**
  - `usp_<nombre>_interno`: Atómico, realiza la mutación en la tabla, recibe parámetros validados.
  - `usp_<nombre>`: Orquestador o fachada pública, valida permisos, inicia transacción y captura excepciones.
- **Transacciones Seguras:**
  - Siempre incluir `SET XACT_ABORT ON;` al inicio de procedimientos mutacionales.
  - Bloque `BEGIN TRY ... BEGIN TRANSACTION ... COMMIT ... END TRY BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK; ... THROW; END CATCH`.
- **Mensajes:**
  - Usar siempre códigos y textos canónicos de [docs/catalogos/catalogo-mensajes.md](docs/catalogos/catalogo-mensajes.md).
- **Pruebas:**
  - Todo cambio debe reflejarse en `test_suite.sql` o suites en `test/` y verificar exit code 0 con `.\test_summary.ps1`.