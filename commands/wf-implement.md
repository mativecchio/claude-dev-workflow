---
description: "Implementa los cambios siguiendo el plan aprobado. Incluye modo debug para bugs/errores. Checkpoint antes de cada grupo de archivos."
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, TodoWrite, TodoRead
---

Tu rol es implementar siguiendo el plan aprobado, respetando las convenciones del proyecto, con checkpoints antes de cada paso costoso.

## Detección de modo

### Modo Debug
Si en `$ARGUMENTS` o en el contexto aparecen señales como: "no funciona", "error", "bug", "falla", "devuelve 4xx/5xx", "está roto", "no renderiza":

1. **Primero: diagnóstico** — explorar el código y entender la causa raíz
2. **Mostrar el análisis** antes de tocar nada:
   ```
   🔍 Causa raíz detectada: [descripción]
   📋 Plan de fix:
   1. [paso 1]
   2. [paso 2]
   ```
3. **Checkpoint**: "¿Este análisis es correcto? ¿Procedo con el fix?"
4. Esperar confirmación antes de modificar archivos

### Modo Normal
Seguir el flujo completo abajo.

---

## Paso 1 — Leer el contexto del plan

Leer:
- `.claude/workflow/plan.md` → qué cambiar y en qué orden
- `.claude/workflow/review-findings.md` → ajustes requeridos al plan
- `.claude/workflow/config.json` → DoD y stack

Si no existe `plan.md`, decirle al usuario que primero corra `/wf-analyze` y `/wf-review-plan`.

## Paso 2 — Checkpoint de inicio

Mostrar resumen del plan al usuario:
```
📋 Plan aprobado: [nombre de la tarea]
📁 Archivos a modificar: [cantidad]
📍 Orden de implementación:
  1. [módulo/grupo 1]
  2. [módulo/grupo 2]
```

Preguntar: **"¿Arrancamos?"**

Esperar confirmación antes de tocar cualquier archivo.

## Paso 3 — Implementar por grupos

Para cada grupo de archivos del plan:

**Antes de modificar:**
- Leer el archivo completo
- Entender el contexto y las convenciones locales (naming, imports, manejo de errores)

**Checkpoint antes de cada grupo (si tiene más de 1 archivo o es un módulo clave):**
```
⚡ Próximo paso: [descripción del grupo]
Archivos: [lista]
```
Preguntar: "¿Continúo?" — solo si el usuario configuró checkpoints detallados o si el cambio es de alto riesgo (contratos, auth, DB).

**Durante la implementación:**
- Respetar: naming, estructura de imports, estilo de error handling, i18n si aplica
- Si detectás un helper existente que el plan no contempló → usarlo y documentar el desvío
- Si hay un cambio necesario que el plan no contempló → informar antes de hacerlo

## Paso 4 — Registrar desvíos

Si durante la implementación hay algo que se hace diferente al plan:
```
⚠️  Desvío del plan: [descripción]
Razón: [por qué]
Impacto: [qué cambia]
```

## Paso 5 — Registrar deuda técnica

Si encontrás deuda técnica durante la implementación, agregar al final de `.claude/workflow/plan.md`:
```markdown
## Deuda técnica detectada (no implementada)
- [descripción] — detectada en [archivo]
```

## Paso 6 — Resumen al terminar

Al completar todos los grupos:
```
✅ Implementación completada
📁 Archivos modificados: [lista]
⚠️  Desvíos del plan: [lista o "ninguno"]
🔧 Deuda técnica registrada: [lista o "ninguna"]
```

Sugerir: "Siguiente: `/wf-validate` (opcional, recomendado) o `/wf-test`"
