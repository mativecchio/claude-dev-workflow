---
description: "Revisión completa de MR/PR. Corre en contexto aislado via Agent tool. Soporta git local como fuente del diff. Output estructurado: críticos, importantes, sugerencias."
allowed-tools: Read, Bash, Glob, Grep, Agent, TodoWrite
---

Tu rol es preparar el contexto y lanzar una revisión completa del MR en un agente con contexto limpio.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage mr-review
```

Si `context` falla, preguntar el ticket y escribir `.claude/workflow/state.json` antes de reintentar.

## Paso 1 — Obtener el diff

```bash
~/.claude/scripts/wf-diff.sh --log
~/.claude/scripts/wf-diff.sh --stat
~/.claude/scripts/wf-diff.sh
```

Si `$ARGUMENTS` trae un branch específico, agregar `--branch [rama]` a cada llamada.

El script resuelve el merge-base contra la rama base del proyecto. Esto importa: `[base]..HEAD` se rompe si la base avanzó por un pull o fast-forward después de crear el feature branch, y termina mostrando cambios de terceros como si fueran del MR.

Si el diff es muy grande (>500 líneas), mostrar el `--stat` al usuario y preguntar si quiere continuar o acotar el scope. Para dimensionarlo bien:
```bash
~/.claude/scripts/wf-diff.sh --weight
```
`weight_prod` es lo que importa — `weight_tests` va aparte, porque un MR de 300 líneas donde 220 son tests no es un MR grande, es uno bien cubierto.

## Paso 2 — Recopilar contexto

Leer:
- `{workflowDir}/plan.md` → contexto de lo que se implementó
- `{workflowDir}/refinement-summary.md` → criterios de aceptación
- `CLAUDE.md` o `README.md` → stack y convenciones
- `.claude/workflow/config.json` → stack del proyecto

## Paso 2.5 — Delegar el review genérico

Antes de lanzar el Agent propio, correr el reviewer del harness:

```
/code-review high
```

Cubre bugs de correctitud, simplificación, reuso y eficiencia sobre el diff — y lo hace mejor que una instrucción nuestra, porque se mantiene solo. Para un MR con foco en seguridad, `/security-review` en vez de o además.

**Qué queda para el Agent del Paso 3**, y es lo que ningún reviewer genérico puede hacer:
- Contraste contra el `plan.md` y los criterios de aceptación del ticket: ¿el MR hace lo que se acordó, y solo eso?
- Contratos con `related_projects`: verificar contra el código fuente real del otro repo, no asumirlo.
- Convenciones específicas del proyecto (feature hermana, helpers existentes).
- Deuda técnica registrada y desvíos del plan.

Si `/code-review` ya reportó un hallazgo, **no repetirlo** en el output del Paso 3. Referenciarlo y seguir.

Si el comando no está disponible en este entorno, seguir al Paso 3 con el alcance completo (la sección "Revisión línea por línea" del prompt) y anotarlo en el output.

## Paso 3 — Lanzar el Agent de revisión

Usar el **Agent tool** con el siguiente prompt:

---
**PROMPT DEL AGENT:**

Sos un senior engineer haciendo code review de un MR. Tu objetivo es encontrar problemas reales — no dar feedback genérico.

**Contexto del MR:**
[contenido de refinement-summary.md y plan.md]

**Stack:** [stack del config]
**Convenciones del proyecto:** [resumen de CLAUDE.md]

**Diff completo:**
[diff]

## Tu proceso de revisión

### 1. Contexto primero (antes de revisar línea por línea)
- ¿Qué resuelve este MR?
- ¿La solución elegida tiene sentido arquitectónicamente?
- ¿Hay efectos secundarios no contemplados?

### 2. Revisión línea por línea
**Si el Paso 2.5 corrió `/code-review`, saltear los bullets 1-3:** ya los cubrió, y repetirlos produce output duplicado que el autor del MR tiene que descartar a mano.

Evaluar en orden de importancia:
- Bugs y lógica incorrecta *(cubierto por `/code-review`)*
- Seguridad — inputs, auth, datos expuestos *(cubierto por `/code-review`)*
- Performance — N+1, re-renders, operaciones costosas *(cubierto por `/code-review`)*
- **Tests: gaps de cobertura contra los casos borde del refinement** — no genérico, sino contra los casos que el ticket identificó
- **Contratos modificados y sus consumidores**, incluidos los de otros repos

### 3. Efectos secundarios
- ¿Hay contratos (API, tipos, eventos) que se modifican y tienen consumidores?
- ¿Hay migraciones que pueden afectar datos existentes?
- ¿El diff toca un estado/storage/contrato compartido con algún `related_project` (config.json)? Si sí: ¿el plan/diff documenta qué se verificó contra el código fuente real de ese proyecto (grep/read de su `path` local), o es una asunción sin confirmar? Un diff correcto en la lógica de *este* repo puede seguir estando roto si el otro lado del contrato (sistema externo) hace algo distinto a lo asumido — no se puede aprobar ese punto solo mirando este diff.

## Output requerido

```markdown
## Code Review — [nombre del MR]

### 📋 Resumen ejecutivo
[1-2 líneas: qué hace el MR y veredicto general]

### 🔴 Críticos (bloqueantes)
- **[archivo:línea]** — [problema] → [corrección requerida]

### 🟠 Importantes
- **[archivo:línea]** — [problema] → [sugerencia]

### 💡 Sugerencias
- **[archivo:línea]** — [mejora opcional]

### 🔗 Efectos secundarios
- [contratos modificados y consumidores afectados]
- [si aplica: riesgo no verificable contra un related_project — qué se asumió sin confirmar contra su código fuente real]

### ❓ Preguntas al autor
- [pregunta 1]

### ✅ Lista de acciones priorizada
1. [acción crítica 1]
2. [acción importante 1]
```

---

## Paso 4 — Mostrar el review

Leer el output del agente y presentarlo al usuario.

Si hay 🔴 Críticos, preguntar: **"¿Querés que aborde alguno de estos items ahora con `/wf-implement`?"**
