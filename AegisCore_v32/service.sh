#!/system/bin/sh
# AegisCore V32.0 — service.sh
# KernelSU auto-executes this in background after post-fs-data on every boot.
MODDIR="${0%/*}"
LOG="/data/local/tmp/brain_core.log"

log() { echo "$(date '+%F %T') [AEGIS_SVC] $*" >> "$LOG"; }

# Wait for full system readiness
wait_boot() {
    local i=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
        sleep 3
        i=$((i+1))
        [ $i -gt 80 ] && { log "WARN: boot_completed timeout"; break; }
    done
    log "boot_completed confirmed (${i}x3s waits)"
}

wait_boot

# 30s grace: lets vendor audio_postboot.rc and audio_postboot_aegis.rc
# both complete before EMS Flow writes cgroup values.
log "Waiting 30s post-boot grace..."
sleep 30

# §1 EMS Flow: one-shot cgroup profile
log "Starting EMS Flow v2.2..."
sh "$MODDIR/scripts/99chimera_ems_v22_flow.sh" >> "$LOG" 2>&1 || \
    log "WARN: EMS Flow exited non-zero"

sleep 20

# §2 Clear any stale Brain Core instances before launching ours.
# A crashed/exited Brain Core from a previous module (V31, V32.1, etc.)
# leaves a lock file behind. Our V32.0 would see it and exit immediately.
# pkill -f first, then wipe lock files, then wait for PID table to settle.
log "Clearing stale Brain Core instances..."
pkill -f brain_core 2>/dev/null || true
sleep 2
rm -f /data/local/tmp/brain_core.lock
rm -f /data/local/tmp/brain_core.lock.pid
log "Stale instances cleared"

# §3 Brain Core V32: persistent daemon
# Double-fork: outer subshell exits immediately, Brain Core is reparented
# to init (PID 1) and survives when service.sh returns to KernelSU.
log "Starting Brain Core V32..."
(sh "$MODDIR/scripts/brain_core_v32.sh" >> "$LOG" 2>&1 &)
sleep 1
BC_PID="$(pgrep -f brain_core_v32 2>/dev/null | head -1)"
log "Brain Core V32 launched (pid=${BC_PID:-unknown})"

exit 0