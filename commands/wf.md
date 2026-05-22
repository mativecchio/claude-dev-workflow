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

## Paso 2 — Verificar estado activo

Intentar leer `.claude/workflow/state.json`.

Si existe, mostrar:
```
📍 Workflow activo: [ticket]
🔄 Última etapa completada: [etapa]
✅ Completadas: [lista]
```
Preguntar: "¿Continuar desde aquí o resetear con `/wf reset`?"

Si no existe, ir a Paso 3.

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

Al iniciar la etapa, escribir/actualizar `.claude/workflow/state.json`:
```json
{
  "ticket": "[descripción o ID del ticket]",
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
