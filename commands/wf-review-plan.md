---
description: "Verifica el plan de implementación contra el codebase real. Corre en contexto aislado. BLOQUEA hasta aprobación explícita del usuario antes de pasar a implementación."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Tu rol es verificar que el plan sea correcto y completo antes de tocar código. Este es el checkpoint más importante del sistema.

## Paso 0 — Contexto del ticket

```bash
~/.claude/scripts/wf-lib.sh context
~/.claude/scripts/wf-lib.sh enter-stage review-plan
~/.claude/scripts/wf-lib.sh set-state approved false
```

`approved` arranca siempre en falso: la aprobación de esta etapa es explícita y se escribe recién en el Paso 4.

**Este campo no es decorativo.** El hook `wf-gate.sh` lo lee en cada `Edit`/`Write`: mientras el ticket esté en `review-plan` sin aprobar, el gate registra el intento (modo `observe`) o lo bloquea (modo `enforce`). El checkpoint de este comando dejó de ser solo una instrucción.

Si `context` falla, preguntar el ticket y escribir `.claude/workflow/state.json` antes de reintentar.

## Paso 1 — Verificar que existe el plan

Leer `{workflowDir}/plan.md`. Si no existe, decirle al usuario que primero corra `/wf-analyze`.

También leer:
- `{workflowDir}/refinement-summary.md` → criterios de aceptación y DoD
- `.claude/workflow/config.json` → stack y contexto del proyecto

## Paso 2 — Lanzar el Agent de verificación

Usar el **Agent tool** con el siguiente prompt:

---
**PROMPT DEL AGENT:**

Sos un senior engineer revisando un plan de implementación antes de que empiece el desarrollo. Tu trabajo es encontrar problemas, no validar lo que ya está bien.

**Plan a revisar:**
[contenido completo de plan.md]

**Criterios de aceptación originales:**
[contenido de refinement-summary.md]

**Stack:** [stack del config]

## Qué verificar

### Consistencia con el codebase
- ¿Los archivos mencionados existen?
- ¿Los patrones propuestos son consistentes con cómo el proyecto lo hace hoy?
- ¿Hay helpers o utilities existentes que el plan ignora y debería usar?

### Completitud
- ¿Todos los criterios de aceptación están cubiertos por algún cambio del plan?
- ¿Falta algún archivo que claramente va a necesitar cambios?
- ¿La infraestructura está completa (env vars, migraciones, etc.)?

### Retrocompatibilidad
- ¿Los contratos que se modifican tienen consumidores que se rompen?
- ¿El orden de implementación es correcto o genera dependencias circulares?

### Contratos con proyectos relacionados
- Si el plan toca un estado/storage/contrato compartido con algún `related_project` (config.json), ¿el plan documenta qué se verificó contra el código fuente real de ese proyecto (archivo:línea), o asume el comportamiento sin haberlo revisado?
- Si el `related_project` tiene `path` local y el plan lo trata como "no se puede confirmar, es externo" sin haber grepeado ese path, marcarlo como hallazgo — el path existe y es verificable, no es una caja negra real.
- ¿El plan cruzó `~/.claude/workflow/flow-history.json` buscando bugs previos en el mismo punto de integración? **Este chequeo solo aplica si el archivo tiene `entries` con contenido.** Si el array está vacío —su estado por defecto hasta que la Fase 4 lo pueble— no es un hallazgo: no hay historial que ignorar. Marcar como hallazgo únicamente cuando existe una entry con el mismo `related_project` en `key_findings`/`anomalies` y el plan no la menciona.

## Clasificar hallazgos

**🔴 Bloqueante** — el plan va a fallar o romper algo si se ejecuta así  
**🟠 Importante** — puede generar problemas o retrabajo, hay que ajustar  
**💡 Sugerencia** — mejora opcional, no bloquea  

## Output requerido

Escribir en `{workflowDir}/review-findings.md`:

```markdown
# Review del Plan — [nombre de la tarea]

## 🔴 Bloqueantes
[si ninguno: "Ninguno"]

## 🟠 Importantes
[si ninguno: "Ninguno"]

## 💡 Sugerencias
[si ninguno: "Ninguno"]

## Veredicto
[APROBADO / APROBADO CON AJUSTES / BLOQUEADO]

## Ajustes requeridos al plan
[lista de cambios a hacer antes de implementar, o "Ninguno"]
```

Cuando termines, decir: "Review escrito en {workflowDir}/review-findings.md"

---

## Paso 3 — CHECKPOINT DURO

Leer `{workflowDir}/review-findings.md` y mostrar el resultado al usuario.

**Este es el checkpoint más importante del sistema. NUNCA pasar a implementación sin respuesta explícita.**

Mostrar el veredicto y preguntar:
**"¿Procedemos a implementar? Respondé 'sí' para continuar o indicá qué hay que ajustar."**

- Si hay 🔴 Bloqueantes → no ofrecer implementar hasta que se resuelvan
- Si hay 🟠 Importantes → mostrarlos y preguntar si ajustar el plan primero
- Si el veredicto es APROBADO → esperar "sí" explícito del usuario

## Paso 3.5 — Registrar los findings

Uno por cada 🔴 y 🟠 del review (los 💡 no):

```bash
~/.claude/scripts/wf-event.sh finding \
  --category [slug] --severity [high|medium] \
  --stage_origin [refine|analyze] --stage_detected review-plan \
  --detected_by [gate|user] --summary "[una línea]"
```

Los dos campos que importan, y los únicos que no se pueden reconstruir después:

- **`stage_origin`** — en qué etapa se *introdujo* el defecto, no dónde apareció. Un requisito ambiguo que el plan arrastra se originó en `refine`, aunque lo detectes acá. Es lo que responde "¿qué etapa origina más defectos?" y dónde conviene poner el próximo gate.
- **`detected_by`** — `gate` si lo encontró el review, `user` si lo encontraste vos leyendo el output. Si la proporción de `user` sube con el tiempo, los gates se están degradando. Marcarlo `gate` cuando lo dijiste vos infla la métrica y hace inútil la comparación.

`--category` es un slug corto y **reutilizable** entre tickets (`missing-guard`, `wrong-layer`, `contract-drift`). Una categoría distinta por finding no agrupa con nada: la consulta que importa es cuáles se repiten en 3+ tickets.

Si el comando falla, seguir con el checkpoint igual. Perder un evento es aceptable; frenar el flujo por telemetría, no.

## Paso 4 — Siguiente paso (solo con aprobación)

Solo si el usuario confirma explícitamente:

1. Registrar la aprobación:
   ```bash
   ~/.claude/scripts/wf-lib.sh set-state approved true
   ```
   Esto es lo que destraba el gate: hasta acá, cualquier `Edit`/`Write` sobre código quedaba registrado como intento de saltear el checkpoint.
2. Decir: "Siguiente: `/wf-implement`"

Si el usuario no confirma, `approved` queda en `false`. No escribirlo "por si acaso" ni anticipar la aprobación.
