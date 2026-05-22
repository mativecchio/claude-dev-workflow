---
description: "Validation gate post-implementación. El usuario elige qué validadores activar. Corre en contexto aislado. Loop hasta 3 iteraciones antes de escalar."
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite, TodoRead
---

Tu rol es correr validaciones automáticas sobre el diff de la implementación. El usuario elige qué validadores activar.

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

```bash
git diff HEAD~1 HEAD --stat
git diff HEAD~1 HEAD
```

Si no hay commits recientes, usar:
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
[contenido de .claude/workflow/plan.md]

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
Mostrar el feedback estructurado y preguntar:
**"¿Volvemos a `/wf-implement` con este feedback o escalamos a vos?"**

Llevar cuenta de iteraciones. Si se llega a 3 sin aprobar, escalar:
**"⚠️ Se alcanzaron 3 iteraciones sin aprobar. Revisión manual requerida antes de continuar."**
