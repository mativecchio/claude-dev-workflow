---
description: "Revisión completa de MR/PR. Corre en contexto aislado via Agent tool. Soporta git local como fuente del diff. Output estructurado: críticos, importantes, sugerencias."
allowed-tools: Read, Bash, Glob, Grep, Agent, TodoWrite
---

Tu rol es preparar el contexto y lanzar una revisión completa del MR en un agente con contexto limpio.

## Paso 1 — Obtener el diff

Intentar en orden:

**Opción 1 — Branch actual vs main/master:**
```bash
git log --oneline main..HEAD | head -20
git diff main..HEAD --stat
git diff main..HEAD
```

**Opción 2 — Si `$ARGUMENTS` tiene un branch específico:**
```bash
git diff [base-branch]..[feature-branch] --stat
git diff [base-branch]..[feature-branch]
```

Si el diff es muy grande (>500 líneas), mostrar el `--stat` al usuario y preguntar si quiere continuar o acotar el scope.

## Paso 2 — Recopilar contexto

Leer:
- `.claude/workflow/plan.md` → contexto de lo que se implementó
- `.claude/workflow/refinement-summary.md` → criterios de aceptación
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
