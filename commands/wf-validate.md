---
description: "Validation gate post-implementación. El usuario elige qué validadores activar. Corre en contexto aislado. Loop hasta 3 iteraciones antes de escalar."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite, TodoRead
---

Tu rol es correr validaciones automáticas sobre el diff de la implementación. El usuario elige qué validadores activar.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage validate
```

Si `context` falla, preguntar el ticket y escribir `.claude/workflow/state.json` antes de reintentar.

## Paso 1 — Selección de validadores

Preguntar al usuario qué validadores activar:

```
¿Qué querés validar? (elegí uno o más)

1. 🏛️  Arquitectura — consistencia con patrones del proyecto
2. 🧪 Tests — cobertura de casos críticos
3. ⚡ Performance — re-renders innecesarios, queries N+1, operaciones costosas
4. 🔒 Seguridad — inputs no sanitizados, auth, datos expuestos
5. ♿ Accesibilidad — a11y básica (solo para cambios de UI)
6. 📱 Runtime — levantar la app y verificar el flujo real
7. ✅ Todos
```

Esperar respuesta antes de continuar.

**Sobre el 6 (Runtime):** ofrecerlo proactivamente cuando el diff toca UI, navegación o estado compartido — son los casos donde leer el diff no alcanza. Requiere que la app esté corriendo y que haya MCP disponible (`metro` para React Native, `claude-in-chrome` para web). Si no hay ninguno, decirlo y seguir sin ese validador en vez de fingir que se validó.

## Paso 2 — Checks determinísticos (antes que cualquier agente)

```bash
~/.claude/scripts/wf-checks.sh
```

Corre lint, types y tests del `config.json`. **Si alguno falla, parar acá:** mostrar qué falló y volver a `/wf-implement`. No lanzar el Agent.

El motivo es económico y de precisión: un linter responde "¿hay console.log?" de forma exacta y gratis, mientras que un agente opina sobre lo mismo con posibilidad de falso positivo. El agente queda para lo que solo él puede hacer — arquitectura, contratos externos, seguridad.

Exit 2 significa que el proyecto no tiene `checks` configurados: informarlo una vez, sugerir agregarlos con `/wf-init`, y continuar.

## Paso 2.5 — Obtener el diff

```bash
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

Resuelve solo el merge-base contra la rama base del proyecto, y el caso de trabajo sin commitear. No hace falta razonar sobre el rango.

## Paso 3 — Lanzar Agent de validación

Usar el **Agent tool** con el siguiente prompt (adaptado a los validadores elegidos):

---
**PROMPT DEL AGENT:**

Sos un senior engineer haciendo una revisión de calidad sobre código recién implementado. Iteración [N] de máximo 3.

**Diff a revisar:**
[diff completo]

**Plan original:**
[contenido de {workflowDir}/plan.md]

**Stack:** [stack del config]

**Validadores activos:** [lista de validadores elegidos]

## Instrucciones por validador

**🏛️ Arquitectura:**
- ¿El código sigue los patrones del proyecto (sister feature)?
- ¿Se usaron helpers existentes en lugar de reimplementar?
- ¿La separación de responsabilidades es correcta?

**🧪 Tests:**
- ¿Los happy paths están cubiertos?
- ¿Los casos de error críticos tienen test?
- ¿Los tests son sociables (no mockean componentes hijos, solo servicios externos)?

**⚡ Performance:**
- ¿Hay re-renders innecesarios en componentes?
- ¿Hay queries N+1 o llamadas a APIs en loops?
- ¿Las operaciones costosas están memoizadas donde corresponde?

**🔒 Seguridad:**
- ¿Los inputs del usuario están sanitizados?
- ¿Hay datos sensibles expuestos en logs o responses?
- ¿Los endpoints tienen la auth correcta?

**🔗 Integración externa (correr siempre, no depende de los validadores elegidos):**
- ¿El diff toca un estado/storage/contrato que también lee o escribe un `related_project` (config.json)? Si sí, y ese proyecto tiene `path` local, ¿se verificó el comportamiento real grepeando/leyendo ese path (merge vs replace, tipos, formato) en vez de asumirlo?
- Esto NO se puede aprobar solo por diff — si hay una integración externa involucrada y no se verificó contra el código fuente real, marcarlo explícitamente como riesgo no verificable, no como aprobado.

**♿ Accesibilidad:**
- ¿Las imágenes tienen alt text?
- ¿Los elementos interactivos tienen labels accesibles?
- ¿El contraste es adecuado?

## Output requerido

```markdown
## Validación — Iteración [N]

### ❌ Falló
#### [Validador]
- **Archivo:** [path]
- **Problema:** [descripción]
- **Corrección:** [qué hacer]
- **Severidad:** [alta/media]

### ⚠️ Warnings
[warnings menores]

### 🔗 Riesgo no verificable por diff
[si el diff toca integración con un related_project y no se pudo verificar contra su código fuente real: qué queda sin confirmar y por qué. Si no aplica: "Ninguno" / "N/A — sin integración externa en este diff"]

### ✅ OK (no tocar)
[qué está bien]

### Veredicto
[APROBADO / APROBADO CON RIESGO NO VERIFICABLE / REQUIERE CAMBIOS]
```

Un veredicto de "APROBADO" nunca implica que el comportamiento contra un sistema externo esté confirmado — si hay una sección "🔗 Riesgo no verificable por diff" con contenido, usar "APROBADO CON RIESGO NO VERIFICABLE", no "APROBADO" a secas.

---

## Paso 3.5 — Validación de runtime (solo si se eligió el validador 6)

**Corre en el contexto principal, no dentro del Agent.** Los subagentes no tienen garantizado el acceso a las tools MCP, y esta validación depende de ellas. Ejecutarla acá, después de que vuelva el Agent, y sumar los hallazgos al output.

El resto de los validadores razonan sobre el diff. Este observa la app funcionando, que es la única forma de detectar cierta clase de defecto: un orden de ejecución entre efectos, un estado que queda inconsistente al volver a una pantalla, una request que se dispara dos veces. `wf-analyze` intenta cubrir eso preguntándole al usuario el orden esperado — acá se mira directamente.

**React Native (MCP `metro`):**
```
1. mcp__metro__list_devices        → confirmar que hay un target conectado
2. mcp__metro__get_bundle_errors   → si hay errores de bundle, parar y reportar
3. mcp__metro__list_routes / get_current_route → ubicar la pantalla afectada por el diff
4. mcp__metro__open_deeplink o tap_element → navegar hasta ella
5. mcp__metro__take_screenshot     → evidencia visual del estado final
6. Según el tipo de cambio:
   - estado:     mcp__metro__get_redux_state, get_redux_actions
   - red:        mcp__metro__get_network_requests, get_response_body
   - errores:    mcp__metro__get_errors, get_console_logs
   - re-renders: mcp__metro__get_react_renders
   - a11y:       mcp__metro__audit_accessibility
```

**Web (MCP `claude-in-chrome`):** navegar a la ruta afectada, `read_console_messages` y `read_network_requests`, screenshot del estado final.

**Qué buscar**, en orden:
1. ¿El flujo que cambió se completa sin error?
2. ¿El estado queda consistente al salir y volver a la pantalla?
3. ¿Hay requests duplicadas, o que se disparan cuando no deberían?
4. ¿Hay errores o warnings nuevos en consola respecto de antes del cambio?

**Reglas:**
- Si la app no está corriendo, pedirle al usuario que la levante. **No** intentar buildear desde acá.
- Si no se pudo verificar, decirlo explícitamente. Un "no se pudo levantar la app" es un resultado honesto; dar por validado lo que no se observó, no.
- No tocar elementos que disparen diálogos nativos o modales de confirmación: bloquean la sesión de automatización.

**Salida**, para sumar al output del Paso 3:
```markdown
### 📱 Runtime
- **Flujo verificado:** [qué se navegó, con qué datos]
- **Observado:** [estado, requests, errores — con evidencia concreta]
- **Screenshot:** [path]
- **No verificable:** [qué quedó sin poder observarse y por qué]
```

> **Hipótesis explícita** (`docs/plan-harness-migration.md` Fase 3): este validador no está fundamentado en datos. La apuesta es que las races y los defectos de estado se detectan mejor observando el runtime que razonando sobre el diff. Si a los 15-20 tickets no aparece esa diferencia, se saca.

## Paso 4 — Decisión post-validación

**Si APROBADO:**
Mostrar resultado y sugerir: "Siguiente: `/wf-test`"

**Si REQUIERE CAMBIOS:**
Mostrar el feedback estructurado completo, y para cada finding de "❌ Falló" (y opcionalmente cada "⚠️ Warning" si el usuario quiere revisarlos también) ofrecer un picker individual:
```
[N]. [archivo:línea] — [resumen del problema] (severidad: [alta/media])
    ¿Qué hacemos?
    a) Implementar el fix
    b) Ignorar (con motivo)
    c) Marcar como deuda técnica (registrar en plan.md, no implementar ahora)
```
Esperar la decisión de cada item (se puede responder todo junto, ej. "1a, 2c, 3b") antes de pasar a `/wf-implement`. No asumir "implementar todo" por default.

**Registrar cada finding y su decisión.** El picker ya produjo el dato; esto sólo lo asienta:

```bash
# uno por cada "❌ Falló"
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [analyze|implement] --stage_detected validate \
  --detected_by [gate|user] --summary "[una línea]"

# y la decisión que tomó el usuario para ese finding
~/.claude/scripts/wf-event.sh finding_decision \
  --finding_ref "[mismo slug o índice]" --decision [implement|ignore|tech-debt]
```

`stage_origin` es dónde se **introdujo** el defecto: un guard que faltó por un plan incompleto se originó en `analyze`, no en `implement`, aunque el síntoma aparezca en el código. Es la diferencia entre "el implementador se equivocó" y "el plan no lo pedía", que son problemas distintos con gates distintos.

`finding_decision` es lo que permite después distinguir un finding real de uno ruidoso: una categoría que se ignora sistemáticamente es un validador que está gritando de más, y eso se ve sólo si las decisiones quedan registradas.

Pasar a `/wf-implement` **solo con la lista ya decidida** (los items marcados "a"), para que ese comando salte su checkpoint de inicio (ver `wf-implement` Paso 2) — la decisión de qué implementar ya se tomó acá, no hace falta repreguntar "¿Arrancamos?".

Llevar cuenta de iteraciones. Si se llega a 3 sin aprobar, escalar:
**"⚠️ Se alcanzaron 3 iteraciones sin aprobar. Revisión manual requerida antes de continuar."**
