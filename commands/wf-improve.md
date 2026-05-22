---
description: "Mejora continua del workflow. Con argumento: registra una observación en el log de la sesión. Sin argumento: revisión completa — categoriza todo lo acumulado y propone fixes de código y mejoras a los comandos."
allowed-tools: Read, Write, Edit, Bash, Glob, TodoRead
---

Comando de mejora continua. Operás en dos modos según si hay argumento o no.

---

## Modo flag — `/wf-improve <observación>`

Cuando `$ARGUMENTS` tiene texto, registrar la observación sin interrumpir el trabajo.

### Paso 1 — Detectar contexto actual

Leer `.claude/workflow/state.json` para saber en qué etapa se está.

### Paso 2 — Clasificar la observación

Determinar a qué categoría pertenece el problema reportado:

| Categoría | Descripción |
|---|---|
| `workflow` | El comando se comportó diferente a lo esperado — habría que mejorar el comando |
| `code` | Algo quedó mal implementado en el código |
| `plan` | El análisis o plan fue incorrecto o incompleto |
| `communication` | Claude malinterpretó la intención o no preguntó lo necesario |
| `other` | Otro tipo de observación |

### Paso 3 — Agregar al log

Crear o agregar a `.claude/workflow/improvement-log.md`:

```markdown
---
**[timestamp] — Etapa: [etapa actual]**
**Categoría:** [categoría]
**Observación:** [texto del $ARGUMENTS]
**Contexto:** [qué se estaba haciendo cuando ocurrió]

---
```

Confirmar al usuario:
```
📝 Registrado en improvement-log.md
Categoría: [categoría]
Podés continuar — se revisa todo al final con /wf-improve
```

---

## Modo review — `/wf-improve` (sin argumentos)

Revisión completa de todo lo acumulado durante la sesión.

### Paso 1 — Recopilar todo

Leer:
- `.claude/workflow/improvement-log.md` → observaciones acumuladas
- `.claude/workflow/state.json` → etapas recorridas
- `.claude/workflow/plan.md` → para entender qué se implementó
- `~/.claude/workflow/flow-history.json` → si hay 3+ entries, cruzar patrones

### Paso 2 — Mostrar el análisis

```
## Revisión de mejora continua

### Observaciones acumuladas
[lista de lo que se registró durante la sesión]

### Patrones detectados
[si hay 2+ observaciones del mismo tipo o componente]

### Categorización
🔧 Fixes de código: [N items]
⚙️  Mejoras al workflow: [N items]
📋 Para el plan / análisis: [N items]
```

### Paso 3 — Proponer acciones

Para cada ítem, proponer una acción concreta:

**Fixes de código** — mostrar qué archivo/función hay que corregir y el cambio exacto.

**Mejoras al workflow** — mostrar el comando afectado (`wf-*.md`) y el cambio de instrucción propuesto. Ejemplo:
```
Comando: wf-analyze
Problema: no pregunta sobre permisos del endpoint antes de generar el plan
Cambio propuesto: agregar en Paso 2 "Si el plan incluye endpoints nuevos, verificar permisos requeridos"
```

**Plan / análisis** — notar para el historial; si el ticket sigue abierto, sugerir correr `/wf-analyze` de nuevo.

### Paso 4 — Aplicar con aprobación

Para cada propuesta, pedir confirmación antes de aplicar:
**"¿Aplico este cambio?"**

- Fixes de código → aplicar con `Edit` tool
- Mejoras al workflow → editar el archivo en `~/.claude/commands/wf-*.md` con `Edit` tool

Recordar al usuario que los cambios al workflow también deben reflejarse en el repo fuente (`~/claude-workflow/commands/`) para que persistan en el próximo `install.sh`.

### Paso 5 — Limpiar el log

Cuando se completó la revisión, preguntar si limpiar el `improvement-log.md` para la próxima sesión.

Si acepta → reemplazar con:
```markdown
# Improvement Log

_Registrar observaciones durante la sesión con `/wf-improve <observación>`_
```

### Paso 6 — Ofrecer guardar en flow-history

Preguntar si quiere agregar un entry al historial global con las mejoras aplicadas en esta sesión.
