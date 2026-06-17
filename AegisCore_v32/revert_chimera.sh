#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# revert_chimera.sh — Project Chimera complete revert
# Kills Brain Core daemon, removes deployed scripts, resets schedtune/cpuset
# cgroup nodes to Android AOSP defaults. Safe to run at any time.
#
# Usage: sh revert_chimera.sh [--dry-run]
# ═══════════════════════════════════════════════════════════════════════════════

set -u

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

LOG="/data/local/tmp/chimera_revert.log"
_log() { echo "$(date '+%F %T') [REVERT] $*" | tee -a "$LOG"; }
_run() {
    if [ "$DRY_RUN" = "1" ]; then
        _log "[DRY-RUN] $*"
    else
        _log "EXEC: $*"
        eval "$@" 2>/dev/null || _log "  (failed — may already be gone)"
    fi
}

_log "========================================================"
_log "Chimera revert started (dry_run=$DRY_RUN)"
_log "========================================================"

# ─── §1 KILL BRAIN CORE DAEMON ───────────────────────────────────────────────
_log "--- §1 Kill Brain Core daemon ---"

# Two-pass kill: SIGTERM first (allows log flush), SIGKILL after 2s
BC_PIDS="$(pgrep -f 'brain_core' 2>/dev/null || true)"
if [ -n "$BC_PIDS" ]; then
    for pid in $BC_PIDS; do
        _log "Sending SIGTERM to pid=$pid"
        _run "kill -15 $pid"
    done
    sleep 2
    for pid in $BC_PIDS; do
        kill -0 "$pid" 2>/dev/null && _run "kill -9 $pid" || true
    done
else
    _log "Brain Core: no running process found"
fi

# Kill the schedutil watchdog subshell (spawned by Brain Core)
WD_PIDS="$(pgrep -f 'schedutil_watchdog' 2>/dev/null || true)"
[ -n "$WD_PIDS" ] && for pid in $WD_PIDS; do _run "kill -9 $pid"; done

# Remove lock file so a fresh start works cleanly
_run "rm -f /data/local/tmp/brain_core.lock"
_run "rm -f /data/local/tmp/brain_core.lock.pid"

# ─── §2 REMOVE DEPLOYED SCRIPTS ──────────────────────────────────────────────
_log "--- §2 Remove deployed scripts ---"

SCRIPTS="
/data/adb/service.d/brain_core.sh
/data/adb/service.d/99chimera_ems_v21_flow.sh
/data/adb/service.d/99chimera_ems.sh
/system/bin/brain_core.sh
/system/bin/99chimera_ems_v21_flow.sh
/system/bin/99chimera_ems.sh
"

for f in $SCRIPTS; do
    [ -f "$f" ] && _run "chattr -i $f 2>/dev/null; rm -f $f" || true
done

_log "Scripts removed (or were not present)"

# ─── §3 RESET SCHEDTUNE TO AOSP DEFAULTS ─────────────────────────────────────
_log "--- §3 Reset schedtune.boost + schedtune.prefer_idle ---"

# AOSP defaults for cgroupv1 schedtune:
#   schedtune.boost        = 0  (all groups)
#   schedtune.prefer_idle  = 0  (all groups)
STUNE_GROUPS="top-app foreground background system-background"

for grp in $STUNE_GROUPS; do
    node_b="/dev/stune/${grp}/schedtune.boost"
    node_p="/dev/stune/${grp}/schedtune.prefer_idle"
    [ -f "$node_b" ] && _run "echo 0 > $node_b"
    [ -f "$node_p" ] && _run "echo 0 > $node_p"
done

_log "schedtune reset to boost=0 prefer_idle=0 on all groups"

# ─── §4 RESET CPUSET TO AOSP DEFAULTS ────────────────────────────────────────
_log "--- §4 Reset cpuset.cpus to AOSP defaults ---"

# AOSP cgroupv1 cpuset defaults for Exynos 9810 (8-core, 0-7):
_reset_cpuset() {
    local grp="$1" cpus="$2"
    local node="/dev/cpuset/${grp}/cpus"
    [ -f "$node" ] && _run "echo $cpus > $node"
}
_reset_cpuset "top-app"           "0-7"
_reset_cpuset "foreground"        "0-7"
_reset_cpuset "background"        "0-7"
_reset_cpuset "system-background" "0-7"
_reset_cpuset "restricted"        "0-7"
_reset_cpuset "camera-daemon"     "0-7"

_log "cpuset.cpus reset to 0-7 on all groups"

# ─── §5 RESET CPU.SHARES TO AOSP DEFAULTS ────────────────────────────────────
_log "--- §5 Reset cpu.shares to AOSP defaults ---"

_reset_shares() {
    local grp="$1" shares="$2"
    local node="/dev/cpuctl/${grp}/cpu.shares"
    [ -f "$node" ] && _run "echo $shares > $node"
}
_reset_shares "top-app"           "1024"
_reset_shares "foreground"        "800"
_reset_shares "background"        "200"
_reset_shares "system-background" "300"

# ─── §6 RESET SCHEDULER KNOBS TO SAMSUNG BSP DEFAULTS ───────────────────────
_log "--- §6 Reset CFS/schedutil knobs to Samsung BSP defaults ---"

# sched_latency_ns: Samsung BSP default is 10000000 (10ms)
# Brain Core sets 6000000 — revert to stock.
[ -f /proc/sys/kernel/sched_latency_ns ] \
    && _run "echo 10000000 > /proc/sys/kernel/sched_latency_ns"

# sched_min_granularity_ns: Samsung BSP default is 1250000
[ -f /proc/sys/kernel/sched_min_granularity_ns ] \
    && _run "echo 1250000 > /proc/sys/kernel/sched_min_granularity_ns"

# sched_wakeup_granularity_ns: Samsung BSP default is 2500000
[ -f /proc/sys/kernel/sched_wakeup_granularity_ns ] \
    && _run "echo 2500000 > /proc/sys/kernel/sched_wakeup_granularity_ns"

# sched_migration_cost_ns: Samsung BSP default is 500000 (500µs)
[ -f /proc/sys/kernel/sched_migration_cost_ns ] \
    && _run "echo 500000 > /proc/sys/kernel/sched_migration_cost_ns"

# schedutil rate limits: restore to kernel defaults (500µs / 20000µs)
for pol_dir in /sys/devices/system/cpu/cpufreq/policy*/schedutil/; do
    [ -d "$pol_dir" ] || continue
    [ -f "${pol_dir}up_rate_limit_us"   ] && _run "echo 500   > ${pol_dir}up_rate_limit_us"
    [ -f "${pol_dir}down_rate_limit_us" ] && _run "echo 20000 > ${pol_dir}down_rate_limit_us"
done

# Restore cpu freq caps (remove Brain Core throttle, restore hardware max)
[ -f /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq ] \
    && _run "echo 1950000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
[ -f /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq ] \
    && _run "echo 2314000 > /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq"

# ─── §7 RESET VM KNOBS TO AOSP DEFAULTS ──────────────────────────────────────
_log "--- §7 Reset vm knobs ---"

[ -f /proc/sys/vm/swappiness ]              && _run "echo 100 > /proc/sys/vm/swappiness"
[ -f /proc/sys/vm/dirty_ratio ]             && _run "echo 20  > /proc/sys/vm/dirty_ratio"
[ -f /proc/sys/vm/dirty_background_ratio ]  && _run "echo 5   > /proc/sys/vm/dirty_background_ratio"
[ -f /proc/sys/vm/vfs_cache_pressure ]      && _run "echo 100 > /proc/sys/vm/vfs_cache_pressure"

# ─── §8 DISMISS BRAIN CORE NOTIFICATIONS ─────────────────────────────────────
_log "--- §8 Dismiss Brain Core notifications ---"
_run "cmd notification cancel Brain_Core 2>/dev/null" || true

# ─── DONE ────────────────────────────────────────────────────────────────────
_log "========================================================"
_log "Chimera revert COMPLETE"
_log "All schedtune/cpuset/cpuctl nodes reset to AOSP defaults."
_log "Brain Core daemon killed. Scripts removed."
_log "No reboot required. ROM default scheduler is now active."
_log "========================================================"

exit 0
