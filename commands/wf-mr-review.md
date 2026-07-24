---
description: "Revisión completa de MR/PR. Corre en contexto aislado via Agent tool. Soporta git local como fuente del diff. Output estructurado: críticos, importantes, sugerencias."
allowed-tools: Read, Bash, Glob, Grep, Agent, TodoWrite
---

Tu rol es preparar el contexto y lanzar una revisión completa del MR en un agente con contexto limpio.

## Paso 0 — Identificar ticket activo

Leer `.claude/workflow/state.json` → campo `activeTicket`.
Si no existe o falta → preguntar: "¿Cuál es el número de ticket? (ej. BC-1234)"

`{ticketId}` = `activeTicket`
`{workflowDir}` = `.claude/workflow/{ticketId}`

## Paso 1 — Obtener el diff

Usar siempre el punto real donde el branch divergió de su base, no la base directo — `[base]..HEAD` se rompe si la base (`develop`/`main`) avanzó por un pull/fast-forward después de crear el feature branch, mostrando cambios de terceros como si fueran del MR.

**Opción 1 — Branch actual vs base (develop/main/master):**
```bash
BASE=develop  # o main/master, según el proyecto
MB=$(git merge-base HEAD "$BASE")
git log --oneline "$MB"..HEAD | head -20
git diff "$MB"..HEAD --stat
git diff "$MB"..HEAD
```

**Opción 2 — Si `$ARGUMENTS` tiene un branch específico:**
```bash
MB=$(git merge-base [feature-branch] [base-branch])
git diff "$MB"..[feature-branch] --stat
git diff "$MB"..[feature-branch]
```

Si el diff es muy grande (>500 líneas), mostrar el `--stat` al usuario y preguntar si quiere continuar o acotar el scope.

## Paso 2 — Recopilar contexto

Leer:
- `{workflowDir}/plan.md` → contexto de lo que se implementó
- `{workflowDir}/refinement-summary.md` → criterios de aceptación
- `CLAUDE.md` o `README.md` → stack y convenciones
- `.claude/workflow/config.json` → stack del proyecto

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
Evaluar en orden de importancia:
- Bugs y lógica incorrecta
- Seguridad (inputs, auth, datos expuestos)
- Performance (N+1, re-renders, operaciones costosas)
- Tests (gaps de cobertura críticos)
- Contratos modificados y sus consumidores

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
