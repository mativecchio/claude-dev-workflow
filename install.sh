#!/bin/bash

# claude-workflow — install script
# Copia comandos y agentes a ~/.claude/ para uso global

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"
WORKFLOW_DIR="$CLAUDE_DIR/workflow"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

echo "📦 Instalando claude-workflow desde $REPO_DIR..."

# Crear directorios si no existen
mkdir -p "$COMMANDS_DIR"
mkdir -p "$AGENTS_DIR"
mkdir -p "$WORKFLOW_DIR"

# Copiar comandos wf-*
echo "→ Copiando comandos..."
cp "$REPO_DIR/commands/"*.md "$COMMANDS_DIR/"
echo "  ✓ $(ls "$REPO_DIR/commands/"*.md | wc -l | tr -d ' ') comandos instalados en $COMMANDS_DIR"

# Copiar agentes
echo "→ Copiando agentes..."
find "$REPO_DIR/agents" -name "*.md" -exec cp {} "$AGENTS_DIR/" \;
echo "  ✓ $(find "$REPO_DIR/agents" -name "*.md" | wc -l | tr -d ' ') agentes instalados en $AGENTS_DIR"

# Inicializar config global si no existe
if [ ! -f "$WORKFLOW_DIR/config.json" ]; then
  cp "$REPO_DIR/config/workflow.json" "$WORKFLOW_DIR/config.json"
  echo "  ✓ Config inicializado en $WORKFLOW_DIR/config.json"
else
  echo "  ↷ Config existente preservado en $WORKFLOW_DIR/config.json"
fi

# Inicializar flow-history si no existe
if [ ! -f "$WORKFLOW_DIR/flow-history.json" ]; then
  echo '{"entries": []}' > "$WORKFLOW_DIR/flow-history.json"
  echo "  ✓ flow-history.json inicializado"
fi

# Agregar sección de workflow al CLAUDE.md global (idempotente)
MARKER="<!-- claude-workflow -->"

if [ ! -f "$CLAUDE_MD" ]; then
  touch "$CLAUDE_MD"
fi

if grep -q "$MARKER" "$CLAUDE_MD" 2>/dev/null; then
  echo "  ↷ Sección en CLAUDE.md ya existe — omitida"
else
  cat >> "$CLAUDE_MD" << 'EOF'

<!-- claude-workflow -->
## Dev Workflow System

Tenés disponibles comandos slash para el ciclo de desarrollo completo. Usarlos cuando el usuario trabaje en una tarea de desarrollo.

### Flujo principal
| Comando | Propósito |
|---|---|
| `/wf` | Orquestador — detecta etapa y enruta |
| `/wf-refine` | Clarificar alcance y DoD |
| `/wf-analyze` | Análisis técnico → genera plan.md |
| `/wf-review-plan` | Verifica plan contra codebase real |
| `/wf-implement` | Implementación con checkpoints |
| `/wf-validate` | Validation gate post-implementación |
| `/wf-test` | Tests y checklist pre-MR |
| `/wf-mr-desc` | Descripción del MR |
| `/wf-mr-review` | Code review del MR |
| `/wf-retro` | Retrospectiva y mejora del workflow |
| `/wf-jira` | Generar o enriquecer ticket de Jira |

### Agentes de lenguaje disponibles
React Native: `rn-architect`, `rn-debugger`, `rn-performance`, `rn-testing`, `rn-uiux`, `rn-bridge`
React: `react-architect`
TypeScript: `typescript-architect`
Python: `python-architect`
Laravel: `laravel-architect`
API: `backend-api`

### Estado del workflow
El workflow activo se guarda en `.claude/workflow/` dentro del proyecto:
- `state.json` — etapa actual y progreso
- `refinement-summary.md` — output del refinement
- `plan.md` — plan de implementación
- `review-findings.md` — hallazgos del plan review
<!-- /claude-workflow -->
EOF
  echo "  ✓ Sección agregada a $CLAUDE_MD"
fi

echo ""
echo "✅ claude-workflow instalado correctamente"
echo ""
echo "Comandos disponibles: /wf, /wf-refine, /wf-analyze, /wf-review-plan,"
echo "  /wf-implement, /wf-validate, /wf-test, /wf-retro,"
echo "  /wf-mr-review, /wf-mr-desc, /wf-jira"
echo ""
echo "Para configurar un proyecto nuevo, crear .claude/workflow/config.json"
echo "Ver docs/per-project-setup.md para instrucciones."
