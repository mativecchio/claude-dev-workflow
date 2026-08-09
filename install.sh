#!/bin/bash

# claude-workflow — install script
# Copia comandos y agentes a ~/.claude/ para uso global

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
AGENTS_DIR="$CLAUDE_DIR/agents"
WORKFLOW_DIR="$CLAUDE_DIR/workflow"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# --- Modo --check: reporta divergencias sin escribir nada ------------------
# El repo es la fuente de verdad. /wf-retro y /wf-improve editan el repo y
# reinstalan; este modo verifica que no se haya roto esa disciplina.
if [ "${1:-}" = "--check" ]; then
  echo "🔍 Comparando repo vs instalado..."
  DIVERGENCIAS=0

  for f in "$REPO_DIR/commands/"*.md; do
    b="$(basename "$f")"
    if [ ! -f "$COMMANDS_DIR/$b" ]; then
      echo "  ✗ falta instalado: $b"
      DIVERGENCIAS=$((DIVERGENCIAS + 1))
    elif ! diff -q "$f" "$COMMANDS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ difiere: $b"
      DIVERGENCIAS=$((DIVERGENCIAS + 1))
    fi
  done

  # Comandos wf-* instalados que no tienen origen en el repo: el modo de
  # falla que dejó huérfanos a wf-commit y wf-deploy.
  for f in "$COMMANDS_DIR/"wf-*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    if [ ! -f "$REPO_DIR/commands/$b" ]; then
      echo "  ✗ huérfano (instalado sin origen en el repo): $b"
      DIVERGENCIAS=$((DIVERGENCIAS + 1))
    fi
  done

  while IFS= read -r f; do
    b="$(basename "$f")"
    if [ ! -f "$AGENTS_DIR/$b" ] || ! diff -q "$f" "$AGENTS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ agente difiere o falta: $b"
      DIVERGENCIAS=$((DIVERGENCIAS + 1))
    fi
  done < <(find "$REPO_DIR/agents" -name "*.md")

  for h in "$REPO_DIR/hooks/"*.sh; do
    [ -e "$h" ] || continue
    b="$(basename "$h")"
    if [ ! -f "$HOOKS_DIR/$b" ] || ! diff -q "$h" "$HOOKS_DIR/$b" >/dev/null 2>&1; then
      echo "  ✗ hook difiere o falta: $b"
      DIVERGENCIAS=$((DIVERGENCIAS + 1))
    fi
  done

  if [ "$DIVERGENCIAS" -eq 0 ]; then
    echo "✅ Sin divergencias — el repo y lo instalado coinciden"
    exit 0
  fi
  echo ""
  echo "⚠️  $DIVERGENCIAS divergencia(s). Correr install.sh para sincronizar,"
  echo "    o portar al repo lo que se haya editado en $CLAUDE_DIR."
  exit 1
fi

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

# Config global. `repo_path` se MERGEA siempre, no solo al crear el archivo:
# preservar el config intacto dejaba sin la clave a toda instalación previa,
# y /wf-retro y /wf-improve la necesitan para editar el repo en vez de ~/.claude.
if [ ! -f "$WORKFLOW_DIR/config.json" ]; then
  cp "$REPO_DIR/config/workflow.json" "$WORKFLOW_DIR/config.json"
  echo "  ✓ Config inicializado en $WORKFLOW_DIR/config.json"
fi

if command -v jq >/dev/null 2>&1 && jq -e . "$WORKFLOW_DIR/config.json" >/dev/null 2>&1; then
  TMP="$(mktemp)"
  if jq --arg p "$REPO_DIR" '.repo_path = $p' "$WORKFLOW_DIR/config.json" > "$TMP" 2>/dev/null; then
    mv "$TMP" "$WORKFLOW_DIR/config.json"
    echo "  ✓ repo_path apunta a $REPO_DIR"
  else
    rm -f "$TMP"
    echo "  ⚠ No se pudo escribir repo_path en el config global"
  fi
else
  echo "  ⚠ config.json global ausente o inválido — repo_path NO configurado."
  echo "    /wf-retro y /wf-improve van a caer al modo manual."
fi

# Inicializar flow-history si no existe
if [ ! -f "$WORKFLOW_DIR/flow-history.json" ]; then
  echo '{"entries": []}' > "$WORKFLOW_DIR/flow-history.json"
  echo "  ✓ flow-history.json inicializado"
fi

# Bitácora de cambios al workflow (brainstorm §0 y §8): todo cambio aplicado
# se asienta acá con su evidencia. Sin esto, la regla de fundamentación no
# tiene dónde escribirse.
if [ ! -f "$WORKFLOW_DIR/improvements.md" ]; then
  cat > "$WORKFLOW_DIR/improvements.md" << 'IMPEOF'
# Improvements — bitácora de cambios al workflow

> Regla (`docs/brainstorm-metricas-y-complejidad.md` §0): ningún cambio se
> asienta acá sin su evidencia. Si no se puede escribir la evidencia, el
> cambio no se aplica.

Formato de cada entrada:

```
## [fecha] — [componente afectado]
**Cambio:** qué se modificó
**Evidencia:** archivo:línea, o la consulta concreta sobre events.jsonl
  (categoría de evento, cantidad de tickets, período)
**Resultado esperado:** qué métrica debería moverse
```

---
IMPEOF
  echo "  ✓ improvements.md inicializado"
fi

# --- Telemetría (docs/brainstorm-metricas-y-complejidad.md §3.2) -------------
echo "→ Instalando hooks de telemetría..."
mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/wf-telemetry.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/wf-telemetry.sh"
touch "$WORKFLOW_DIR/events.jsonl"

if ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq no está instalado — los hooks van a salir sin registrar nada."
  echo "    Instalar con: brew install jq"
else
  # Registrar los hooks en settings.json preservando los que ya existan.
  # Idempotente: primero se descarta cualquier entrada previa de wf-telemetry.
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

  if jq -e . "$SETTINGS" >/dev/null 2>&1; then
    TMP="$(mktemp)"
    jq --arg h "$HOOKS_DIR/wf-telemetry.sh" '
      def strip:
        map(.hooks |= map(select((.command // "") | contains("wf-telemetry.sh") | not)))
        | map(select((.hooks | length) > 0));
      def add($mode):
        . + [{hooks: [{type: "command", command: ($h + " " + $mode)}]}];

      .hooks                    //= {}
      | .hooks.UserPromptSubmit //= [] | .hooks.UserPromptSubmit |= (strip | add("prompt"))
      | .hooks.PostToolUse      //= [] | .hooks.PostToolUse      |= (strip | add("tool"))
      | .hooks.Stop             //= [] | .hooks.Stop             |= (strip | add("stop"))
      | .hooks.SessionEnd       //= [] | .hooks.SessionEnd       |= (strip | add("session-end"))
    ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
    echo "  ✓ Hooks registrados en $SETTINGS (hooks existentes preservados)"
  else
    echo "  ⚠ $SETTINGS no es JSON válido — hooks NO registrados."
    echo "    Corregir el archivo y volver a correr install.sh"
  fi
fi

# Sección de workflow en el CLAUDE.md global.
#
# El bloque entre marcadores se REGENERA en cada instalación. La versión previa
# hacía skip si el marcador existía, así que una instalación vieja se quedaba
# con la lista de comandos de ese momento para siempre — el mismo modo de falla
# que dejó huérfanos a wf-commit y wf-deploy, en otro canal. Lo que está fuera
# de los marcadores no se toca nunca.
[ -f "$CLAUDE_MD" ] || touch "$CLAUDE_MD"

BLOCK="$(mktemp)"
cat > "$BLOCK" << 'EOF'
<!-- claude-workflow -->
## Dev Workflow System

Tenés disponibles comandos slash para el ciclo de desarrollo completo. Usarlos cuando el usuario trabaje en una tarea de desarrollo.

### Flujo principal
| Comando | Propósito |
|---|---|
| `/wf` | Orquestador — detecta etapa y enruta |
| `/wf-init` | Inicializa el workflow en un proyecto (una vez por repo) |
| `/wf-refine` | Clarificar alcance y DoD |
| `/wf-analyze` | Análisis técnico → genera plan.md |
| `/wf-review-plan` | Verifica plan contra codebase real |
| `/wf-implement` | Implementación con checkpoints |
| `/wf-validate` | Validation gate post-implementación |
| `/wf-test` | Tests y checklist pre-MR |
| `/wf-commit` | Mensaje de commit con contexto del ticket |
| `/wf-deploy` | Commit+push, release branch y deploy |
| `/wf-mr-desc` | Descripción del MR |
| `/wf-mr-review` | Code review del MR |
| `/wf-retro` | Retrospectiva y mejora del workflow |
| `/wf-improve` | Registrar una observación, o revisar todo lo acumulado |
| `/wf-jira` | Generar o enriquecer ticket de Jira |

### Agentes de lenguaje disponibles
React Native: `rn-architect`, `rn-debugger`, `rn-performance`, `rn-testing`, `rn-uiux`, `rn-bridge`
React: `react-architect`
TypeScript: `typescript-architect`
Python: `python-architect`
Laravel: `laravel-architect`
ML / CV: `ml-architect`, `ml-evaluator`, `ml-testing`, `cv-engineer`
API: `backend-api`

### Estado del workflow
Soporta múltiples tickets. El estado raíz solo guarda cuál está activo:
- `.claude/workflow/state.json` — `{ "activeTicket": "BC-XXXX" }`
- `.claude/workflow/{ticketId}/state.json` — etapa, progreso, branch
- `.claude/workflow/{ticketId}/` — refinement-summary.md, plan.md, review-findings.md
- `.claude/workflow/config.json` — stack, DoD, related_projects

### Mejora del sistema
El repo fuente (`repo_path` en `~/.claude/workflow/config.json`) es la fuente de verdad.
Nunca editar `~/.claude/commands/` directo — se pierde en la próxima instalación.
Verificar sincronía: `install.sh --check`
<!-- /claude-workflow -->
EOF

if grep -q "<!-- claude-workflow -->" "$CLAUDE_MD" 2>/dev/null; then
  TMP="$(mktemp)"
  # Copia todo lo de afuera del bloque e inyecta la versión nueva en su lugar.
  awk -v blockfile="$BLOCK" '
    /<!-- claude-workflow -->/ { while ((getline line < blockfile) > 0) print line; skip=1; next }
    /<!-- \/claude-workflow -->/ { skip=0; next }
    !skip { print }
  ' "$CLAUDE_MD" > "$TMP" && mv "$TMP" "$CLAUDE_MD"
  echo "  ✓ Sección de CLAUDE.md regenerada"
else
  { echo ""; cat "$BLOCK"; } >> "$CLAUDE_MD"
  echo "  ✓ Sección agregada a $CLAUDE_MD"
fi
rm -f "$BLOCK"

echo ""
echo "✅ claude-workflow instalado correctamente"
echo ""
echo "Comandos disponibles: /wf, /wf-init, /wf-refine, /wf-analyze, /wf-review-plan,"
echo "  /wf-implement, /wf-validate, /wf-test, /wf-commit, /wf-deploy,"
echo "  /wf-mr-desc, /wf-mr-review, /wf-retro, /wf-improve, /wf-jira"
echo ""
echo "Para configurar un proyecto nuevo: correr /wf-init desde su raíz."
echo "Para verificar que repo e instalación coinciden: install.sh --check"
