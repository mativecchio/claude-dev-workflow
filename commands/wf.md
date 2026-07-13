---
description: "Orquestador del workflow de desarrollo. Detecta etapa actual y enruta al comando correcto. Soporta: /wf, /wf reset, /wf <etapa>, /wf <descripción libre>"
allowed-tools: Read, Glob, Bash, TodoWrite, TodoRead
---

Sos el orquestador del sistema de desarrollo. Tu rol es detectar en qué etapa está el usuario y enrutarlo al comando correcto.

## Paso 1 — Argumentos especiales

Revisar `$ARGUMENTS`:
- Vacío o "resume" → ir a Paso 2 (verificar estado activo)
- "reset" → borrar `.claude/workflow/state.json` y confirmar al usuario
- Nombre de etapa exacto ("refine", "analyze", "review-plan", "implement", "validate", "test", "retro", "mr-review", "mr-desc", "jira", "improve") → forzar esa etapa, ir a Paso 4
- Texto libre → ir a Paso 3 (detectar desde texto)

## Paso 0 — Verificar inicialización del proyecto

Intentar leer `.claude/workflow/config.json`.

Si no existe, mostrar antes de cualquier otra cosa:
```
⚙️  Este proyecto no tiene config de workflow.
Corré /wf-init para detectar el stack y generar el config automáticamente.
(O continuá sin config — el workflow funciona igual, con menos contexto)
```

Preguntar: "¿Corremos `/wf-init` primero?"

## Paso 2 — Dashboard de tickets

Leer `.claude/workflow/state.json` → campo `activeTicket`.
Escanear todos los archivos `.claude/workflow/*/state.json` para listar tickets.

Mostrar dashboard:
```
📋 Tickets:
  BC-XXXX  [stage]   ✅ [completadas]   🎯 ← activo
  BC-YYYY  [stage]   ✅ [completadas]
```

Si `$ARGUMENTS` contiene un ticket ID (ej. "BC-1522"):
1. Cambiar activeTicket: guardar `{ "activeTicket": "BC-1522" }` en `.claude/workflow/state.json`
2. Confirmar: "🎯 Activo ahora: BC-1522"
3. Leer `{workflowDir}/state.json` y mostrar etapa actual

**Ticket retroactivo (código ya implementado, sin plan.md):** si al activar un ticket nuevo no existe `{workflowDir}/plan.md` pero el branch actual ya tiene commits con cambios de código (no solo el branch vacío recién creado), es un ticket armado *después* de la implementación — no fuerces `refine`/`analyze`/`review-plan`. En su lugar:
- Preguntar: "No hay plan.md y ya hay código implementado en este branch — ¿salteamos refine/analyze e implementamos/validamos directo?"
- Si confirma, guardar el `stage` inicial como `"implement"` con `"completed": ["implement"]` y agregar un campo `"notes"` en `{workflowDir}/state.json` resumiendo en 2-3 líneas qué se hizo y por qué no hay plan formal (esto reemplaza a refinement-summary.md/plan.md como contexto mínimo para las etapas siguientes).
- Comandos que dependen de `plan.md`/`refinement-summary.md` (`wf-validate`, `wf-mr-desc`, `wf-mr-review`) deben caer a leer ese campo `"notes"` de `{workflowDir}/state.json` cuando esos archivos no existan, en vez de bloquear o asumir que faltan por error.

Verificar branch actual con `git branch --show-current`. Si el branch NO contiene el activeTicket ni es `develop`:
```
⚠️  Branch actual: [branch] — no parece ser el branch de [ticket]
```
No bloquear — solo informar.

Preguntar: "¿Continuar desde aquí o resetear con `/wf reset`?"

Si no existe ningún `state.json`, ir a Paso 3.

## Paso 3 — Detectar etapa desde `$ARGUMENTS` o contexto

Buscar señales en el texto:

| Señales | Etapa |
|---|---|
| "ticket", "feature", "nueva tarea", "empezar", "vamos a" | `refine` |
| "analizar", "cómo implementar", "explorar", "hacer un plan", "necesito un plan" | `analyze` |
| "revisar plan", "verificar plan", "el plan está listo" | `review-plan` |
| "implementar", "codear", "hacer los cambios", "empezar a codear" | `implement` |
| "no funciona", "hay un error", "bug", "falla", "devuelve 400", "devuelve 404", "devuelve 500", "está roto" | `implement` (modo debug) |
| "escribir tests", "faltan tests", "agregar tests", "testear" | `test` |
| "revisar MR", "revisar PR", "code review", "merge request" | `mr-review` |
| "descripción del MR", "descripción del PR", "escribir la descripción" | `mr-desc` |
| "retrospectiva", "aprendizajes", "mejorar el workflow" | `retro` |
| "ticket de jira", "crear ticket", "escribir el ticket" | `jira` |

Si el texto es ambiguo, presentar opciones numeradas y esperar respuesta.

## Paso 4 — Mostrar routing

```
📍 Etapa detectada: [nombre]
📋 Señales: [qué indicó la etapa]
🛠️  Comando: /wf-[comando]
```

Luego leer el archivo `~/.claude/commands/wf-[comando].md` y ejecutar sus instrucciones directamente.

## Paso 5 — Actualizar estado

Al iniciar una etapa para un ticket:

1. Actualizar `.claude/workflow/state.json` (solo el activo):
```json
{ "activeTicket": "BC-XXXX" }
```

2. Actualizar `.claude/workflow/{ticketId}/state.json` (estado del ticket):
```json
{
  "stage": "[etapa actual]",
  "completed": ["[etapas ya completadas]"],
  "started_at": "[timestamp ISO]"
}
```

## Paso 6 — Sugerencias post-etapa

Al finalizar cada etapa, sugerir la siguiente:
- Después de `refine` → `/wf-analyze`
- Después de `analyze` → `/wf-review-plan`
- Después de `review-plan` → `/wf-implement`
- Después de `implement` → `/wf-validate` (opcional) y `/wf-test`
- Después de `validate` → `/wf-test`
- Después de `test` → `/wf-mr-desc` y `/wf-mr-review`
- En cualquier momento → recordar que `/wf-improve <observación>` registra algo que salió diferente, sin interrumpir el trabajo
- Después de cualquier etapa → ofrecer guardar entry en `~/.claude/workflow/flow-history.json`
