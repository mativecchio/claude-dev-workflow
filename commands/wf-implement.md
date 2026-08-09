---
description: "Implementa los cambios siguiendo el plan aprobado. Incluye modo debug para bugs/errores. Checkpoint antes de cada grupo de archivos."
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite, TodoRead
---

Tu rol es implementar siguiendo el plan aprobado, respetando las convenciones del proyecto, con checkpoints antes de cada paso costoso.

## Detección de modo

### Modo Debug
Si en `$ARGUMENTS` o en el contexto aparecen señales como: "no funciona", "error", "bug", "falla", "devuelve 4xx/5xx", "está roto", "no renderiza":

1. **Primero: diagnóstico** — explorar el código y entender la causa raíz
2. **Mostrar el análisis** antes de tocar nada:
   ```
   🔍 Causa raíz detectada: [descripción]
   📋 Plan de fix:
   1. [paso 1]
   2. [paso 2]
   ```
3. **Checkpoint**: "¿Este análisis es correcto? ¿Procedo con el fix?"
4. Esperar confirmación antes de modificar archivos

### Modo Normal
Seguir el flujo completo abajo.

---

## Paso 0 — Identificar ticket activo y branch

Leer `.claude/workflow/state.json` → campo `activeTicket`.
Si no existe o falta → preguntar: "¿Cuál es el número de ticket activo? (ej. BC-1234)"
Guardar: `{ "activeTicket": "BC-XXXX" }` en `.claude/workflow/state.json`.

`{ticketId}` = `activeTicket`
`{workflowDir}` = `.claude/workflow/{ticketId}`

Leer `{workflowDir}/state.json`. Si falta `branch` → preguntar: "¿En qué branch estás trabajando?" y guardar en `{workflowDir}/state.json`.

**Registrar la entrada a la etapa:** escribir `"stage": "implement"` en `{workflowDir}/state.json` y appendear `"implement"` a `completed` si no estaba, preservando los demás campos (`branch`, `notes`, `iterations`, `subtasks`, `approved`).

## Paso 1 — Leer el contexto del plan

Leer:
- `{workflowDir}/plan.md` → qué cambiar y en qué orden
- `{workflowDir}/review-findings.md` → ajustes requeridos al plan
- `.claude/workflow/config.json` → DoD y stack

Si no existe `plan.md`, decirle al usuario que primero corra `/wf-analyze` y `/wf-review-plan`.

## Paso 2 — Checkpoint de inicio

Mostrar resumen del plan al usuario:
```
📋 Plan aprobado: [nombre de la tarea]
📁 Archivos a modificar: [cantidad]
📍 Orden de implementación:
  1. [módulo/grupo 1]
  2. [módulo/grupo 2]
```

**Saltear el checkpoint "¿Arrancamos?" (ir directo a Paso 3) cuando aplique cualquiera de estos dos casos** — ya hay una confirmación explícita del usuario, no hace falta pedir otra:
- El usuario invocó `/wf-implement` directamente (escribió el comando) — eso ya es la confirmación de arrancar.
- Se llega desde `wf-validate` con una lista de findings ya decidida item por item (ver picker de `wf-validate` Paso 4) — la decisión de qué implementar ya se tomó ahí.

**Preguntar "¿Arrancamos?" solo cuando se llega de forma indirecta** (enrutado desde `/wf` u otro comando) y todavía no hubo ninguna acción explícita del usuario pidiendo implementar. Esperar confirmación antes de tocar cualquier archivo en ese caso.

## Paso 3 — Implementar por grupos

Para cada grupo de archivos del plan:

**Antes de modificar:**
- Leer el archivo completo
- Entender el contexto y las convenciones locales (naming, imports, manejo de errores)

**Checkpoint antes de cada grupo (si tiene más de 1 archivo o es un módulo clave):**
```
⚡ Próximo paso: [descripción del grupo]
Archivos: [lista]
```
Preguntar: "¿Continúo?" — solo si el usuario configuró checkpoints detallados o si el cambio es de alto riesgo (contratos, auth, DB).

**Durante la implementación:**
- Respetar: naming, estructura de imports, estilo de error handling, i18n si aplica
- Si detectás un helper existente que el plan no contempló → usarlo y documentar el desvío
- Si hay un cambio necesario que el plan no contempló → informar antes de hacerlo

## Paso 3.5 — Heurística: test-primero para guards de validación

Si el grupo que estás por implementar agrega o modifica un **guard de validación** (código que chequea si un valor es válido/seguro antes de usarlo — ej. `isValidDate`, sanitización, parseo defensivo, chequeo de null/formato), evaluar los 3 criterios:

1. El valor cruza un límite de datos que no controlás (sessionStorage/localStorage escrito por otro repo, respuesta de API externa, input de usuario libre, query params).
2. Ya existe o estás agregando un helper de validación (`isValidDate`, `sanitize`, `parse`, etc.) — señal de que "input corrupto" es un modo de falla conocido, no hipotético.
3. El valor se usa en **más de un lugar** (grep del state/prop/variable da 2+ call sites/consumidores).

**Si se cumplen 2 de los 3:** antes de escribir el fix, grepear **todos** los call sites del valor (no solo el que motivó el cambio) y listarlos:
```
🔎 Call sites de [valor] sin guard: [archivo:línea, archivo:línea, ...]
```
Escribir un test que fuerce el input corrupto/inválido por **cada** call site de la lista (o confirmar explícitamente cuáles quedan fuera de alcance y por qué) antes de dar la implementación por terminada — no solo para el primer lugar donde se detectó el problema.

**Por qué:** un guard agregado en un solo lugar (ej. al hidratar desde sessionStorage) deja el mismo valor sin validar en otros consumidores (ej. validación de formulario, props a componentes hijos) — bug real detectado en BC-1529 vía `/wf-mr-review`, dos rondas después de la implementación, en vez de en esta etapa.

Si no se cumplen 2 de los 3 criterios (valor interno controlado, un solo call site), seguir el flujo normal sin este paso extra.

## Paso 4 — Registrar desvíos

Si durante la implementación hay algo que se hace diferente al plan:
```
⚠️  Desvío del plan: [descripción]
Razón: [por qué]
Impacto: [qué cambia]
```

## Paso 5 — Registrar deuda técnica

Si encontrás deuda técnica durante la implementación, agregar al final de `{workflowDir}/plan.md`:
```markdown
## Deuda técnica detectada (no implementada)
- [descripción] — detectada en [archivo]
```

## Paso 6 — Resumen al terminar

Al completar todos los grupos:
```
✅ Implementación completada
📁 Archivos modificados: [lista]
⚠️  Desvíos del plan: [lista o "ninguno"]
🔧 Deuda técnica registrada: [lista o "ninguna"]
```

Sugerir: "Siguiente: `/wf-validate` (opcional, recomendado) o `/wf-test`"
