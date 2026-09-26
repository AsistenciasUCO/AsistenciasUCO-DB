# Gestión de Asistencias - Base de Datos (gestionasistenciadb) 🗄️

![DB Quality Gate CI/CD](https://github.com/johnjduque/gestion-asistencia-db/actions/workflows/ci.yml/badge.svg?branch=develop)

Este repositorio contiene el diseño lógico, la estructura y los objetos programables de la base de datos para el **Sistema de Gestión de Asistencias**. El entorno de desarrollo está completamente dockerizado para garantizar que todos los miembros del equipo trabajen sobre la misma versión del motor de bases de datos de forma idéntica.

---

## LOCAL DEVELOPMENT BASELINE

```text
Container: sql_server_asistencias
Database: gestionasistenciadb
State: ALIGNED_WITH_FROZEN_BASELINE
Temporary validation container: REMOVED
DBCODE: ENABLED
Golden Path: FROZEN
Backend integration target: sql_server_asistencias / gestionasistenciadb
```

La base local oficial de desarrollo es `gestionasistenciadb` dentro de `sql_server_asistencias`. Debe desplegarse desde el codigo SQL versionado actual del repositorio, no copiando archivos fisicos de otra instancia.

## FREEZE STATUS (DB-GP-001C)

```text
DB Golden Path: FROZEN (docs/contracts/DB_BASELINE_CONTRACT.md, sin cambios)
develop extensions: FROZEN as of final commit (docs/contracts/DB_DEVELOP_FREEZE_ADDENDUM.md)
uv_auth_*: FAIL_CLOSED (sin SESSION_CONTEXT => 0 filas)
Manifest: docs/contracts/DB_DEVELOP_FREEZE_MANIFEST.sha256 (verificado por test_summary.ps1)
```

El backend solo puede depender del contrato aprobado (`DB_BASELINE_CONTRACT.md`) salvo que un nuevo work item de alineacion adopte una extension. Todo cambio de esquema posterior al freeze requiere un nuevo work item / decision de contrato. Ver `docs/arquitectura/DB_SESSION_CONTEXT_Y_VISTAS_AUTORIZADAS.md`.

Secretos: copie `.env.template` a `.env` (ignorado por Git) y reemplace `CHANGE_ME`. Nunca versione una contrasena; el gate `NO_HARDCODED_DB_PASSWORD` escanea scripts, workflows y plantillas `.env*`.

---

## 🛠️ Stack Tecnológico
* **Motor:** SQL Server 2022+ (Compatibilidad Nivel 160)
* **Entorno Local:** Docker & Docker Desktop
* **IDE Recomendado:** VS Code / Antigravity IDE con extensión *SQL Server (mssql)* o Azure Data Studio / SSMS 21.
* **Control de Versiones:** Git + GitHub / Azure DevOps

---

## 📁 Arquitectura Universal del Esquema (`/schema`)

El proyecto utiliza un **enfoque modular por objetos**. En lugar de crear archivos de parches sueltos (`fix-*.sql`), cada objeto de la base de datos se mantiene en un archivo `.sql` individual bajo la carpeta `schema/`:

```text
/schema
├── /tables/              <-- Un archivo por cada Tabla (ej. Usuario.sql, Grupo.sql)
├── /functions/           <-- Un archivo por cada Función UFN (ej. ufn_validar_correo.sql)
├── /views/               <-- Un archivo por cada Vista (ej. uv_usuario.sql)
└── /stored-procedures/   <-- Un archivo por cada Procedimiento Almacenado (ej. usp_sincronizar_usuario_interno.sql)
```

### 💡 Flujo de Modificación
1. Edita directamente el archivo del objeto que necesites modificar (por ejemplo `schema/stored-procedures/usp_sincronizar_usuario_interno.sql`).
2. Ejecuta el script universal `.\deploy_schema.ps1` para compilar los cambios en tu entorno local.

---

## ⚙️ Guía de Despliegue y Pruebas Locales (Paso a Paso)

### 1. Prerrequisitos
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) ejecutándose.

### 2. Levantar el Contenedor de SQL Server
Si aún no tienes el contenedor activo, créalo ejecutando el siguiente comando en PowerShell:

```powershell
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=<MSSQL_SA_PASSWORD>" -p 1433:1433 --name sql_server_asistencias -d mcr.microsoft.com/mssql/server:2022-latest
```

---

## 🚀 Comandos de Despliegue y Pruebas

### 🔹 Desplegar todo el Esquema Modular (`deploy_schema.ps1`)
Para compilar y aplicar todas las tablas, funciones, vistas y procedimientos almacenados en la base de datos en Docker, ejecuta:

```powershell
.\deploy_schema.ps1 -ContainerName "sql_server_asistencias"
```

### 🔹 Ejecutar el Quality Gate (`test_summary.ps1`)
Para validar el baseline completo congelado, ejecuta:

```powershell
.\test_summary.ps1 -ContainerName "sql_server_asistencias"
```

### 🔹 Reiniciar y Limpiar la Base de Datos desde Cero
Si deseas simular una instalación fresca y verificar el esquema completo:

```powershell
# 1. Recrear Base de Datos Vacía en Docker
docker exec -i sql_server_asistencias /opt/mssql-tools18/bin/sqlcmd -S localhost -C -d master -Q "ALTER DATABASE gestionasistenciadb SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE gestionasistenciadb; CREATE DATABASE gestionasistenciadb;"

# 2. Desplegar todo el esquema
.\deploy_schema.ps1 -ContainerName "sql_server_asistencias"

# 3. Correr Pruebas
.\test_summary.ps1 -ContainerName "sql_server_asistencias"
```
