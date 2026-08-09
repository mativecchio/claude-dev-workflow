---
description: "Genera mensaje de commit con contexto del workflow activo. Lee plan.md, refinement-summary.md y el diff para producir un mensaje en Conventional Commits con scope del ticket."
allowed-tools: Read, Bash, Glob
---

Tu rol es generar un mensaje de commit preciso usando el contexto del workflow y el diff real.

## Paso 1 — Leer contexto del workflow

Intentar leer (silenciosamente, sin error si no existe):
- `.claude/workflow/state.json` → `activeTicket`
- `{workflowDir}/refinement-summary.md` → objetivo del cambio
- `{workflowDir}/plan.md` → qué se implementó

Donde `{workflowDir}` = `.claude/workflow/{activeTicket}`. Si no hay ticket activo o no existen los archivos, continuar igual — el diff es suficiente.

`/wf-commit` no es una etapa del ciclo: no registra `stage` ni emite telemetría.

## Paso 2 — Obtener el diff

Si se llamó con archivos específicos en `$ARGUMENTS`, usar esos. Si no, usar los archivos staged + modified:

```bash
# Archivos staged
git diff --cached --stat

# Archivos modified (unstaged)
git diff --stat

# Diff completo (excluir lock files y binarios)
git diff HEAD -- ':!pnpm-lock.yaml' ':!*.lock' ':!*.png' ':!*.jpg' ':!*.svg'
```

## Paso 3 — Determinar tipo y scope

**Tipo** (Conventional Commits):

| Tipo | Cuándo |
|------|--------|
| `feat` | nueva funcionalidad visible al usuario |
| `fix` | corrección de bug |
| `refactor` | reestructura sin cambio de comportamiento |
| `style` | cambios de estilo/formato sin lógica |
| `test` | tests nuevos o corregidos |
| `chore` | tooling, config, deps, build |
| `docs` | solo documentación |
| `perf` | mejora de performance |

**Scope**: derivar del ticket ID en `state.json` (ej: `MA-770`) o del módulo más afectado (ej: `PlayerControls`, `chat`, `auth`). Si hay ticket ID, usarlo como scope.

## Paso 4 — Generar el mensaje

Formato:
```
<tipo>(<scope>): <descripción en imperativo, max 72 chars>

[cuerpo opcional: por qué, no el qué — solo si el cambio no es obvio del título]
```

Reglas:
- Descripción en imperativo, minúsculas, sin punto al final
- No repetir el scope en la descripción
- Cuerpo solo si hay decisiones técnicas no obvias o contexto de workaround
- Máximo 2 líneas de cuerpo
- No listar archivos modificados

## Paso 5 — Mostrar y confirmar

Mostrar el mensaje propuesto:

```
📝 Mensaje de commit propuesto:

  <tipo>(<scope>): <descripción>

  [cuerpo si aplica]

¿Usamos este mensaje, lo ajustamos, o escribís uno distinto?
```

Esperar respuesta. Si el usuario aprueba o ajusta → devolver el mensaje final listo para usar.

**No hacer el commit** — solo generar el mensaje. El caller (wf-deploy u otro) ejecuta el commit.
