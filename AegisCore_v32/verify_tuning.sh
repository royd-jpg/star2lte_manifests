#!/system/bin/sh
set -u
LOG="/data/local/tmp/chimera_verify.log"
BRAIN_LOG="/data/local/tmp/brain_core.log"
: > "$LOG"
PASS=0; WARN=0; FAIL=0

say()  { echo "$(date '+%F %T') [VERIFY] $*" | tee -a "$LOG"; }
ok()   { PASS=$((PASS+1));  say "  ✅ PASS  $1"; }
warn() { WARN=$((WARN+1));  say "  ⚠️  WARN  $1"; }
fail() { FAIL=$((FAIL+1));  say "  ❌ FAIL  $1"; }

say "========================================================"
say "AegisCore V32.0 Tuning Verification"
say "$(date)"
say "========================================================"

# §1 Brain Core alive
say "--- §1 Brain Core daemon ---"
BC_PID="$(pgrep -f brain_core_v32 2>/dev/null | head -1)"
# Fallback: check for any brain_core process
[ -z "$BC_PID" ] && BC_PID="$(pgrep -f brain_core 2>/dev/null | head -1)"
if [ -n "$BC_PID" ] && [ -d "/proc/$BC_PID" ]; then
    ok "Brain Core running (pid=$BC_PID)"
else
    fail "Brain Core NOT running — check: cat $BRAIN_LOG | tail -20"
fi
# Check for stale lock file blocking startup
if [ -f /data/local/tmp/brain_core.lock ]; then
    LOCK_PID="$(cat /data/local/tmp/brain_core.lock 2>/dev/null)"
    if [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
        warn "Stale lock file found (pid=$LOCK_PID dead) — Brain Core blocked. Run: rm /data/local/tmp/brain_core.lock"
    fi
fi
BC_VER="$(grep -m1 'Brain Core V' "$BRAIN_LOG" 2>/dev/null | grep -oE 'V[0-9]+\.[0-9]+' | head -1)"
[ -n "$BC_VER" ] && ok "Brain Core version: $BC_VER" \
    || warn "Version not yet in log (normal if Brain Core just started)"

# §2 schedtune
say "--- §2 schedtune cgroup values ---"
check_node() {
    local label="$1" path="$2" want="$3"
    [ -e "$path" ] || { warn "$label: node missing"; return; }
    got="$(cat "$path" 2>/dev/null | tr -d '\r')"
    [ "$got" = "$want" ] && ok "$label = $got" || fail "$label = $got (want: $want)"
}
check_node "top-app/schedtune.boost"          /dev/stune/top-app/schedtune.boost        "10"
check_node "top-app/schedtune.prefer_idle"    /dev/stune/top-app/schedtune.prefer_idle  "1"
check_node "foreground/schedtune.boost"       /dev/stune/foreground/schedtune.boost     "5"
check_node "foreground/schedtune.prefer_idle" /dev/stune/foreground/schedtune.prefer_idle "1"
check_node "background/schedtune.boost"       /dev/stune/background/schedtune.boost     "0"
check_node "background/schedtune.prefer_idle" /dev/stune/background/schedtune.prefer_idle "0"
[ -e /dev/stune/system-background/schedtune.boost ] \
    && check_node "system-background/schedtune.boost" /dev/stune/system-background/schedtune.boost "0" \
    || warn "system-background/schedtune.boost: node missing (normal on some ROMs)"

# §3 cpuset
say "--- §3 cpuset CPU affinity ---"
check_node "cpuset/top-app/cpus"           /dev/cpuset/top-app/cpus           "0-7"
check_node "cpuset/foreground/cpus"        /dev/cpuset/foreground/cpus        "0-7"
check_node "cpuset/background/cpus"        /dev/cpuset/background/cpus        "0-3"
check_node "cpuset/system-background/cpus" /dev/cpuset/system-background/cpus "0-2"

# §4 Fingerprint HAL BIG-pin
say "--- §4 Fingerprint HAL BIG-cluster pin ---"
FP_PID="$(pidof android.hardware.biometrics.fingerprint-service.samsung 2>/dev/null | awk '{print $1}')"
[ -z "$FP_PID" ] && FP_PID="$(pgrep -f fingerprint 2>/dev/null | head -1)"
if [ -n "$FP_PID" ] && [ -d "/proc/$FP_PID" ]; then
    say "  FP HAL pid=$FP_PID"
    AFF="$(taskset -p "$FP_PID" 2>/dev/null | awk '{print $NF}')"
    case "${AFF:-0}" in
        f0|F0) ok "FP HAL taskset = 0x${AFF} (CPUs 4-7 BIG ✓)" ;;
        *)     fail "FP HAL taskset = 0x${AFF:-?} (expected f0 — Brain Core not yet cycled?)" ;;
    esac
    CPUSET="$(cat /proc/$FP_PID/cpuset 2>/dev/null)"
    [ "$CPUSET" = "/top-app" ] && ok "FP HAL cpuset = /top-app" \
        || warn "FP HAL cpuset = ${CPUSET:-?} (expected /top-app)"
    SCHED="$(chrt -p "$FP_PID" 2>/dev/null | tr '\n' ' ')"
    echo "$SCHED" | grep -q "SCHED_RR" && ok "FP HAL = SCHED_RR" \
        || fail "FP HAL scheduling = $SCHED (expected SCHED_RR)"
else
    warn "FP HAL not found — normal when screen is off or unlocked"
fi

# §5 Audio HAL protection
say "--- §5 Audio HAL protection ---"
grep -q "drop_caches\|compact_memory" "$BRAIN_LOG" 2>/dev/null \
    && fail "drop_caches or compact_memory in Brain Core log — CRITICAL" \
    || ok "drop_caches / compact_memory: NOT in Brain Core log"

CRASHING="$(getprop sys.init.updatable_crashing 2>/dev/null || echo 0)"
CRASH_PROC="$(getprop sys.init.updatable_crashing_process_name 2>/dev/null || echo '')"
[ "$CRASHING" = "1" ] \
    && fail "sys.init.updatable_crashing=1 (proc=${CRASH_PROC})" \
    || ok "sys.init.updatable_crashing = 0"

ASS="$(getprop init.svc.audioserver 2>/dev/null)"
[ "$ASS" = "running" ] && ok "audioserver = running" || fail "audioserver = ${ASS:-unknown}"

# Audio HAL: try all known service names (name changed across Android versions)
AUDIO_HAL_OK=0
for hal_name in \
    "vendor.audio-hal" \
    "android.hardware.audio.service" \
    "vendor.audio-hal-4-0" \
    "vendor.audio-hal-2-0" \
    "audio.hal"; do
    hal_state="$(getprop "init.svc.${hal_name}" 2>/dev/null)"
    if [ "$hal_state" = "running" ]; then
        ok "Audio HAL ($hal_name) = running"
        AUDIO_HAL_OK=1
        break
    fi
done
[ "$AUDIO_HAL_OK" -eq 0 ] \
    && warn "Audio HAL: not found under known init.svc names (audio still functional if audioserver=running)"

# §6 CFS + schedutil
say "--- §6 CFS / schedutil knobs ---"
check_node "sched_latency_ns"      /proc/sys/kernel/sched_latency_ns        "6000000"
check_node "sched_min_granularity" /proc/sys/kernel/sched_min_granularity_ns "1000000"
check_node "sched_migration_cost"  /proc/sys/kernel/sched_migration_cost_ns  "3000000"
check_node "sched_rt_runtime_us"   /proc/sys/kernel/sched_rt_runtime_us      "950000"
check_node "policy0 up_rate_limit"   /sys/devices/system/cpu/cpufreq/policy0/schedutil/up_rate_limit_us   "1500"
check_node "policy0 down_rate_limit" /sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us "16000"
check_node "policy4 up_rate_limit"   /sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us   "1500"
check_node "policy4 down_rate_limit" /sys/devices/system/cpu/cpufreq/policy4/schedutil/down_rate_limit_us "16000"

# §7 Verdict
say "========================================================"
say "VERDICT: ✅ PASS=$PASS  ⚠️  WARN=$WARN  ❌ FAIL=$FAIL"
say "========================================================"
[ "$FAIL" -eq 0 ] \
    && say "✅ All critical checks passed." \
    || say "❌ $FAIL failure(s) — check: cat $BRAIN_LOG | tail -30"
say "Full log: $LOG"
exit 0
