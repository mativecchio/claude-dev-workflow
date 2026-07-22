---
description: "Validation gate post-implementación. El usuario elige qué validadores activar. Corre en contexto aislado. Loop hasta 3 iteraciones antes de escalar."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite, TodoRead
---

Tu rol es correr validaciones automáticas sobre el diff de la implementación. El usuario elige qué validadores activar.

## Paso 0 — Identificar ticket activo

Leer `.claude/workflow/state.json` → campo `activeTicket`.
Si no existe o falta → preguntar: "¿Cuál es el número de ticket? (ej. BC-1234)"
Guardar: `{ "activeTicket": "BC-XXXX" }` en `.claude/workflow/state.json`.

`{ticketId}` = `activeTicket`
`{workflowDir}` = `.claude/workflow/{ticketId}`

## Paso 1 — Selección de validadores

Preguntar al usuario qué validadores activar:

```
¿Qué querés validar? (elegí uno o más)

1. 🏛️  Arquitectura — consistencia con patrones del proyecto
2. 🧪 Tests — cobertura de casos críticos
3. ⚡ Performance — re-renders innecesarios, queries N+1, operaciones costosas
4. 🔒 Seguridad — inputs no sanitizados, auth, datos expuestos
5. ♿ Accesibilidad — a11y básica (solo para cambios de UI)
6. ✅ Todos
```

Esperar respuesta antes de continuar.

## Paso 2 — Obtener el diff

Diffear contra el punto real donde el branch divergió de su base (`develop`/`main`/`master`), no contra `HEAD~1` (solo captura el último commit) ni contra la base directo (`develop..HEAD`), que se rompe si la base avanzó después de crear el branch (ej. alguien corrió `git pull --ff-only` sobre `develop` en el medio — el diff naive termina mostrando cambios de terceros como si fueran del feature).

```bash
BASE=develop  # o main/master, según el proyecto
MB=$(git merge-base HEAD "$BASE")
git diff "$MB"..HEAD --stat
git diff "$MB"..HEAD
```

Si no hay commits sobre la base (todo el cambio está en working tree sin commitear), usar:
```bash
git diff --stat
git diff
```

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

### ✅ OK (no tocar)
[qué está bien]

### Veredicto
[APROBADO / REQUIERE CAMBIOS]
```

---

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

Pasar a `/wf-implement` **solo con la lista ya decidida** (los items marcados "a"), para que ese comando salte su checkpoint de inicio (ver `wf-implement` Paso 2) — la decisión de qué implementar ya se tomó acá, no hace falta repreguntar "¿Arrancamos?".

Llevar cuenta de iteraciones. Si se llega a 3 sin aprobar, escalar:
**"⚠️ Se alcanzaron 3 iteraciones sin aprobar. Revisión manual requerida antes de continuar."**
