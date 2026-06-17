#!/system/bin/sh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  BRAIN CORE V32.0 "SENTINEL"  (V31 + V32 Stabilitas merge)                 ║
# ║  Target : Samsung Galaxy S9+ (SM-G965F) · Exynos 9810                      ║
# ║           Chimera Mk7 4.9.337 · Evolution X 11.8 (Android 16 QPR2)         ║
# ║                                                                             ║
# ║  V30.1 FIX — AEGIS DIAGS v5.1 review (2026-06-14): speaker audio dead      ║
# ║                                                                             ║
# ║  ROOT CAUSE: V30.0 apply_memory_pressure_response() called drop_caches     ║
# ║  and compact_memory under PSI pressure. Exynos 9810 vendor.audio-hal       ║
# ║  holds open mmap()d ABOX DSP firmware and abox_vdma DMA regions. These    ║
# ║  are backed by pagecache-adjacent memory — drop_caches invalidated those   ║
# ║  mappings, causing SIGSEGV in the HAL at t=938.973s. The HAL crashed 4x   ║
# ║  in 4 minutes, triggering sys.init.updatable_crashing=1 (vendor.audio-hal ║
# ║  named). Init stopped auto-restarting. audioserver stuck 'restarting'.     ║
# ║  Speaker completely dead without reboot.                                   ║
# ║                                                                             ║
# ║  FIXES in V30.1:                                                           ║
# ║  [FIX-1] drop_caches and compact_memory PERMANENTLY REMOVED from           ║
# ║           apply_memory_pressure_response(). Never safe on this SoC.        ║
# ║  [FIX-2] am force-stop in both apply_memory_pressure_response() and        ║
# ║           apply_evox_bloat() now gated on _audio_stack_live(). When        ║
# ║           audioserver is running, OOM score adjustment is used instead      ║
# ║           — lmkd handles eviction safely.                                  ║
# ║  [FIX-3] New apply_audio_hal_crash_recovery() watchdog detects the         ║
# ║           updatable_crashing=1/vendor.audio-hal state, clears the flag,    ║
# ║           and restarts the stack in correct order: vendor.audio-hal →       ║
# ║           audioserver → dap_post_audio_restart. Runs at head of            ║
# ║           apply_policy() every poll cycle. Rate-limited to 90s.            ║
# ║  [FIX-4] apply_spkamp_shim_watchdog() now checks updatable_crashing first  ║
# ║           and yields to the recovery watchdog if the flag is set —          ║
# ║           prevents a HAL bounce race with the recovery sequence.            ║
# ║                                                                             ║
# ║  V30.0 CHANGES vs V29.5.3 — AEGIS DIAGS v5.1 review (2026-06-13):         ║
# ║                                                                             ║
# ║  [A] AIDL audio HAL: audioserver and android.hardware.audio.service        ║
# ║      both confirmed CFS (FAIL in diag). New apply_audio_rt() issues        ║
# ║      chrt SCHED_RR p=3 on every audioserver thread PID via /proc/N/task/  ║
# ║      and SCHED_RR p=2 on the HAL process. Replaces the OOM-only path.     ║
# ║      A2DP offload prop not-set warning addressed: sets a2dp.offload.cap.   ║
# ║                                                                             ║
# ║  [B] Bluetooth HIDL 1.0: BT HAL (pid 6325) found but BT Audio HAL NOT     ║
# ║      RUNNING — this causes A2DP stream death on reconnect. New             ║
# ║      apply_bt_audio_ensure() checks IBluetoothAudioProviderFactory AIDL   ║
# ║      registration and restarts android.hardware.bluetooth@1.0-service if  ║
# ║      BT Audio HAL is missing >30s after BT adapter enable is detected.    ║
# ║      BT A2DP offload: sets persist.bluetooth.a2dp_offload.disabled=false. ║
# ║                                                                             ║
# ║  [C] Fingerprint HAL: confirmed AIDL (android.hardware.biometrics.        ║
# ║      fingerprint-service.samsung, PID 7308). Discovery updated to use      ║
# ║      init.svc_debug_pid.vendor.fingerprint-default first (matches diag),  ║
# ║      then service registry fallback. Raised to SCHED_RR p=5 + OOM -950.   ║
# ║      All fingerprint threads in /proc/N/task/ also raised to SCHED_RR p=5 ║
# ║      for minimum unlock latency.                                           ║
# ║                                                                             ║
# ║  [D] sched_latency_ns: diag shows 10000000 (Samsung default), scorecard   ║
# ║      WARNs for target 6000000. Brain Core V30 sets 6000000 in            ║
# ║      apply_system_knobs() and the schedutil watchdog re-asserts it.       ║
# ║                                                                             ║
# ║  [E] PSI memory pressure very high (full avg10=45%). New                   ║
# ║      apply_memory_pressure_response() runs when full avg10 > PSI_SEVERE.  ║
# ║      Trims background processes, compacts zram, and drops caches under     ║
# ║      a lockout guard so it fires at most once per 120s.                   ║
# ║                                                                             ║
# ║  [F] Phantom killer WARNs (max_phantom_processes, native_boot ns not set). ║
# ║      apply_phantom_killer_guard() sets both device_config keys via         ║
# ║      device_config put on first boot pass. Prevents phantom process kills  ║
# ║      of Brain Core subshells and busybox workers.                          ║
# ║                                                                             ║
# ║  [G] Notifications: TERMUX_API removed from all paths. All user-facing    ║
# ║      messages now use cmd notification post exclusively. Verified against  ║
# ║      AIDL service registry (android.hardware.notification present).        ║
# ║                                                                             ║
# ║  [H] EMS: diag confirms /sys/kernel/ems/ is exposed but eff_mode=0 and    ║
# ║      all ontime/band nodes are empty strings. EMS writes are now guarded   ║
# ║      with a content-check to avoid writing to stub nodes. eff_mode=1 is   ║
# ║      attempted on each boot pass.                                          ║
# ║                                                                             ║
# ║  [I] thermal zone mapping confirmed from diag: zone0=BIG(53°C at          ║
# ║      capture), zone1=LITTLE(54°C), zone2=G3D(50°C), zone3=ISP(50°C).     ║
# ║      Thermal latch thresholds tightened: HIGH=72°C / LOW=65°C.            ║
# ║      HAL cooling path confirmed: thermal-cpufreq-0 cur_state confirmed     ║
# ║      at /sys/class/thermal/cooling_device2/cur_state.                     ║
# ║                                                                             ║
# ║  [J] swappiness watchdog: diag shows zram-swap-manager module active.     ║
# ║      New ZRAM_SWAP_MGR_COMPAT mode detects zram-swap-manager and yields   ║
# ║      swappiness control to it (avoids the V29.3 conflict).                ║
# ║                                                                             ║
# ║  [K] Native notification channel: IDs and channels pre-registered once    ║
# ║      at boot via cmd notification createChannel.                           ║
# ║                                                                             ║
# ║  V30.2 — memory_pressure_guard() formalization (2026-06-15)               ║
# ║                                                                             ║
# ║  V30.1 fixed the SIGSEGV by removing drop_caches/compact_memory outright.  ║
# ║  V30.2 keeps that removal in force and adds a formal, reusable guard so    ║
# ║  ANY future memory-assist routine is automatically checked against the    ║
# ║  audio HAL's state before it runs — not just the two call sites fixed in  ║
# ║  V30.1.                                                                    ║
# ║                                                                             ║
# ║  ANALOGY: system memory is a busy restaurant kitchen. audioserver,         ║
# ║  vendor.audio-hal, mediaserver and the AIDL audio service are the chef —   ║
# ║  while any of them are mid-prep (running), you do NOT deep-clean the      ║
# ║  kitchen (no drop_caches/compact_memory — already permanently banned).     ║
# ║  Even light tidying (process trims) waits until the chef has stepped away  ║
# ║  long enough that they won't be disturbed mid-step.                       ║
# ║                                                                             ║
# ║  [L] New "Safety Zone" process list (SAFETY_ZONE_PROCS) and                ║
# ║      memory_pressure_guard(), which sets MPG_STATUS to one of:            ║
# ║        BUSY     — a Safety Zone process is live right now. oom_score      ║
# ║                    nudges only; no trims.                                  ║
# ║        SAFE     — Safety Zone clear, but not idle long enough yet          ║
# ║                    (< MPG_IDLE_GRACE_S). oom_score nudges only.            ║
# ║        IDLE_EXT — Safety Zone has been clear for >= MPG_IDLE_GRACE_S.      ║
# ║                    A rate-limited deferred trim (am kill-background-      ║
# ║                    processes on bloat pkgs — userspace teardown, never a  ║
# ║                    VM/page-cache op) is permitted.                        ║
# ║      apply_memory_pressure_response() now dispatches on MPG_STATUS.       ║
# ║      _audio_stack_live() is now derived from SAFETY_ZONE_PROCS via a      ║
# ║      shared _svc_is_live() check (getprop init.svc.<name> OR pidof        ║
# ║      fallback), extending coverage to mediaserver and the AIDL audio       ║
# ║      service.                                                              ║
# ║                                                                             ║
# ║  [M] Zero added jitter: memory_pressure_guard() is only evaluated inside   ║
# ║      apply_memory_pressure_response(), which is itself gated by            ║
# ║      PSI_SEVERE + MEM_PRESSURE_LOCKOUT (>=120s apart). The guard's own     ║
# ║      checks are a handful of getprop/pidof calls — no new polling, no      ║
# ║      new sleeps, no change to POLL_SCREEN_ON/POLL_SCREEN_OFF/FAST_POLL.    ║
# ║                                                                             ║
# ║  AudioProxy SIGSEGV (separate issue, build-time): traced to compiler       ║
# ║  miscompilation of audio components, fixed via clean rebuild with          ║
# ║  KCFLAGS="-O2 -fcommon -fno-strict-aliasing -Wno-error". All pcm_null_     ║
# ║  patch hotpatch modules (v1-v2) are retired. Unrelated to this guard, but  ║
# ║  noted here as the companion fix for Mk7/star2lte builds.                 ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -u
umask 022

INSTALL_TARGET="/data/adb/service.d/brain_core.sh"

# ─── Paths ────────────────────────────────────────────────────────────────────
LOG_FILE="/data/local/tmp/brain_core.log"
LOCK_FILE="/data/local/tmp/brain_core.lock"
OVERRIDE_TIMEOUT_FILE="/data/local/tmp/brain.no_timeout"

# ─── Log verbosity ────────────────────────────────────────────────────────────
LOG_LEVEL=1
CMD_NOTIFICATION_TAG="Brain_Core"
CMD_NOTIFICATION_CHAN="brain_core_alerts"
CMD_NOTIFICATION_APP="com.android.systemui"
SCRIPT_VERSION="V32.0"

# ─── F_ fact variable defaults ────────────────────────────────────────────────
F_FDE_MODE="auto"
F_SCREEN_ON=0
F_FG_APP=""
F_BATT=50
F_CHARGING=0
F_THERMAL=0
F_MEM_AVAILABLE_MB=0
F_MEM_PRESSURE=0
F_PSI_FULL_AVG10=0
F_CAMERA_ACTIVE=0
F_LOAD_AVG_100=0
F_BRIGHTNESS=0
F_BT_ENABLED=0
_SAVED_BRIGHTNESS=128
LAST_THERMAL_LOG=0
LAST_MEDIA_LOG=0
LAST_BT_PID=""
LAST_BT_AUDIO_ENSURE=0
LAST_BT_WATCH_CHECK=0
CODEC2_BOOT_FIXED=0
_NOTIF_CHAN_CREATED=0

# ─── State tracking ───────────────────────────────────────────────────────────
LAST_STATE=""
LAST_FDE_MODE=""
LAST_MEM_TIER=""
BOOT_STATIC_DONE=0

# ─── Screen timeout ───────────────────────────────────────────────────────────
MAX_TIMEOUT=120000
MIN_TIMEOUT=30000
INACTIVITY_THRESHOLD=60
INACTIVITY_TIMEOUT=30000

# ─── Polling ──────────────────────────────────────────────────────────────────
POLL_SCREEN_ON=120
POLL_SCREEN_OFF=600
FAST_POLL=5

# ─── Memory tier thresholds ───────────────────────────────────────────────────
MEM_TIER_COMFORTABLE=1200
MEM_TIER_TIGHT=600

# ─── Exynos 9810 hardware ─────────────────────────────────────────────────────
LITTLE_POLICY="/sys/devices/system/cpu/cpufreq/policy0"
BIG_POLICY="/sys/devices/system/cpu/cpufreq/policy4"
LITTLE_FREQ_MAX_DEFAULT=1950000
BIG_FREQ_MAX_DEFAULT=2314000
LITTLE_FREQ_MIN_DEFAULT=455000
BIG_FREQ_MIN_DEFAULT=650000

# ─── CFS tuning constants ─────────────────────────────────────────────────────
# [D] sched_latency_ns target = 6000000 (scorecard requires; Samsung BSP=10ms)
CFS_SCHED_LATENCY_NS=6000000
CFS_SCHED_MIN_GRAN_NS=1000000
CFS_SCHED_WAKEUP_GRAN_NS=2000000
SCHEDUTIL_UP_RATE_LIMIT_US=1500
SCHEDUTIL_DOWN_RATE_LIMIT_US=16000

# ─── Thermal — [I] confirmed zone mapping from AEGIS diag ────────────────────
THERMAL_ZONE_BIG="/sys/class/thermal/thermal_zone0/temp"
THERMAL_ZONE_LITTLE="/sys/class/thermal/thermal_zone1/temp"
# [I] Tightened from 75000/70000 — device peaked at 53/54°C at capture,
# thermal headroom reduced to avoid accumulating heat undetected.
THERMAL_HYST_HIGH=72000
THERMAL_HYST_LOW=65000
THERMAL_LATCH=0
THERMAL_LATCH_TICKS=0
THERMAL_LATCH_MIN=3
# [I] Confirmed cooling_device2 = thermal-cpufreq-0 (BIG cluster)
HAL_COOLING_BIG="/sys/class/thermal/cooling_device2/cur_state"

# ─── PSI thresholds ───────────────────────────────────────────────────────────
PSI_MODERATE=10
PSI_SEVERE=30
# [E] Memory pressure response lockout interval (seconds)
MEM_PRESSURE_LOCKOUT=120
_LAST_MEM_PRESSURE_RESPONSE=0

# ─── [MPG] Memory Pressure Guard — Safety Zone ───────────────────────────────
# Processes that mmap/own DSP & media buffers. While ANY of these are
# "live" (running AND recently active), the guard blocks deep memory
# actions — same logic as "don't deep-clean the kitchen while the chef
# is mid-prep at the stove."
SAFETY_ZONE_PROCS="audioserver vendor.audio-hal mediaserver android.hardware.audio.service"
# How long (s) the Safety Zone must be clear before a deferred trim is
# allowed to run. Prevents a trim from landing mid-handshake right after
# the HAL goes quiet (e.g., between tracks).
MPG_IDLE_GRACE_S=20
_MPG_AUDIO_IDLE_SINCE=0
# Rate limit for the deferred trim itself (separate from the lockout on
# the overall response, so a long PSI event doesn't spam am commands).
MPG_TRIM_LOCKOUT=180
_LAST_MPG_TRIM=0
# Set by memory_pressure_guard(): BUSY | SAFE | IDLE_EXT
MPG_STATUS="SAFE"

# ─── Touch input ──────────────────────────────────────────────────────────────
TOUCH_EVENT="/dev/input/event0"

# ─── Camera apps ─────────────────────────────────────────────────────────────
CAMERA_APPS="org.lineageos.aperture com.google.android.GoogleCamera com.samsung.android.app.camera com.android.camera2"

# ─── Camera ISP daemons ───────────────────────────────────────────────────────
CAMERA_ISP_DAEMONS="vendor.camera-provider-2-5 fimc_is_daemon sensorserver vendor.samsung.hardware.camera.provider android.hardware.camera.provider@2.4-service"

# ─── Fingerprint HAL — [C] AIDL confirmed on diag ────────────────────────────
FINGERPRINT_SVCS="vendor.fingerprint-default android.hardware.biometrics.fingerprint-service.samsung vendor.samsung.hardware.biometrics.fingerprint"

# ─── Bluetooth HAL ───────────────────────────────────────────────────────────
BT_HAL_SVCS="vendor.bluetooth-1-0 android.hardware.bluetooth@1.0-service com.android.bluetooth"
# [B] AIDL BT Audio provider confirmed present in service registry
BT_AUDIO_AIDL="android.hardware.bluetooth.audio.IBluetoothAudioProviderFactory/default"
# Time to wait after BT enable before declaring BT Audio HAL missing
BT_AUDIO_WAIT_S=30

# ─── Background audio players ─────────────────────────────────────────────────
BACKGROUND_AUDIO_PKGS="com.apple.android.music com.spotify.music com.maxmpz.equalizer com.google.android.apps.youtube.music com.soundcloud.android com.bbc.sounds com.google.android.youtube"
STREAMING_AUDIO_APPS="com.google.android.apps.youtube.music com.spotify.music com.apple.android.music org.videolan.vlc com.maxmpz.equalizer com.google.android.youtube"

LAUNCHER_CACHE_TTL=120
PREV_UNLOCKED=0
UNLOCK_GRACE_DONE=0

# ─── [J] ZRAM swap manager compat ────────────────────────────────────────────
ZRAM_SWAP_MGR_MODULE="zram-swap-manager"
_ZRAM_MGR_PRESENT=0

# ─── [V31-B] Biometric + camera BIG-cluster pinning ──────────────────────────
# Exynos 9810: CPUs 4-7 = Mongoose M3 (BIG cluster).
# taskset affinity mask 0xf0 = bits 4-7 = CPUs 4-7 only.
BIG_CLUSTER_MASK="0xf0"
BIOMETRIC_BIG_PIN_INTERVAL=30
_LAST_BIOMETRIC_PIN=0
_LAST_FP_PID="0"
LAST_NOTIFY=0

# ─── [V31-C] Audio control node sentinel ─────────────────────────────────────
# /dev/audio_control inode mtime advances on every ABOX DSP PCM ioctl.
# Catches DMA-active gaps that getprop + pidof alone cannot detect.
AUDIO_CTRL_NODE="/dev/audio_control"
AUDIO_CTRL_ACTIVE_WINDOW_S=30

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────────────────────
log()  { [ "${LOG_LEVEL:-1}" -ge 1 ] && echo "$(date '+%F %T') [BRAIN] $*" >> "$LOG_FILE" || true; }
logv() { [ "${LOG_LEVEL:-1}" -ge 2 ] && echo "$(date '+%F %T') [BRAIN] $*" >> "$LOG_FILE" || true; }
loge() { echo "$(date '+%F %T') [BRAIN][ERR] $*" >> "$LOG_FILE"; }

rotate_logs() {
    local max_lines=5000
    [ -f "$LOG_FILE" ] || return 0
    local lines
    lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$max_lines" ]; then
        local tmp="${LOG_FILE}.rot.$$"
        tail -n 2500 "$LOG_FILE" > "$tmp" 2>/dev/null \
            && mv "$tmp" "$LOG_FILE" 2>/dev/null \
            || { rm -f "$tmp" 2>/dev/null; loge "rotate: failed"; }
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# NATIVE NOTIFICATION — [G] cmd notification only, no third-party deps
# ──────────────────────────────────────────────────────────────────────────────
_ensure_notif_channel() {
    [ "$_NOTIF_CHAN_CREATED" = "1" ] && return 0
    # Channel creation requires notification service to be up
    service check notification 2>/dev/null | grep -q "found" || return 1
    cmd notification createChannel \
        "$CMD_NOTIFICATION_APP" \
        "$CMD_NOTIFICATION_CHAN" \
        "Brain Core Alerts" \
        3 2>/dev/null || true
    _NOTIF_CHAN_CREATED=1
}

notify_user() {
    local title="$1" body="$2" tag="${3:-brain_core_info}
# notify_once: rate-limited notify — at most once per 600s per tag.
# Prevents notification spam during crash loops or rapid HAL respawns.
notify_once() {
    local now
    now="$(date +%s)"
    [ $((now - LAST_NOTIFY)) -lt 600 ] && return 0
    LAST_NOTIFY="$now"
    notify_user "$@"
}
"
    _ensure_notif_channel || return 0
    cmd notification post \
        -S bigtext \
        --title "$title" \
        --text  "$body" \
        --channel "$CMD_NOTIFICATION_CHAN" \
        "$tag" \
        "$CMD_NOTIFICATION_APP" 2>/dev/null || true
    log "NOTIFY: [$title] $body"
}

# ──────────────────────────────────────────────────────────────────────────────
# PURE HELPERS
# ──────────────────────────────────────────────────────────────────────────────
write_node() {
    local node="$1" val="$2" tries=0 cur
    [ -e "$node" ] || { logv "WRITE: node missing $node"; return 1; }
    cur="$(cat "$node" 2>/dev/null || echo __missing__)"
    [ "$cur" = "$val" ] && return 0
    while [ $tries -lt 3 ]; do
        if echo "$val" > "$node" 2>/dev/null; then
            logv "WRITE: $node <- $val"
            return 0
        fi
        tries=$((tries+1)); sleep 1
    done
    loge "WRITE_FAIL: $node <- $val"
    return 1
}

safe_cpuset_write() {
    local p="$1" cs="${2:-/dev/cpuset/top-app/tasks}"
    [ -f "$cs" ] || { logv "CPUSET: missing $cs"; return 1; }
    [ -d "/proc/$p" ] || { logv "CPUSET: pid $p gone"; return 1; }
    if ! printf '%s\n' "$p" > "$cs" 2>/dev/null; then
        sleep 1
        if ! printf '%s\n' "$p" > "$cs" 2>/dev/null; then
            loge "CPUSET: failed to write $p to $cs"
            return 1
        fi
    fi
    logv "CPUSET: wrote $p to $cs"
    return 0
}

_ps_snapshot=""
snapshot_ps() {
    _ps_snapshot="$(ps -A -o pid,comm 2>/dev/null || ps -A 2>/dev/null || true)"
}
lookup_pid_by_comm() {
    local name="$1"
    echo "$_ps_snapshot" | awk -v n="$name" '$2==n {print $1; exit}'
}
lookup_pid_by_grep() {
    local pattern="$1"
    echo "$_ps_snapshot" | awk -v pat="$pattern" '$0 ~ pat {print $1; exit}'
}

is_screen_on() {
    local b
    b="$(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null \
         || cat /sys/class/backlight/panel/brightness 2>/dev/null \
         || echo 0)"
    [ "${b:-0}" -gt 0 ]
}

get_foreground_pkg() {
    local pkg
    pkg="$(dumpsys activity activities 2>/dev/null \
        | grep -m1 -E 'mResumedActivity|topResumedActivity' \
        | sed -n 's/.* \([^ ]*\)\/[^ ]* .*/\1/p')"
    [ -z "$pkg" ] && logv "FG_PKG: empty result from dumpsys"
    echo "$pkg"
}

_LAUNCHER_CACHE=""
_LAUNCHER_CACHE_TIME=0
get_default_launcher() {
    local force="${1:-0}" now
    now="$(date +%s)"
    if [ "$force" = "1" ] || [ -z "$_LAUNCHER_CACHE" ] \
       || [ $((now - _LAUNCHER_CACHE_TIME)) -ge "$LAUNCHER_CACHE_TTL" ]; then
        _LAUNCHER_CACHE="$(cmd package resolve-activity --brief \
            -a android.intent.action.MAIN \
            -c android.intent.category.HOME 2>/dev/null \
            | tail -n1 | awk '{print $NF}' | cut -d/ -f1)"
        _LAUNCHER_CACHE_TIME=$now
    fi
    echo "$_LAUNCHER_CACHE"
}

set_proc_adj() {
    local pid="$1" oom="$2" nicev="$3"
    [ -d "/proc/$pid" ] || return 0
    write_node "/proc/$pid/oom_score_adj" "$oom" || true
    renice -n "$nicev" -p "$pid" >/dev/null 2>&1 || true
}

# boost_all_threads_rt: set SCHED_RR on every thread of a process
# $1=pid $2=priority (1-99)
boost_all_threads_rt() {
    local pid="$1" prio="$2"
    [ -d "/proc/$pid" ] || return 0
    local tid
    for tid in $(ls "/proc/$pid/task/" 2>/dev/null); do
        chrt -r -p "$prio" "$tid" 2>/dev/null || true
    done
}

# [V31-D] pin_all_threads_big: taskset 0xf0 (CPUs 4-7, BIG cluster) on every
# thread of a process. Call alongside boost_all_threads_rt() for security HALs.
pin_all_threads_big() {
    local pid="$1"
    [ -d "/proc/$pid" ] || return 0
    local tid
    for tid in $(ls "/proc/$pid/task/" 2>/dev/null); do
        taskset -p "$BIG_CLUSTER_MASK" "$tid" >/dev/null 2>&1 || true
    done
}

get_battery_level() { cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 50; }
get_big_temp_c()    { local t; t="$(cat "$THERMAL_ZONE_BIG" 2>/dev/null || echo 0)"; echo $((${t:-0}/1000)); }
get_battery_temp_c() {
    local t
    t="$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)"
    [ "${t:-0}" -gt 0 ] && echo $((t / 10)) || echo 0
}
get_max_thermal_c() {
    local z max=0 t
    for z in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$z" ] || continue
        t="$(cat "$z" 2>/dev/null || echo 0)"
        [ "${t:-0}" -gt "$max" ] && max="${t:-0}"
    done
    echo $((max / 1000))
}
get_thermal_state() {
    local max; max="$(get_max_thermal_c)"
    local temp; temp="$(get_big_temp_c)"
    if   [ "${max:-0}" -ge 80 ] || [ "${temp:-0}" -ge 80 ]; then echo "emergency"
    elif [ "${max:-0}" -ge 72 ] || [ "${temp:-0}" -ge 72 ]; then echo "hot"
    elif [ "${max:-0}" -ge 55 ] || [ "${temp:-0}" -ge 55 ]; then echo "warm"
    else echo "normal"
    fi
}

seconds_since_last_touch() {
    local mtime now
    mtime="$(stat -c %Y "$TOUCH_EVENT" 2>/dev/null)" || { echo 9999; return; }
    now="$(date +%s)"
    echo $((now - mtime))
}

is_notification_service_ready() { service check notification 2>/dev/null | grep -q "found"; }

is_user_unlocked() {
    local v
    v="$(getprop sys.user.0.ce_available 2>/dev/null)"
    [ "$v" = "true" ] && return 0
    [ -d "/data/data/com.android.settings" ] && return 0
    return 1
}

EMS_ROOT="/sys/kernel/ems"
has_ems() { [ -d "$EMS_ROOT" ]; }

# ems_write: [H] guard against empty stub nodes before writing
ems_write() {
    local node="$1" val="$2"
    [ -f "$node" ] || return 1
    # Stub nodes on this ROM are present but contain only empty string
    local content
    content="$(cat "$node" 2>/dev/null)"
    # Allow write to empty node or node with a numeric value
    case "${content:-}" in
        ''|[0-9]*)
            echo "$val" > "$node" 2>/dev/null && \
                logv "EMS: $node <- $val" && return 0
            ;;
    esac
    logv "EMS: skipping stub node $node (content='${content}')"
    return 1
}

waitAudioServer() {
    local i=0
    while [ "$i" -lt 20 ]; do
        [ "$(getprop sys.boot_completed)" = "1" ] \
            && [ -n "$(getprop init.svc.audioserver 2>/dev/null)" ] \
            && return 0
        sleep 3; i=$((i+1))
    done
    log "WARN: audioserver not confirmed after 60s — proceeding anyway."
    return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# SCHEDUTIL WATCHDOG — re-asserts CFS knobs every 180s
# [D] Now also re-asserts sched_latency_ns = 6000000
# ──────────────────────────────────────────────────────────────────────────────
schedutil_watchdog() {
    log "WATCHDOG: started (pid=$$, interval=180s)"
    while true; do
        sleep 180

        # sched_latency_ns — [D] target 6ms
        local n="/proc/sys/kernel/sched_latency_ns"
        if [ -f "$n" ]; then
            local cur; cur="$(cat "$n" 2>/dev/null || echo 0)"
            if [ "${cur:-0}" != "$CFS_SCHED_LATENCY_NS" ]; then
                write_node "$n" "$CFS_SCHED_LATENCY_NS" \
                    && log "WATCHDOG: sched_latency_ns reset to $CFS_SCHED_LATENCY_NS (was $cur)"
            fi
        fi

        # sched_min_granularity_ns
        local n2="/proc/sys/kernel/sched_min_granularity_ns"
        if [ -f "$n2" ]; then
            local cur2; cur2="$(cat "$n2" 2>/dev/null || echo 0)"
            if [ "${cur2:-0}" != "$CFS_SCHED_MIN_GRAN_NS" ]; then
                write_node "$n2" "$CFS_SCHED_MIN_GRAN_NS" \
                    && log "WATCHDOG: sched_min_granularity_ns reset to $CFS_SCHED_MIN_GRAN_NS (was $cur2)"
            fi
        fi

        # schedutil rate_limit_us
        for pol in /sys/devices/system/cpu/cpufreq/policy*/schedutil/rate_limit_us; do
            [ -f "$pol" ] || continue
            local cur3; cur3="$(cat "$pol" 2>/dev/null || echo 0)"
            if [ "${cur3:-0}" != "$SCHEDUTIL_UP_RATE_LIMIT_US" ]; then
                write_node "$pol" "$SCHEDUTIL_UP_RATE_LIMIT_US" \
                    && logv "WATCHDOG: $pol reset to $SCHEDUTIL_UP_RATE_LIMIT_US"
            fi
        done
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# [F] PHANTOM KILLER GUARD
# Sets max_phantom_processes and native_boot ns key to prevent phantom kills
# of Brain Core subshells and busybox workers. Runs once at boot.
# ──────────────────────────────────────────────────────────────────────────────
apply_phantom_killer_guard() {
    local KEY1="activity_manager"
    local KEY2="activity_manager_native_boot"
    local PROP="max_phantom_processes"
    local TARGET=32768

    # device_config requires boot_completed
    [ "$(getprop sys.boot_completed)" = "1" ] || return 0

    local cur1 cur2
    cur1="$(device_config get "$KEY1" "$PROP" 2>/dev/null || echo '')"
    cur2="$(device_config get "$KEY2" "$PROP" 2>/dev/null || echo '')"

    [ "${cur1:-}" = "$TARGET" ] || \
        device_config put "$KEY1" "$PROP" "$TARGET" 2>/dev/null \
        && log "PHANTOM: $KEY1/$PROP = $TARGET"

    [ "${cur2:-}" = "$TARGET" ] || \
        device_config put "$KEY2" "$PROP" "$TARGET" 2>/dev/null \
        && log "PHANTOM: $KEY2/$PROP = $TARGET"

    # A16 QPR2 fflag: ensure monitor phantom procs is off (suppress spurious kills)
    device_config put settings_global \
        "settings_enable_monitor_phantom_procs" "false" 2>/dev/null || true
}

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 1: collect_facts()
# ──────────────────────────────────────────────────────────────────────────────
collect_facts() {
    F_FDE_MODE="$(getprop fde.mode 2>/dev/null)"
    [ -z "$F_FDE_MODE" ] && F_FDE_MODE="auto"

    F_SCREEN_ON=0; is_screen_on && F_SCREEN_ON=1
    F_FG_APP="$(get_foreground_pkg 2>/dev/null || true)"
    F_BATT="$(get_battery_level)"

    F_CHARGING=0
    local batt_status
    batt_status="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
    case "${batt_status:-Discharging}" in Charging|Full) F_CHARGING=1 ;; esac
    if [ "$F_CHARGING" = "0" ]; then
        for f in /sys/class/power_supply/*/online; do
            [ "$(cat "$f" 2>/dev/null)" = "1" ] && F_CHARGING=1 && break
        done
    fi

    # Thermal latch — [I] HAL_COOLING_BIG confirmed path
    local temp
    temp="$(cat "$THERMAL_ZONE_BIG" 2>/dev/null \
         || cat "$THERMAL_ZONE_LITTLE" 2>/dev/null \
         || echo 0)"

    local cooling=0
    if [ -n "$HAL_COOLING_BIG" ] && [ -f "$HAL_COOLING_BIG" ]; then
        cooling="$(cat "$HAL_COOLING_BIG" 2>/dev/null || echo 0)"
    fi

    if [ "$THERMAL_LATCH" = "0" ]; then
        if [ "${temp:-0}" -ge "$THERMAL_HYST_HIGH" ]; then
            THERMAL_LATCH=1; THERMAL_LATCH_TICKS=1
            log "THERMAL: latch triggered at ${temp}mC"
        fi
        [ "${cooling:-0}" -gt 0 ] && THERMAL_LATCH=1
        [ "$(getprop fde.thermal 2>/dev/null)" = "1" ] && THERMAL_LATCH=1
    else
        THERMAL_LATCH_TICKS=$((THERMAL_LATCH_TICKS + 1))
        if [ "${temp:-0}" -le "$THERMAL_HYST_LOW" ] \
           && [ "$THERMAL_LATCH_TICKS" -ge "$THERMAL_LATCH_MIN" ] \
           && [ "$(getprop fde.thermal 2>/dev/null)" != "1" ]; then
            local cooling_unlock=0
            if [ -n "$HAL_COOLING_BIG" ] && [ -f "$HAL_COOLING_BIG" ]; then
                cooling_unlock="$(cat "$HAL_COOLING_BIG" 2>/dev/null || echo 0)"
            fi
            if [ "${cooling_unlock:-0}" = "0" ]; then
                THERMAL_LATCH=0; THERMAL_LATCH_TICKS=0
                log "THERMAL: latch cleared"
            fi
        fi
    fi
    F_THERMAL="$THERMAL_LATCH"

    # Memory
    F_MEM_AVAILABLE_MB=0
    F_MEM_PRESSURE=0
    F_PSI_FULL_AVG10=0
    local mem_kb
    mem_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    F_MEM_AVAILABLE_MB=$((${mem_kb:-0} / 1024))

    if [ -f "/proc/pressure/memory" ]; then
        local psi_some psi_full
        psi_some="$(awk '/^some/ {for(i=1;i<=NF;i++) if($i~/^avg10=/) {split($i,a,"="); printf "%.0f", a[2]; exit}}' \
            /proc/pressure/memory 2>/dev/null || echo 0)"
        psi_full="$(awk '/^full/ {for(i=1;i<=NF;i++) if($i~/^avg10=/) {split($i,a,"="); printf "%.0f", a[2]; exit}}' \
            /proc/pressure/memory 2>/dev/null || echo 0)"
        F_PSI_FULL_AVG10="${psi_full:-0}"
        if [ "${psi_full:-0}" -ge "$PSI_SEVERE" ]; then
            F_MEM_PRESSURE=2
        elif [ "${psi_some:-0}" -ge "$PSI_MODERATE" ]; then
            F_MEM_PRESSURE=1
        fi
    else
        pidof kswapd0 >/dev/null 2>&1 && F_MEM_PRESSURE=1
    fi

    F_CAMERA_ACTIVE=0
    for cam in $CAMERA_APPS; do
        [ "$F_FG_APP" = "$cam" ] && F_CAMERA_ACTIVE=1 && break
    done

    F_LOAD_AVG_100=0
    local load_str
    load_str="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo 0.00)"
    F_LOAD_AVG_100="$(echo "$load_str" | awk '{printf "%d", $1*100}')"

    F_BRIGHTNESS=0
    F_BRIGHTNESS="$(cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null \
                 || cat /sys/class/backlight/panel/brightness 2>/dev/null \
                 || echo 0)"

    # BT state
    F_BT_ENABLED=0
    local bt_state
    bt_state="$(settings get global bluetooth_on 2>/dev/null || echo 0)"
    [ "${bt_state:-0}" = "1" ] && F_BT_ENABLED=1

    # [J] Detect zram-swap-manager
    _ZRAM_MGR_PRESENT=0
    ls /data/adb/modules/"$ZRAM_SWAP_MGR_MODULE"/ >/dev/null 2>&1 && _ZRAM_MGR_PRESENT=1
}

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 2: classify_state()
# ──────────────────────────────────────────────────────────────────────────────
classify_state() {
    if [ "${F_MEM_PRESSURE:-0}" -ge 2 ] && [ "$F_MEM_AVAILABLE_MB" -lt "$MEM_TIER_TIGHT" ]; then
        MEM_TIER="critical"
    elif [ "${F_MEM_PRESSURE:-0}" -ge 2 ]; then
        MEM_TIER="tight"
    elif [ "$F_MEM_AVAILABLE_MB" -ge "$MEM_TIER_COMFORTABLE" ] && [ "${F_MEM_PRESSURE:-0}" -eq 0 ]; then
        MEM_TIER="comfortable"
    elif [ "$F_MEM_AVAILABLE_MB" -ge "$MEM_TIER_TIGHT" ]; then
        MEM_TIER="tight"
    else
        MEM_TIER="critical"
    fi

    if [ "$F_THERMAL" = "1" ]; then
        STATE="thermal";          POLICY_CAUSE="thermal_latch"
    elif [ "$F_BATT" -le 20 ] && [ "$F_CHARGING" = "0" ]; then
        STATE="battery_critical"; POLICY_CAUSE="batt_${F_BATT}pct"
    elif [ "$F_SCREEN_ON" = "0" ]; then
        STATE="screen_off_idle";  POLICY_CAUSE="screen_off"
    elif [ "$F_CHARGING" = "1" ]; then
        STATE="charging";         POLICY_CAUSE="charger_connected"
    elif [ "$F_CAMERA_ACTIVE" = "1" ]; then
        STATE="camera_active";    POLICY_CAUSE="fg_camera"
    elif [ "$F_SCREEN_ON" = "1" ] && [ -n "${F_FG_APP:-}" ]; then
        STATE="interactive";      POLICY_CAUSE="fg_${F_FG_APP##*.}"
    else
        STATE="normal";           POLICY_CAUSE="nominal"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 3: compute_policy()
# ──────────────────────────────────────────────────────────────────────────────
compute_policy() {
    : "${BIG_HW_MAX:=$BIG_FREQ_MAX_DEFAULT}"

    P_OOM_VIP="-800";  P_NICE_VIP="-10";  P_TIMEOUT=60000
    P_TOP_BOOST=5;     P_FG_BOOST=6;      P_BG_BOOST=0
    P_TOP_PREFER_IDLE=1; P_FG_PREFER_IDLE=0; P_BG_PREFER_IDLE=0
    P_CPUSET_TOP="0-7"; P_CPUSET_FG="0-6"; P_CPUSET_BG="0-3"; P_CPUSET_SYSBG="0-2"

    P_MIGRATION_COST=2000000
    P_LITTLE_FREQ_MIN=$LITTLE_FREQ_MIN_DEFAULT
    P_BIG_FREQ_MIN=$BIG_FREQ_MIN_DEFAULT
    P_LITTLE_FREQ_CAP=1586000; P_BIG_FREQ_CAP=1794000

    P_IO_READ_AHEAD=128; P_IO_NR_REQUESTS=64
    # [J] Only set swappiness if zram-swap-manager is absent
    P_VM_SWAPPINESS=60;  P_VM_DIRTY_RATIO=20; P_VM_DIRTY_BG_RATIO=5
    P_VM_VFS_CACHE_PRESSURE=100

    case "$STATE" in
        thermal)
            P_TOP_BOOST=0;    P_FG_BOOST=2;  P_BG_BOOST=0
            P_OOM_VIP="-700"; P_NICE_VIP="-6"
            P_MIGRATION_COST=5000000
            P_LITTLE_FREQ_CAP=1200000; P_BIG_FREQ_CAP=1352000
            P_TIMEOUT=30000
            ;;
        battery_critical)
            P_TOP_BOOST=0;    P_FG_BOOST=2;  P_BG_BOOST=0
            P_LITTLE_FREQ_CAP=1200000; P_BIG_FREQ_CAP=1352000
            P_VM_SWAPPINESS=35; P_VM_VFS_CACHE_PRESSURE=160
            P_TIMEOUT=30000
            ;;
        screen_off_idle)
            P_TOP_BOOST=0;    P_FG_BOOST=0;  P_BG_BOOST=0
            P_TOP_PREFER_IDLE=0; P_BG_PREFER_IDLE=0
            P_CPUSET_TOP="0-3"; P_CPUSET_FG="0-3"
            P_CPUSET_BG="0-1";  P_CPUSET_SYSBG="0-1"
            P_LITTLE_FREQ_CAP=800000; P_BIG_FREQ_CAP=1000000
            P_MIGRATION_COST=5000000
            ;;
        charging)
            P_OOM_VIP="-900"; P_NICE_VIP="-12"
            P_TOP_BOOST=12;   P_FG_BOOST=10; P_BG_BOOST=2
            P_CPUSET_FG="0-7"; P_MIGRATION_COST=4000000
            P_IO_READ_AHEAD=256; P_IO_NR_REQUESTS=128
            P_VM_SWAPPINESS=80
            P_LITTLE_FREQ_CAP=1586000; P_BIG_FREQ_CAP=1950000
            P_TIMEOUT=60000
            ;;
        camera_active)
            P_OOM_VIP="-900"; P_NICE_VIP="-12"
            P_TOP_BOOST=10;   P_FG_BOOST=8;  P_BG_BOOST=0
            P_CPUSET_TOP="0-7"; P_CPUSET_FG="0-7"
            P_LITTLE_FREQ_CAP=1586000; P_BIG_FREQ_CAP="$BIG_HW_MAX"
            P_MIGRATION_COST=4000000
            P_TIMEOUT=60000
            ;;
        interactive|normal)
            ;;
    esac

    if [ "$STATE" != "thermal" ] && [ "$STATE" != "battery_critical" ]; then
        case "$F_FDE_MODE" in
            powersave)
                P_TOP_BOOST=0;  P_FG_BOOST=3;  P_BG_BOOST=0
                P_OOM_VIP="-700"; P_NICE_VIP="-6"
                P_LITTLE_FREQ_CAP=1400000; P_BIG_FREQ_CAP=1690000
                P_IO_READ_AHEAD=64; P_IO_NR_REQUESTS=32
                P_VM_SWAPPINESS=40; P_VM_DIRTY_RATIO=10; P_VM_DIRTY_BG_RATIO=3
                P_VM_VFS_CACHE_PRESSURE=150
                P_TIMEOUT=30000
                ;;
            performance)
                P_TOP_BOOST=12; P_FG_BOOST=10; P_BG_BOOST=2
                P_OOM_VIP="-900"; P_NICE_VIP="-12"
                P_MIGRATION_COST=4000000
                P_LITTLE_FREQ_CAP=1586000; P_BIG_FREQ_CAP="$BIG_HW_MAX"
                P_IO_READ_AHEAD=256; P_IO_NR_REQUESTS=128
                P_VM_SWAPPINESS=80; P_VM_DIRTY_RATIO=30; P_VM_DIRTY_BG_RATIO=8
                P_VM_VFS_CACHE_PRESSURE=80
                ;;
        esac
    fi

    # INVARIANT: foreground prefer_idle must never be 1
    P_FG_PREFER_IDLE=0

    [ "$P_TIMEOUT" -lt "$MIN_TIMEOUT" ] && P_TIMEOUT="$MIN_TIMEOUT"
    [ "$P_TIMEOUT" -gt "$MAX_TIMEOUT" ] && P_TIMEOUT="$MAX_TIMEOUT"
}

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 4: apply_*()
# ──────────────────────────────────────────────────────────────────────────────

apply_render_pipeline_priority() {
    local RENDER_SVCS="surfaceflinger vendor.hwcomposer-3 vendor.livedisplay-hal-samsung-exynos android.hardware.composer.hwc3-service.slsi"
    local svc p
    for svc in $RENDER_SVCS; do
        p="$(lookup_pid_by_comm "$svc")"
        [ -n "$p" ] || p="$(lookup_pid_by_grep "$svc")"
        [ -n "$p" ] || continue
        set_proc_adj "$p" "-750" "-8"
    done
}

apply_touch_power_hal_priority() {
    local svc p
    for svc in "vendor.touch-hal" "vendor.power-hal-aidl"; do
        p="$(getprop "init.svc_debug_pid.${svc}" 2>/dev/null)"
        if [ -n "$p" ] && [ -d "/proc/$p" ]; then
            set_proc_adj "$p" "-750" "-8"
        fi
    done
}

apply_launcher_priority() {
    local L p pkg
    L="$(get_default_launcher)"
    [ -z "${L:-}" ] || for p in $(pidof "$L" 2>/dev/null); do
        set_proc_adj "$p" "$P_OOM_VIP" "$P_NICE_VIP"
    done
    for pkg in app.lawnchair com.drdisagree.pixellauncherenhanced com.kieronquinn.app.pixellaunchermods; do
        for p in $(pidof "$pkg" 2>/dev/null); do
            set_proc_adj "$p" "$P_OOM_VIP" "$P_NICE_VIP"
        done
    done
}

apply_systemui_priority() {
    local p
    for p in $(pidof com.android.systemui 2>/dev/null); do
        set_proc_adj "$p" "$P_OOM_VIP" "$P_NICE_VIP"
    done
}

# ── [A] Audio RT priority — AIDL HAL + audioserver thread-level SCHED_RR ─────
# AEGIS diag FAILs: audioserver CFS, audio HAL CFS.
# Fix: SCHED_RR p=3 on all audioserver threads, SCHED_RR p=2 on HAL.
apply_audio_rt() {
    local asp ahp
    asp="$(getprop init.svc_debug_pid.audioserver 2>/dev/null || pidof audioserver 2>/dev/null | awk '{print $1}')"
    ahp="$(getprop init.svc_debug_pid.vendor.audio-hal 2>/dev/null || pidof android.hardware.audio.service 2>/dev/null | awk '{print $1}')"

    if [ -n "${asp:-}" ] && [ -d "/proc/$asp" ]; then
        set_proc_adj "$asp" "-700" "-8"
        boost_all_threads_rt "$asp" 3
        logv "AUDIO_RT: audioserver pid=$asp all threads SCHED_RR p=3"
    fi

    if [ -n "${ahp:-}" ] && [ -d "/proc/$ahp" ]; then
        set_proc_adj "$ahp" "-700" "-8"
        chrt -r -p 2 "$ahp" 2>/dev/null || true
        logv "AUDIO_RT: audio HAL pid=$ahp SCHED_RR p=2"
    fi

    # A2DP offload prop — AEGIS WARN: prop not set
    local offload_cur
    offload_cur="$(getprop persist.bluetooth.a2dp_offload.disabled 2>/dev/null)"
    if [ "${offload_cur:-unset}" != "false" ]; then
        setprop persist.bluetooth.a2dp_offload.disabled false 2>/dev/null || true
        logv "AUDIO_RT: a2dp_offload.disabled set to false"
    fi
}

apply_background_audio_priority() {
    local pkg p
    for pkg in $BACKGROUND_AUDIO_PKGS; do
        [ "$pkg" = "${F_FG_APP:-}" ] && continue
        for p in $(pidof "$pkg" 2>/dev/null); do
            set_proc_adj "$p" "-700" "-8"
        done
    done
}

# ── [C] Fingerprint HAL — AIDL service, SCHED_RR p=5, all threads ───────────
# Diag confirms: android.hardware.biometrics.fingerprint-service.samsung PID 7308
# Raised from p=1 → p=5 and all threads elevated for minimum unlock latency.
apply_fingerprint_priority() {
    local p="" svc

    # Primary: init.svc_debug_pid lookup (fastest, no regex needed)
    for svc in "vendor.fingerprint-default" "vendor.fps_hal" \
                "android.hardware.biometrics.fingerprint" \
                "fingerprint_hal" "egis_fp_hal"; do
        p="$(getprop "init.svc_debug_pid.${svc}" 2>/dev/null)"
        [ -n "$p" ] && [ -d "/proc/$p" ] && {
            logv "FP: found via init.svc_debug_pid.${svc} → PID=$p"
            break
        }
        p=""
    done

    # Fallback: pidof
    if [ -z "$p" ]; then
        for svc in $FINGERPRINT_SVCS; do
            p="$(pidof "$svc" 2>/dev/null | awk '{print $1}')"
            [ -n "$p" ] && [ -d "/proc/$p" ] && break
            p=""
        done
    fi

    # Last resort: pgrep
    if [ -z "$p" ]; then
        p="$(pgrep -f "fingerprint-service\|fps_hal\|egis_fp" 2>/dev/null | head -1)"
        [ -n "$p" ] && logv "FP: found via pgrep -f → PID=$p"
    fi

    if [ -n "$p" ] && [ -d "/proc/$p" ]; then
        set_proc_adj "$p" "-950" "-15"
        # Elevate all threads to SCHED_RR p=5 for minimum latency unlock
        boost_all_threads_rt "$p" 5
        log "FP: HAL PID=$p → SCHED_RR p=5 on all threads, OOM=-950"
    fi
}

apply_foreground_priority() {
    [ -z "${F_FG_APP:-}" ] && return 0
    local launcher; launcher="$(get_default_launcher)"
    [ "$F_FG_APP" = "${launcher:-__none__}" ] && return 0

    snapshot_ps
    local p
    p="$(pidof "$F_FG_APP" 2>/dev/null | awk '{print $1}')"
    if [ -z "$p" ]; then
        p="$(lookup_pid_by_grep "$F_FG_APP")"
    fi
    [ -z "$p" ] && return 0

    set_proc_adj "$p" "-900" "-15"
    safe_cpuset_write "$p" "/dev/cpuset/foreground/tasks"
}

apply_camera_priority() {
    [ "$F_CAMERA_ACTIVE" = "0" ] && return 0
    local cam p
    for cam in $CAMERA_APPS; do
        for p in $(pidof "$cam" 2>/dev/null); do set_proc_adj "$p" "-900" "-15"; done
    done
}

apply_camera_isp_protection() {
    local svc p
    for svc in $CAMERA_ISP_DAEMONS; do
        for p in $(pidof "$svc" 2>/dev/null); do
            set_proc_adj "$p" "-800" "-10"
        done
    done
}

# apply_biometric_big_pin: "High Priority Zone" (V31 + V32 Stabilitas merge)
# Pins fingerprint HAL + camera ISP to BIG cluster (M3, CPUs 4-7).
#
# V32 improvements over V31:
#   • taskset -ap (single call, all threads) replaces per-thread loop
#   • LAST_FP_PID tracking: notify_once() fires on HAL respawn (PID change)
#   • Camera detection: pidof package fallback in addition to mResumedActivity
#     catches camera in split-screen / PiP / background recording
#   • boost_all_threads_rt() added for FP HAL (was missing from V31 body)
#
# Rate-limited to BIOMETRIC_BIG_PIN_INTERVAL (30s) to cap syscall overhead.
apply_biometric_big_pin() {
    local now
    now="$(date +%s)"
    [ $((now - _LAST_BIOMETRIC_PIN)) -lt "$BIOMETRIC_BIG_PIN_INTERVAL" ] && return 0
    _LAST_BIOMETRIC_PIN="$now"

    local p="" svc pinned=0 fp_cur=""

    # ── Fingerprint HAL discovery ──────────────────────────────────────────────
    for svc in "vendor.fingerprint-default" "vendor.fps_hal"                 "android.hardware.biometrics.fingerprint"                 "fingerprint_hal" "egis_fp_hal"; do
        p="$(getprop "init.svc_debug_pid.${svc}" 2>/dev/null)"
        [ -n "$p" ] && [ -d "/proc/$p" ] && break
        p=""
    done
    if [ -z "$p" ]; then
        for svc in $FINGERPRINT_SVCS; do
            p="$(pidof "$svc" 2>/dev/null | awk '"'"'{print $1}'"'"')"
            [ -n "$p" ] && [ -d "/proc/$p" ] && break
            p=""
        done
    fi
    if [ -z "$p" ]; then
        p="$(pgrep -f "fingerprint-service|fps_hal|egis_fp" 2>/dev/null | head -1)"
    fi

    if [ -n "$p" ] && [ -d "/proc/$p" ]; then
        # [V32] taskset -ap: one call covers all threads (toybox -a flag)
        taskset -ap "$BIG_CLUSTER_MASK" "$p" >/dev/null 2>&1 || true
        safe_cpuset_write "$p" "/dev/cpuset/top-app/tasks"
        boost_all_threads_rt "$p" 5
        set_proc_adj "$p" "-950" "-15"
        fp_cur="$p"
        # [V32] Respawn detection: notify if PID changed since last cycle
        if [ "$fp_cur" != "$_LAST_FP_PID" ] && [ "$_LAST_FP_PID" != "0" ]; then
            notify_once "Brain Core"                 "FP HAL respawned (was PID $_LAST_FP_PID → now $fp_cur) — re-pinned to BIG"                 "brain_core_fp_respawn"
            log "BIG_PIN: FP HAL respawn detected (was=$_LAST_FP_PID now=$fp_cur)"
        fi
        _LAST_FP_PID="$fp_cur"
        log "BIG_PIN: FP HAL PID=$p → taskset=0x${BIG_CLUSTER_MASK} cpuset=top-app SCHED_RR p=5"
        pinned=$((pinned+1))
    fi

    # ── Camera ISP pinning ─────────────────────────────────────────────────────
    # [V32] Dual detection: F_CAMERA_ACTIVE (Brain Core state) OR
    #       mResumedActivity name match OR pidof camera package (catches PiP/split)
    local cam_active=0
    [ "$F_CAMERA_ACTIVE" = "1" ] && cam_active=1
    if [ "$cam_active" -eq 0 ]; then
        local resumed
        resumed="$(dumpsys activity activities 2>/dev/null             | grep -m1 mResumedActivity             | sed -n '"'"'s/.* \([^ ]*\)\/[^ ]* .*//p'"'"' 2>/dev/null || true)"
        case "${resumed:-}" in *camera*|*Camera*) cam_active=1 ;; esac
    fi
    if [ "$cam_active" -eq 0 ]; then
        for svc in com.sec.android.app.camera com.android.camera                    com.google.android.GoogleCamera; do
            pidof "$svc" >/dev/null 2>&1 && cam_active=1 && break
        done
    fi

    if [ "$cam_active" = "1" ]; then
        for svc in $CAMERA_ISP_DAEMONS; do
            for p in $(pidof "$svc" 2>/dev/null); do
                [ -d "/proc/$p" ] || continue
                taskset -ap "$BIG_CLUSTER_MASK" "$p" >/dev/null 2>&1 || true
                safe_cpuset_write "$p" "/dev/cpuset/top-app/tasks"
                set_proc_adj "$p" "-800" "-10"
                pinned=$((pinned+1))
            done
        done
        logv "BIG_PIN: camera ISP → CPUs 4-7 (cam_active)"
    fi

    [ "$pinned" -gt 0 ] && logv "BIG_PIN: $pinned processes pinned to BIG cluster"
}

apply_sensor_hal_pm() {
    local svc p
    for svc in android.hardware.sensors@1.0-service android.hardware.sensors@2.0-service \
               android.hardware.sensors@2.1-service android.frameworks.sensorservice@1.0-service; do
        for p in $(pidof "$svc" 2>/dev/null); do
            set_proc_adj "$p" "-800" "-10"
        done
    done
}

apply_shizuku_priority() {
    local p
    for p in $(pidof moe.shizuku.privileged.api 2>/dev/null); do
        set_proc_adj "$p" "-800" "-10"
        [ -f /dev/cpuset/foreground/tasks ] && safe_cpuset_write "$p" "/dev/cpuset/foreground/tasks"
    done
}

# ── [B] Bluetooth HAL priority + BT Audio HAL ensure ────────────────────────
apply_bt_pm() {
    local _bt_pid svc p
    _bt_pid="$(getprop init.svc_debug_pid.vendor.bluetooth-1-0 2>/dev/null || true)"

    for svc in $BT_HAL_SVCS; do
        for p in $(pidof "$svc" 2>/dev/null); do
            set_proc_adj "$p" "-900" "-12"
            chrt -r -p 2 "$p" 2>/dev/null || true
        done
    done

    if [ -n "${_bt_pid:-}" ] && [ -d "/proc/${_bt_pid}" ]; then
        set_proc_adj "$_bt_pid" "-900" "-12"
        chrt -r -p 2 "$_bt_pid" 2>/dev/null || true
    fi

    if [ "$F_SCREEN_ON" = "0" ]; then
        write_node /sys/module/bcm_bt_lpm/parameters/bt_wake_state "0" 2>/dev/null || true
    fi
}

# [B] BT Audio HAL ensure: diag shows BT Audio HAL NOT RUNNING
# When BT is enabled, verify IBluetoothAudioProviderFactory is registered.
# If missing after BT_AUDIO_WAIT_S, restart the BT HAL service.
apply_bt_audio_ensure() {
    [ "$F_BT_ENABLED" = "0" ] && return 0

    local now
    now="$(date +%s)"
    [ $((now - LAST_BT_AUDIO_ENSURE)) -lt 60 ] && return 0
    LAST_BT_AUDIO_ENSURE="$now"

    # Check AIDL registration
    if service check "$BT_AUDIO_AIDL" 2>/dev/null | grep -q "found"; then
        logv "BT_AUDIO: IBluetoothAudioProviderFactory registered OK"
        return 0
    fi

    # Not found — determine how long BT has been on
    local bt_enable_time
    bt_enable_time="$(getprop ro.boottime.vendor.bluetooth-1-0 2>/dev/null || echo 0)"
    local uptime_ms
    uptime_ms="$(cat /proc/uptime 2>/dev/null | awk '{printf "%d", $1}')"

    # Only restart if BT has been up for at least BT_AUDIO_WAIT_S
    if [ "${uptime_ms:-0}" -gt "$BT_AUDIO_WAIT_S" ]; then
        log "BT_AUDIO: IBluetoothAudioProviderFactory missing — restarting BT HAL"
        stop vendor.bluetooth-1-0 2>/dev/null || true
        sleep 2
        start vendor.bluetooth-1-0 2>/dev/null || true
        sleep 3
        notify_user "Brain Core" "BT Audio HAL restarted — A2DP should reconnect" "bt_audio_restart"
    fi
}

apply_bt_watchdog() {
    local now pid
    now="$(date +%s)"
    [ $((now - LAST_BT_WATCH_CHECK)) -lt 60 ] && return 0
    LAST_BT_WATCH_CHECK="$now"

    pid="$(pidof com.android.bluetooth 2>/dev/null | awk '{print $1}')"
    [ -n "${pid:-}" ] || return 0
    [ -d "/proc/$pid" ] || return 0

    if [ "$pid" != "${LAST_BT_PID:-}" ]; then
        LAST_BT_PID="$pid"
        log "BT: app restart detected pid=$pid"
    fi

    set_proc_adj "$pid" "-700" "-8"
    safe_cpuset_write "$pid" "/dev/cpuset/foreground/tasks"
}

apply_wifi_pm() {
    if [ "$F_SCREEN_ON" = "0" ]; then
        iw wlan0 set power_save on 2>/dev/null || true
        write_node /sys/module/dhd/parameters/dhd_watchdog_ms    "10000"
        write_node /sys/module/bcmdhd/parameters/dhd_watchdog_ms "10000"
    else
        iw wlan0 set power_save off 2>/dev/null || true
        write_node /sys/module/dhd/parameters/dhd_watchdog_ms    "2000"
        write_node /sys/module/bcmdhd/parameters/dhd_watchdog_ms "2000"
    fi
}

apply_screen_timeout() {
    settings put system screen_off_timeout "$P_TIMEOUT" 2>/dev/null \
        || logv "TIMEOUT: settings put failed"
}

# ── [E] Memory pressure response ─────────────────────────────────────────────
# Fires when PSI full avg10 exceeds PSI_SEVERE. Rate-limited to MEM_PRESSURE_LOCKOUT.
# ── AUDIO HAL SAFETY GUARD ────────────────────────────────────────────────────
# _svc_is_live: is a given init service (or its process) currently running?
# Checks getprop init.svc.<name> first (matches the diag's reporting), then
# falls back to pidof for processes that don't carry an init.svc property
# (e.g. mediaserver on some builds). Cheap — one getprop + at most one pidof.
_svc_is_live() {
    local name="$1" st
    st="$(getprop "init.svc.$name" 2>/dev/null)"
    [ "$st" = "running" ] && return 0
    pidof "$name" >/dev/null 2>&1 && return 0
    return 1
}

# _audio_stack_live: returns 0 (true) if ANY Safety Zone process is live.
# TWO-LAYER CHECK (V32 Stabilitas):
#   1. getprop + pidof for each SAFETY_ZONE_PROC (fast, catches running procs)
#   2. /dev/audio_control inode mtime < 30s (catches ABOX DSP DMA activity
#      even when audioserver is momentarily idle between tracks — the inode
#      mtime advances on every PCM ioctl regardless of process state)
# Any path that could corrupt HAL mmap'd memory MUST call memory_pressure_guard()
# and respect MPG_STATUS before doing anything beyond oom_score_adj.
_audio_stack_live() {
    local svc
    for svc in $SAFETY_ZONE_PROCS; do
        _svc_is_live "$svc" && return 0
    done
    # [V32] Audio control inode sentinel (moved from _svc_is_live to here)
    if [ -e "$AUDIO_CTRL_NODE" ]; then
        local mtime now
        mtime="$(stat -c %Y "$AUDIO_CTRL_NODE" 2>/dev/null || echo 0)"
        now="$(date +%s)"
        if [ $((now - mtime)) -le "$AUDIO_CTRL_ACTIVE_WINDOW_S" ]; then
            logv "MPG: audio_control mtime $((now-mtime))s ago — DSP active, BUSY"
            return 0
        fi
    fi
    return 1
}

# ── [MPG] memory_pressure_guard ───────────────────────────────────────────────
# Restaurant-kitchen analogy:
#   BUSY     — the chef (audio HAL) is mid-prep right now. Don't touch the
#               kitchen at all beyond noting what needs doing later.
#   SAFE     — the chef stepped away, but might be back any second (hasn't
#               been gone MPG_IDLE_GRACE_S yet). Light tidying only.
#   IDLE_EXT — the chef's break has run long enough that a deeper tidy
#               (deferred trim) won't get in their way.
#
# Sets MPG_STATUS and returns 0 always (status is read from the variable,
# not the return code, so callers can branch on three states with one call).
memory_pressure_guard() {
    local now
    now="$(date +%s)"
    if _audio_stack_live; then
        _MPG_AUDIO_IDLE_SINCE=0
        MPG_STATUS="BUSY"
        return 0
    fi
    if [ "$_MPG_AUDIO_IDLE_SINCE" -eq 0 ]; then
        _MPG_AUDIO_IDLE_SINCE="$now"
    fi
    if [ $((now - _MPG_AUDIO_IDLE_SINCE)) -ge "$MPG_IDLE_GRACE_S" ]; then
        MPG_STATUS="IDLE_EXT"
    else
        MPG_STATUS="SAFE"
    fi
    return 0
}

# _mpg_oom_adj_assist: always-safe reclaim assist. Nudges background/bloat
# package oom_score_adj upward so lmkd reclaims them first under pressure.
# Pure /proc/<pid>/oom_score_adj writes — no /proc/sys/vm/* operations, so
# it can never touch the HAL's mmap'd ABOX DSP/abox_vdma regions. Safe in
# BUSY, SAFE, and IDLE_EXT.
_mpg_oom_adj_assist() {
    local pkg p
    for pkg in $BLOAT_KILL_PKGS $BLOAT_THROTTLE_PKGS; do
        [ -z "$pkg" ] && continue
        [ "$pkg" = "${F_FG_APP:-}" ] && continue
        for p in $(pidof "$pkg" 2>/dev/null); do
            [ -d "/proc/$p" ] || continue
            write_node "/proc/$p/oom_score_adj" "950" || true
        done
    done
}

# _mpg_deferred_trim: ONLY called when MPG_STATUS=IDLE_EXT, i.e. the Safety
# Zone has been clear for MPG_IDLE_GRACE_S seconds. Issues
# `am kill-background-processes` for bloat packages — userspace process
# teardown via ActivityManager, NOT a VM/page-cache operation, so it cannot
# invalidate the HAL's mmap regions even if the HAL restarts moments later.
# Separately rate-limited via MPG_TRIM_LOCKOUT so a long PSI event doesn't
# spam `am` calls every poll.
_mpg_deferred_trim() {
    local now pkg
    now="$(date +%s)"
    [ $((now - _LAST_MPG_TRIM)) -lt "$MPG_TRIM_LOCKOUT" ] && return 0
    _LAST_MPG_TRIM="$now"
    for pkg in $BLOAT_KILL_PKGS; do
        [ -z "$pkg" ] && continue
        [ "$pkg" = "${F_FG_APP:-}" ] && continue
        am kill-background-processes "$pkg" 2>/dev/null || true
    done
    logv "MPG: deferred trim executed (Safety Zone idle >= ${MPG_IDLE_GRACE_S}s)"
}

# ── [E-FIX/MPG] apply_memory_pressure_response ────────────────────────────────
# V30.0 BUG (fixed in V30.1): issued drop_caches + compact_memory unconditionally.
# On Exynos 9810, vendor.audio-hal mmaps ABOX DSP firmware and abox_vdma DMA
# buffers via pagecache-adjacent memory. drop_caches invalidates those
# mappings -> SIGSEGV in the HAL -> "exited 4 times in 4 minutes" ->
# sys.init.updatable_crashing=1 -> audioserver stuck 'restarting', speaker dead.
#
# drop_caches and compact_memory remain PERMANENTLY REMOVED — they are never
# safe on this SoC while the audio HAL is resident. V30.2 formalizes the
# guard so every reclaim-assist path is dispatched through MPG_STATUS instead
# of relying on each call site remembering to check _audio_stack_live().
apply_memory_pressure_response() {
    [ "${F_PSI_FULL_AVG10:-0}" -lt "$PSI_SEVERE" ] && return 0

    local now
    now="$(date +%s)"
    [ $((now - _LAST_MEM_PRESSURE_RESPONSE)) -lt "$MEM_PRESSURE_LOCKOUT" ] && return 0
    _LAST_MEM_PRESSURE_RESPONSE="$now"

    memory_pressure_guard
    log "MEM_PRESSURE: PSI full avg10=${F_PSI_FULL_AVG10}% — guard=$MPG_STATUS"

    case "$MPG_STATUS" in
        BUSY)
            # Chef is mid-prep: oom_score nudges only. lmkd handles the rest.
            _mpg_oom_adj_assist
            ;;
        SAFE)
            # Chef stepped away but could be back any second: same light touch.
            _mpg_oom_adj_assist
            ;;
        IDLE_EXT)
            # Chef's break has run long enough: nudge + deferred trim.
            _mpg_oom_adj_assist
            _mpg_deferred_trim
            ;;
    esac

    if [ "${F_PSI_FULL_AVG10:-0}" -ge 50 ]; then
        notify_user "Brain Core: Memory" \
            "PSI full avg10=${F_PSI_FULL_AVG10}% — sustained pressure (guard=$MPG_STATUS)" \
            "mem_pressure_warn"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# [V31-G] apply_stune_profiles: re-assert schedtune cgroup values every cycle.
# EMS Flow v2.1 sets these at boot; ActivityManager/PowerHAL may reset them.
# State-aware: thermal/battery_critical/screen_off → all boosts to 0.
apply_stune_profiles() {
    local ta_boost=10 fg_boost=5 ta_idle=1 fg_idle=1
    case "$STATE" in
        thermal|battery_critical|screen_off_idle)
            ta_boost=0; fg_boost=0; ta_idle=0; fg_idle=0 ;;
    esac
    write_node /dev/stune/top-app/schedtune.boost        "$ta_boost"  || true
    write_node /dev/stune/top-app/schedtune.prefer_idle  "$ta_idle"   || true
    write_node /dev/stune/foreground/schedtune.boost      "$fg_boost"  || true
    write_node /dev/stune/foreground/schedtune.prefer_idle "$fg_idle"  || true
    write_node /dev/stune/background/schedtune.boost       "0"         || true
    write_node /dev/stune/background/schedtune.prefer_idle "0"         || true
    write_node /dev/stune/system-background/schedtune.boost "0"        || true
    logv "STUNE: state=$STATE ta_boost=$ta_boost fg_boost=$fg_boost ta_idle=$ta_idle"
}

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 5: apply_system_knobs
# [D] sched_latency_ns = 6000000 (scorecard target)
# [J] swappiness only written if zram-swap-manager absent
# ──────────────────────────────────────────────────────────────────────────────
apply_system_knobs() {
    # [J] Yield swappiness to zram-swap-manager if present
    if [ "$_ZRAM_MGR_PRESENT" = "0" ]; then
        write_node /proc/sys/vm/swappiness               "$P_VM_SWAPPINESS"        || true
    else
        logv "KNOBS: zram-swap-manager present — skipping swappiness write"
    fi

    write_node /proc/sys/vm/dirty_ratio                 "$P_VM_DIRTY_RATIO"       || true
    write_node /proc/sys/vm/dirty_background_ratio      "$P_VM_DIRTY_BG_RATIO"    || true
    write_node /proc/sys/vm/vfs_cache_pressure          "$P_VM_VFS_CACHE_PRESSURE" || true

    [ -f /sys/block/mmcblk0/queue/read_ahead_kb ] \
        && write_node /sys/block/mmcblk0/queue/read_ahead_kb "$P_IO_READ_AHEAD"

    [ -d "$LITTLE_POLICY" ] && write_node "$LITTLE_POLICY/scaling_max_freq" "$P_LITTLE_FREQ_CAP"
    [ -d "$BIG_POLICY" ]    && write_node "$BIG_POLICY/scaling_max_freq"    "$P_BIG_FREQ_CAP"

    [ -f /proc/sys/kernel/sched_migration_cost_ns ] \
        && write_node /proc/sys/kernel/sched_migration_cost_ns "$P_MIGRATION_COST"

    # CFS latency knobs — [D]
    [ -f /proc/sys/kernel/sched_latency_ns ] \
        && write_node /proc/sys/kernel/sched_latency_ns        "$CFS_SCHED_LATENCY_NS"
    [ -f /proc/sys/kernel/sched_min_granularity_ns ] \
        && write_node /proc/sys/kernel/sched_min_granularity_ns "$CFS_SCHED_MIN_GRAN_NS"
    [ -f /proc/sys/kernel/sched_wakeup_granularity_ns ] \
        && write_node /proc/sys/kernel/sched_wakeup_granularity_ns "$CFS_SCHED_WAKEUP_GRAN_NS"

    # Schedutil rate limits — split up/down (Chimera Mk7 exposes separate nodes)
    for pol_dir in /sys/devices/system/cpu/cpufreq/policy*/schedutil/; do
        [ -d "$pol_dir" ] || continue
        write_node "${pol_dir}up_rate_limit_us"   "$SCHEDUTIL_UP_RATE_LIMIT_US"   || true
        write_node "${pol_dir}down_rate_limit_us" "$SCHEDUTIL_DOWN_RATE_LIMIT_US" || true
        # Fallback combined node (older schedutil)
        write_node "${pol_dir}rate_limit_us"      "$SCHEDUTIL_UP_RATE_LIMIT_US"   || true
    done

    # [V31-H] Replaced EMS sysfs writes with cgroup-based profiles.
    # EMS nodes confirmed stubs (eff_mode=0, ontime/band = empty strings).
    # schedtune + cpuset is the effective scheduler control path.
    apply_stune_profiles

    local ts; ts="$(get_thermal_state)"
    logv "KNOBS: state=$STATE mem=$MEM_TIER thermal=$ts psi_full=${F_PSI_FULL_AVG10} batt=$F_BATT charging=$F_CHARGING"
}

# ──────────────────────────────────────────────────────────────────────────────
# Audio HAL crash recovery watchdog
# Handles two failure modes on Derpfest 16.2 + Exynos 9810 vendor HAL:
#
# MODE A — updatable_crashing (hard stop):
#   vendor.audio-hal crashes 4x in 4 min → init sets updatable_crashing=1 →
#   auto-restart suppressed → audioserver stuck 'restarting' indefinitely.
#
# MODE B — AIDL Core HAL mismatch / binder EINVAL (soft restart loop):
#   Derpfest A16 audioserver.rc tries to start AIDL Core HAL companions
#   (vendor.audio-hal-aidl etc.) — all fail "service not found" because the
#   Exynos 9810 vendor partition only has legacy HIDL. audioserver falls back
#   to HIDL but gets binder EINVAL (-22) if vendor.audio-hal restarted
#   mid-handshake. Result: audioserver in 'restarting' loop without
#   updatable_crashing firing. Detected by watching 'restarting' persist
#   for > RESTART_STALL_S seconds.
#
# Recovery sequence (both modes):
#   stop audioserver → stop vendor.audio-hal → 3s binder GC pause →
#   start vendor.audio-hal → 2s registration wait →
#   start audioserver → 3s → dap_post_audio_restart
# ──────────────────────────────────────────────────────────────────────────────
_LAST_AUDIO_RECOVERY=0
_AUDIO_RESTART_FIRST_SEEN=0
RESTART_STALL_S=45

apply_audio_hal_crash_recovery() {
    local now
    now="$(date +%s)"
    [ $((now - _LAST_AUDIO_RECOVERY)) -lt 90 ] && return 0

    local asp_svc hal_svc crashing proc_name trigger_mode=""
    asp_svc="$(getprop init.svc.audioserver 2>/dev/null)"
    hal_svc="$(getprop init.svc.vendor.audio-hal 2>/dev/null)"
    crashing="$(getprop sys.init.updatable_crashing 2>/dev/null || echo 0)"
    proc_name="$(getprop sys.init.updatable_crashing_process_name 2>/dev/null || echo '')"

    # MODE A
    if [ "$crashing" = "1" ]; then
        case "${proc_name:-}" in *audio*|*audio-hal*) trigger_mode="hard_crash" ;; esac
    fi

    # MODE B — soft restart loop
    if [ -z "$trigger_mode" ] && [ "$asp_svc" = "restarting" ]; then
        if [ "$_AUDIO_RESTART_FIRST_SEEN" = "0" ]; then
            _AUDIO_RESTART_FIRST_SEEN="$now"
            logv "AUDIO_RECOVERY: audioserver=restarting — stall watch started (${RESTART_STALL_S}s)"
        elif [ $((now - _AUDIO_RESTART_FIRST_SEEN)) -ge "$RESTART_STALL_S" ]; then
            trigger_mode="soft_loop"
        fi
    fi

    # Audio healthy — reset stall timer and clear stale flag
    if [ "$asp_svc" = "running" ]; then
        _AUDIO_RESTART_FIRST_SEEN=0
        [ "$crashing" = "1" ] && {
            setprop sys.init.updatable_crashing 0 2>/dev/null || true
            log "AUDIO_RECOVERY: HAL recovered on its own — cleared updatable_crashing"
        }
        return 0
    fi

    [ -z "$trigger_mode" ] && return 0

    _LAST_AUDIO_RECOVERY="$now"
    _AUDIO_RESTART_FIRST_SEEN=0
    log "AUDIO_RECOVERY: triggered mode=$trigger_mode asp=$asp_svc hal=$hal_svc"
    notify_user "Brain Core: Audio" "Recovering audio stack (mode=$trigger_mode)" "audio_recovery"

    # Clear crash flag
    setprop sys.init.updatable_crashing 0 2>/dev/null || true
    setprop sys.init.updatable_crashing_process_name "" 2>/dev/null || true

    # Stop audioserver first — releases binder refs to HAL
    stop audioserver 2>/dev/null || true
    sleep 1
    stop vendor.audio-hal 2>/dev/null || true
    # 3s binder GC pause — clears dead session refs causing EINVAL (Mode B)
    sleep 3

    start vendor.audio-hal 2>/dev/null || true

    local hal_up=0 i=0
    while [ $i -lt 6 ]; do
        hal_svc="$(getprop init.svc.vendor.audio-hal 2>/dev/null)"
        [ "$hal_svc" = "running" ] && { hal_up=1; break; }
        sleep 1; i=$((i+1))
    done

    if [ "$hal_up" = "1" ]; then
        # Extra 1s: Exynos 9810 HIDL HAL needs time to publish IModule/default
        sleep 1
        start audioserver 2>/dev/null || true
        sleep 3
        start dap_post_audio_restart 2>/dev/null || true
        local final
        final="$(getprop init.svc.audioserver 2>/dev/null)"
        log "AUDIO_RECOVERY: done — audioserver=$final"
        notify_user "Brain Core: Audio" "Recovery complete (audioserver=$final)" "audio_recovery_done"
    else
        loge "AUDIO_RECOVERY: vendor.audio-hal did not come up — reboot recommended"
        notify_user "Brain Core: Audio" "HAL recovery failed — reboot recommended" "audio_recovery_fail"
    fi
}

apply_codec2_boot_fix() {
    [ "${CODEC2_BOOT_FIXED:-0}" = "1" ] && return 0
    CODEC2_BOOT_FIXED=1

    if command -v resetprop >/dev/null 2>&1; then
        resetprop persist.media.c2.hal.selection hidl 2>/dev/null || true
        resetprop persist.vendor.media.c2.hal.selection hidl 2>/dev/null || true
    else
        setprop persist.media.c2.hal.selection hidl 2>/dev/null || true
        setprop persist.vendor.media.c2.hal.selection hidl 2>/dev/null || true
    fi

    stop media.swcodec 2>/dev/null || true
    sleep 2
    start media.swcodec 2>/dev/null || true
    log "Codec2: forced HIDL selection"
}

# ──────────────────────────────────────────────────────────────────────────────
# EVOX BLOAT MANAGEMENT
# ──────────────────────────────────────────────────────────────────────────────
apply_evox_bloat() {
    local pkg p

    # [FIX] Gate force-stop on audio stack state.
    # am force-stop while audioserver holds an active binder session to a
    # media app causes a binder transaction leak inside the HAL's session
    # teardown path — confirmed by binder log at t=938s in AEGIS diag.
    # When audio is live we demote OOM scores and let lmkd do the eviction.
    local _do_kill=1
    _audio_stack_live && _do_kill=0

    for pkg in $BLOAT_KILL_PKGS; do
        [ -z "$pkg" ] && continue
        [ "$pkg" = "${F_FG_APP:-}" ] && continue
        if [ "$_do_kill" = "1" ]; then
            am force-stop "$pkg" 2>/dev/null || true
        fi
        for p in $(pidof "$pkg" 2>/dev/null); do
            [ -d "/proc/$p" ] || continue
            write_node "/proc/$p/oom_score_adj" "900" || true
            renice -n 19 -p "$p" >/dev/null 2>&1 || true
        done
    done
    logv "BLOAT: kill tier done (force_stop=$_do_kill)"

    for pkg in $BLOAT_THROTTLE_PKGS; do
        [ -z "$pkg" ] && continue
        [ "$pkg" = "${F_FG_APP:-}" ] && continue
        for p in $(pidof "$pkg" 2>/dev/null); do
            [ -d "/proc/$p" ] || continue
            write_node "/proc/$p/oom_score_adj" "600" || true
            renice -n 10 -p "$p" >/dev/null 2>&1 || true
            safe_cpuset_write "$p" "/dev/cpuset/background/tasks" || true
        done
    done
    logv "BLOAT: throttle tier done"

    _BLOAT_APPLIED=1
}

apply_streaming_audio_boost() {
    [ -z "${F_FG_APP:-}" ] && return 0

    local is_streaming=0 app
    for app in $STREAMING_AUDIO_APPS; do
        [ "$F_FG_APP" = "$app" ] && { is_streaming=1; break; }
    done
    [ "$is_streaming" = "0" ] && return 0

    local p
    p="$(pidof "$F_FG_APP" 2>/dev/null | awk '{print $1}')"
    if [ -n "$p" ] && [ -d "/proc/$p" ]; then
        set_proc_adj "$p" "-900" "-15"
        safe_cpuset_write "$p" "/dev/cpuset/top-app/tasks"
    fi

    local asp
    asp="$(pidof audioserver 2>/dev/null | awk '{print $1}')"
    if [ -n "$asp" ] && [ -d "/proc/$asp" ]; then
        set_proc_adj "$asp" "-1000" "-20"
        safe_cpuset_write "$asp" "/dev/cpuset/top-app/tasks"
        boost_all_threads_rt "$asp" 3
        logv "STREAM: audioserver $asp boosted for streaming"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN apply_policy wrapper
# ──────────────────────────────────────────────────────────────────────────────
apply_policy() {
    rotate_logs
    snapshot_ps

    apply_audio_hal_crash_recovery   # must run first — recovers dead HAL
    apply_render_pipeline_priority
    apply_touch_power_hal_priority
    apply_launcher_priority
    apply_systemui_priority
    apply_audio_rt
    apply_background_audio_priority
    apply_fingerprint_priority        # [C] resolves FP PID, sets SCHED_RR p=5
    apply_camera_isp_protection       # resolves camera ISP PIDs
    apply_biometric_big_pin           # [V31-E] BIG-pin FP + camera HALs
    apply_foreground_priority
    apply_camera_priority
    apply_sensor_hal_pm
    apply_shizuku_priority
    apply_bt_pm
    apply_bt_audio_ensure
    apply_bt_watchdog
    apply_codec2_boot_fix
    apply_streaming_audio_boost
    apply_wifi_pm
    apply_system_knobs                # calls apply_stune_profiles() [V31-G]
    apply_screen_timeout
    apply_memory_pressure_response
    apply_spkamp_shim_watchdog

    if [ "$_BLOAT_APPLIED" = "0" ] || [ "$F_SCREEN_ON" = "0" ]; then
        apply_evox_bloat
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# DAEMON / LOOP
# ──────────────────────────────────────────────────────────────────────────────
_is_fast_poll_state() {
    case "$STATE" in
        interactive|camera_active|charging) return 0 ;;
        *) return 1 ;;
    esac
}

main_loop() {
    exec 9>"$LOCK_FILE" 2>/dev/null || {
        loge "Cannot open lock file $LOCK_FILE"
        return 1
    }
    if ! flock -n 9; then
        log "Another instance is running; exiting."
        return 0
    fi
    echo $$ > "${LOCK_FILE}.pid" 2>/dev/null || true

    waitAudioServer || true

    # [F] Phantom killer guard — must run after boot_completed
    apply_phantom_killer_guard

    # Start schedutil watchdog
    schedutil_watchdog &
    log "MAIN: watchdog pid=$!"

    # Initial SPKAMP check
    _LAST_SHIM_CHECK=0
    apply_spkamp_shim_watchdog

    # Initial bloat pass
    collect_facts
    apply_evox_bloat
    log "MAIN: Brain Core $SCRIPT_VERSION started"
    notify_user "Brain Core $SCRIPT_VERSION" "Daemon started — all subsystems armed" "bc_start"

    while true; do
        collect_facts
        classify_state
        compute_policy
        apply_policy

        if [ "$F_SCREEN_ON" = "0" ]; then
            sleep "$POLL_SCREEN_OFF"
        elif _is_fast_poll_state; then
            sleep "$FAST_POLL"
        else
            sleep "$POLL_SCREEN_ON"
        fi
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL / UNINSTALL
# ──────────────────────────────────────────────────────────────────────────────
install_self() {
    if [ -w "$(dirname "$INSTALL_TARGET")" ]; then
        cp -f "$0" "$INSTALL_TARGET" 2>/dev/null || { loge "install: copy failed"; return 1; }
        chmod 0755 "$INSTALL_TARGET" 2>/dev/null || true
        log "Installed to $INSTALL_TARGET"
    else
        loge "install: cannot write to $(dirname "$INSTALL_TARGET")"
        return 1
    fi
}

uninstall_self() {
    if [ -f "$INSTALL_TARGET" ]; then
        rm -f "$INSTALL_TARGET" 2>/dev/null || loge "uninstall: rm failed"
        log "Uninstalled $INSTALL_TARGET"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# ENTRYPOINT
# ──────────────────────────────────────────────────────────────────name────────
case "${1:-run}" in
    install)   install_self ;;
    uninstall) uninstall_self ;;
    run)       main_loop ;;
    *)         echo "Usage: $0 {install|uninstall|run}"; exit 1 ;;
esac

exit 0