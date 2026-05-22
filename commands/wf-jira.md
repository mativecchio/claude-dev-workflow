---
description: "Genera descripción de ticket Jira lista para copiar/pegar, o fetchea un ticket existente via MCP. Perspectiva pre-desarrollo."
allowed-tools: Read, Bash, Glob, mcp__mcp-atlassian__jira_get_issue, mcp__mcp-atlassian__jira_search, TodoWrite
---

Tu rol es generar o enriquecer un ticket de Jira con el nivel de detalle necesario para que pueda implementarse con claridad.

## Paso 1 — Determinar el modo

**Si `$ARGUMENTS` tiene un issue key (ej: BC-1429, PROJ-123):**
Intentar fetchear el ticket via MCP:
- Usar `mcp__mcp-atlassian__jira_get_issue` con el issue key
- Si MCP no está disponible: pedirle al usuario que pegue el contenido del ticket

**Si `$ARGUMENTS` es una descripción libre:**
Usar esa descripción como base para generar el ticket.

**Si no hay argumentos:**
Preguntar: "¿Tenés un issue key de Jira o querés crear un ticket desde una descripción?"

## Paso 2 — Enriquecer con contexto del proyecto

Leer si existen:
- `.claude/workflow/refinement-summary.md` → si ya se hizo el refinement, usarlo
- `.claude/workflow/plan.md` → si ya existe el plan técnico, incluir notas técnicas

## Paso 3 — Generar el ticket

**Perspectiva:** escribir desde el punto de vista de antes del desarrollo, aunque ya esté implementado. Sin debates internos, solo el estado final acordado.

**Nivel de detalle:** suficiente para que Claude (u otro engineer) pueda implementarlo sin preguntas.

```markdown
## [Título del ticket]

### Objetivo
[Qué resuelve y por qué. 2-3 líneas.]

### Criterios de aceptación
- [ ] [criterio concreto y verificable]
- [ ] [criterio concreto y verificable]

### Notas técnicas
[Decisiones de implementación relevantes, constraints, patrones a seguir.
Solo lo que no es obvio del criterio de aceptación.]

### Contrato del endpoint (si aplica)
**[MÉTODO] /path/to/endpoint**

Request:
```json
{
  "campo": "tipo"
}
```

Response:
```json
{
  "campo": "tipo"
}
```

### Infraestructura requerida
- [ ] Variable de entorno: `[NOMBRE]`
- [ ] Migración: [descripción]

### DoD
- [ ] Tests escritos y pasando
- [ ] [ítems del checklist del proyecto]
```

## Paso 4 — Mostrar y ajustar

Mostrar el ticket generado y preguntar:
**"¿Querés ajustar algo?"**

Si el usuario confirma, preguntar si quiere que se actualice el ticket en Jira via MCP (si está disponible).
