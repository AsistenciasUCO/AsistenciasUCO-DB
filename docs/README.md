# 📚 Índice General de Documentación - gestionasistenciadb

Bienvenido a la documentación oficial del sistema de base de datos `gestionasistenciadb`. La documentación está organizada en 5 categorías principales para facilitar la navegación y el mantenimiento.

---

## 🏛️ 1. Arquitectura y Especificaciones de Backend (`docs/arquitectura/`)

Documentos principales que definen las reglas de negocio, firmas de endpoints, patrones de transacciones y el plan general de desarrollo:

- 📄 [**`backend_specification.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/backend_specification.md): Especificación maestra del modelo relacional, endpoints, tipos de datos y reglas de negocio.
- 📄 [**`Plan_de_Trabajo_Historias_de_Usuario.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/Plan_de_Trabajo_Historias_de_Usuario.md): Matriz completa de las 179 Historias de Usuario (`HU001` a `HU179`).
- 📄 [**`DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_INTERNOS.md): Especificación de procedimientos internos (`*_interno`).
- 📄 [**`DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_PUBLICOS.md): Especificación de procedimientos públicos sin sufijo `_interno`.
- 📄 [**`DOCUMENTACION_PROCEDIMIENTOS_ORQUESTADORES.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/DOCUMENTACION_PROCEDIMIENTOS_ORQUESTADORES.md): Especificación de orquestadores transaccionales.
- 📄 [**`6_Entregable.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/6_Entregable.md): Documento borrador/consolidado del trabajo de grado.
- 📄 [**`especificacion_sp_endpoints.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/especificacion_sp_endpoints.md): Mapeo directo entre procedimientos almacenados y endpoints consumidos por la API.
- 📄 [**`transaccion-procedimiento.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/arquitectura/transaccion-procedimiento.md): Especificación técnica canónica de transacciones T-SQL en base de datos.

---

## 📐 2. Modelos de Diseño y Dominio (`docs/modelos/`)

Modelos gráficos y conceptuales del sistema en sintaxis Mermaid y especificaciones de clases:

- 📄 [**`ModeloEntidadRelacion.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/modelos/ModeloEntidadRelacion.md): Diagrama Entidad-Relación (MER) físico y lógico.
- 📄 [**`DiagramaDeClases.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/modelos/DiagramaDeClases.md): Diagrama de clases y entidades orientadas a objetos.
- 📄 [**`DiagramaDeDominio.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/modelos/DiagramaDeDominio.md): Modelo conceptual de dominios académicos y de asistencia.

---

## 📋 3. Catálogos Maestros y Configuración (`docs/catalogos/`)

Catálogos estandarizados consumidos por los procedimientos almacenados y lógica de aplicación:

- 📄 [**`catalogo-mensajes.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/catalogos/catalogo-mensajes.md): Mensajes del sistema (códigos de validación, error y éxito).
- 📄 [**`catalogo-parametros.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/catalogos/catalogo-parametros.md): Parámetros globales y constantes del sistema.
- 📄 [**`prioridades-desarrollo.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/catalogos/prioridades-desarrollo.md): Matriz de priorización de desarrollo por entregables.

---

## 📊 4. Reportes de Auditoría e Históricos (`docs/reportes/`)

Informes de auditoría y análisis arquitectónicos realizados sobre la base de datos:

- 🌐 [**`reporte_analisis_arquitectura_rbac.html`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/reportes/reporte_analisis_arquitectura_rbac.html): Reporte técnico de la arquitectura de Vistas Autorizadas (`uv_auth_*`) y RBAC.
- 📄 [**`reporte_auditoria_roles_permisos_jerarquia_develop.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/reportes/reporte_auditoria_roles_permisos_jerarquia_develop.md): Auditoría de roles y custodia jerárquica.
- 📄 [**`reporte_comparativo_transacciones_especificacion.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/reportes/reporte_comparativo_transacciones_especificacion.md): Análisis comparativo de cobertura transaccional.
- 📄 [**`reporte_historias_de_usuario_cobertura_develop.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/reportes/reporte_historias_de_usuario_cobertura_develop.md): Reporte de cobertura de HUs en la base de datos.
- 📄 [**`PR_Eliminar.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/reportes/PR_Eliminar.md): Listado analítico de procedimientos complejos objeto de depuración.

---

## 🗄️ 5. Datos y Muestreo de Entidades (`docs/datos/`)

- 📄 [**`ListadoObjetosDominio.md`**](file:///c:/Users/Jhon/Documents/IngSistUco/TrabajoGrado/Repositorio_GestionAsistenciadb/docs/datos/ListadoObjetosDominio.md): Inventario de objetos y datos de muestreo.
