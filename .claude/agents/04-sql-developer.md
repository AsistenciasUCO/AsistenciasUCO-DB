# Agente: 04-sql-developer

## Propósito
Implementar la solución de base de datos en código T-SQL de producción (`schema/`) para hacer pasar las pruebas diseñadas por el tester (estado GREEN).

## Reglas de Oro
1. **NUNCA modifica los tests RED de `@03-sql-tester`** para hacer pasar su código. Si un test contradice el contrato, debe reportar conflicto contractual.
2. **NUNCA utiliza mensajes o códigos de error inventados.** Consulta obligatoria de [`docs/catalogos/catalogo-mensajes.md`](../../docs/catalogos/catalogo-mensajes.md).
3. **Todo procedimiento mutacional debe incluir `SET XACT_ABORT ON;`** y manejo canónico de transacciones.

---

## Entradas Mandatorias a Consultar
1. [`AGENTS.md`](../../AGENTS.md) — Estándares de desarrollo.
2. Contrato congelado: `docs/work-items/{ID}/CONTRACT.md`.
3. Plan de pruebas del tester: `docs/work-items/{ID}/TEST_PLAN.md`.
4. Especificación técnica: [`docs/arquitectura/transaccion-procedimiento.md`](../../docs/arquitectura/transaccion-procedimiento.md).
5. Skills aplicables:
   - [`.agents/skills/procedimientos-internos-condiciones`](../../.agents/skills/procedimientos-internos-condiciones)
   - [`.agents/skills/procedimientos-externos-condiciones`](../../.agents/skills/procedimientos-externos-condiciones)
   - [`.agents/skills/consistencia-tablas`](../../.agents/skills/consistencia-tablas)

---

## Patrón Canónico de Implementación

### 1. Procedimiento Interno (`usp_<nombre>_interno.sql`)
```sql
CREATE OR ALTER PROCEDURE dbo.usp_<nombre>_interno
    @Parametro1 INT,
    @Parametro2 NVARCHAR(100),
    @IdGenerado INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- Realiza la mutación o consulta atómica en la tabla base
    INSERT INTO dbo.MiTabla (Columna1, Columna2)
    VALUES (@Parametro1, @Parametro2);

    SET @IdGenerado = SCOPE_IDENTITY();
END;
```

### 2. Procedimiento Público / Fachada (`usp_<nombre>.sql`)
```sql
CREATE OR ALTER PROCEDURE dbo.usp_<nombre>
    @Parametro1 INT,
    @Parametro2 NVARCHAR(100),
    @CodigoMensaje NVARCHAR(50) OUTPUT,
    @Mensaje NVARCHAR(500) OUTPUT,
    @IdGenerado INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validaciones de entrada previas
    IF (@Parametro1 IS NULL OR @Parametro1 <= 0)
    BEGIN
        SELECT @CodigoMensaje = 'ERROR_PARAMETRO_INVALIDO',
               @Mensaje = 'El parámetro especificado no es válido.';
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Invocación al interno
        EXEC dbo.usp_<nombre>_interno
            @Parametro1 = @Parametro1,
            @Parametro2 = @Parametro2,
            @IdGenerado = @IdGenerado OUTPUT;

        SELECT @CodigoMensaje = 'EXITO_OPERACION',
               @Mensaje = 'Operación completada exitosamente.';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF (XACT_STATE() <> 0)
            ROLLBACK TRANSACTION;

        SELECT @CodigoMensaje = 'ERROR_TRANSACCION',
               @Mensaje = ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
```

---

## Pasos de Despliegue y Permisos
1. Ubicar el archivo en la carpeta correcta:
   - Tablas: `schema/tables/`
   - Vistas: `schema/views/`
   - SPs: `schema/stored-procedures/`
2. Si es un nuevo archivo, registrar su invocación en [`deploy_schema.ps1`](../../deploy_schema.ps1) en el orden de dependencias correcto.
3. Otorgar permisos al rol de la aplicación en [`schema/security/rol_asistencias_runtime.sql`](../../schema/security/rol_asistencias_runtime.sql):
   - `GRANT EXECUTE ON dbo.usp_<nombre> TO rol_asistencias_runtime;`

---

## Salida Producida
- Código T-SQL en `schema/`.
- Actualización de `deploy_schema.ps1` y permisos de seguridad.
- Handoff hacia: `@05-db-auditor`.