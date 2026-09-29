#!/bin/bash
#
# wf-resources — how much of this machine the workflow is allowed to use.
#
# The workflow used to spawn whatever the tool defaulted to: a test runner takes
# one worker per core, a build takes the rest, and two or three of those run as
# background tasks at the same time. On a 12-core box that is 24+ heavy processes
# and the machine stops responding — which is how it kept freezing mid-run.
#
# This prints one budget, derived from the cores, the free RAM and the load
# already on the machine, so every caller throttles against the same number
# instead of each guessing on its own.
#
# Usage:
#   wf-resources.sh            human-readable summary
#   wf-resources.sh --env      shell assignments, for `eval`
#   wf-resources.sh --json     JSON, for a command to consume
#   wf-resources.sh workers    print a single value (workers|background|load|cores|free_gb)
#
# Exit: 0 always — a machine it cannot measure gets the conservative default,
# never an error that blocks the caller.

set -u

# ---------------------------------------------------------------- measurements

cores="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
[ "$cores" -ge 1 ] 2>/dev/null || cores=2

# Available, not free: page cache is reclaimable and counting it as used makes
# every machine look starved.
free_mb="$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)"
if [ -z "${free_mb:-}" ]; then
  # macOS / anything without /proc: fall back to something rather than nothing.
  free_mb="$(vm_stat 2>/dev/null | awk '
    /page size of/ {ps=$8}
    /Pages free/ {f=$3}
    /Pages inactive/ {i=$3}
    END {if (ps && f) print int((f+i)*ps/1048576)}')"
fi
[ -n "${free_mb:-}" ] && [ "$free_mb" -ge 0 ] 2>/dev/null || free_mb=2048

# 1-minute load. Whatever is already running has to come out of the budget,
# otherwise the workflow piles onto a machine that is busy with a build.
load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
[ -n "${load1:-}" ] || load1="$(uptime 2>/dev/null | sed 's/.*averages*: *//' | tr ',' ' ' | awk '{print $1}')"
case "${load1:-}" in ''|*[!0-9.]*) load1=0 ;; esac

# ------------------------------------------------------------------- the budget

# Headroom in cores: what is left once the current load is accounted for, capped
# so a momentarily idle machine still keeps a core for the desktop.
budget="$(awk -v c="$cores" -v l="$load1" 'BEGIN {
    free_cores = c - l
    if (free_cores < 1) free_cores = 1
    # Never take the whole machine: leave a core for the UI, and never more
    # than half the box to a single runner.
    cap = c / 2
    if (cap < 1) cap = 1
    if (free_cores > cap) free_cores = cap
    printf "%d", free_cores
}')"
[ "$budget" -ge 1 ] 2>/dev/null || budget=1

# Each jsdom/vitest/jest worker is worth roughly a GB once the suite is warm;
# a machine with little RAM left gets fewer workers regardless of its cores.
mem_workers=$(( free_mb / 1024 ))
[ "$mem_workers" -ge 1 ] || mem_workers=1

workers=$budget
[ "$mem_workers" -lt "$workers" ] && workers=$mem_workers
[ "$workers" -ge 1 ] || workers=1

# Heavy background tasks (suites, builds, installs) run one at a time unless the
# machine is genuinely idle and big. Two is the ceiling: the freezes came from
# three-plus overlapping runs, not from the size of any single one.
background=1
if [ "$cores" -ge 8 ] && [ "$workers" -ge 4 ]; then
  background=2
fi

# ---------------------------------------------------------------------- output

case "${1:-}" in
  --env)
    echo "WF_MAX_WORKERS=$workers"
    echo "WF_MAX_BACKGROUND=$background"
    echo "WF_CORES=$cores"
    echo "WF_FREE_MB=$free_mb"
    echo "WF_LOAD1=$load1"
    ;;
  --json)
    printf '{"workers":%d,"background":%d,"cores":%d,"free_mb":%d,"load1":%s}\n' \
      "$workers" "$background" "$cores" "$free_mb" "$load1"
    ;;
  workers)    echo "$workers" ;;
  background) echo "$background" ;;
  load)       echo "$load1" ;;
  cores)      echo "$cores" ;;
  free_gb)    echo $(( free_mb / 1024 )) ;;
  ''|--human)
    echo "cores=$cores  free=$(( free_mb / 1024 ))GB  load1=$load1"
    echo "→ max test/build workers : $workers"
    echo "→ max background tasks   : $background"
    if [ "$workers" -le 2 ]; then
      echo "  (machine is loaded — run suites one at a time)"
    fi
    ;;
  *)
    echo "wf-resources: unknown argument: $1" >&2
    echo "usage: wf-resources.sh [--env|--json|--human|workers|background|load|cores|free_gb]" >&2
    exit 0
    ;;
esac
