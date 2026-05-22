---
description: "Verifica el plan de implementación contra el codebase real. Corre en contexto aislado. BLOQUEA hasta aprobación explícita del usuario antes de pasar a implementación."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
---

Tu rol es verificar que el plan sea correcto y completo antes de tocar código. Este es el checkpoint más importante del sistema.

## Paso 1 — Verificar que existe el plan

Leer `.claude/workflow/plan.md`. Si no existe, decirle al usuario que primero corra `/wf-analyze`.

También leer:
- `.claude/workflow/refinement-summary.md` → criterios de aceptación y DoD
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

## Clasificar hallazgos

**🔴 Bloqueante** — el plan va a fallar o romper algo si se ejecuta así  
**🟠 Importante** — puede generar problemas o retrabajo, hay que ajustar  
**💡 Sugerencia** — mejora opcional, no bloquea  

## Output requerido

Escribir en `.claude/workflow/review-findings.md`:

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

Cuando termines, decir: "Review escrito en .claude/workflow/review-findings.md"

---

## Paso 3 — CHECKPOINT DURO

Leer `review-findings.md` y mostrar el resultado al usuario.

**Este es el checkpoint más importante del sistema. NUNCA pasar a implementación sin respuesta explícita.**

Mostrar el veredicto y preguntar:
**"¿Procedemos a implementar? Respondé 'sí' para continuar o indicá qué hay que ajustar."**

- Si hay 🔴 Bloqueantes → no ofrecer implementar hasta que se resuelvan
- Si hay 🟠 Importantes → mostrarlos y preguntar si ajustar el plan primero
- Si el veredicto es APROBADO → esperar "sí" explícito del usuario

## Paso 4 — Siguiente paso (solo con aprobación)

Solo si el usuario confirma explícitamente: "Siguiente: `/wf-implement`"
