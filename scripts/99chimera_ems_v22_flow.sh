#!/system/bin/sh
# EMS Flow v2.2 - tuned for Derpfest 16.2 / star2lte
set -u; umask 022

log() {
    echo "[EMS] $*" >> /data/local/tmp/brain_core.log
}

write_node() {
    local path="$1" value="$2"
    [ -e "$path" ] && echo "$value" > "$path" 2>/dev/null || true
}

log "applying EMS profile"

write_node /proc/sys/kernel/sched_migration_cost_ns "3000000"
write_node /proc/sys/kernel/sched_latency_ns "6000000"
write_node /proc/sys/kernel/sched_min_granularity_ns "1000000"
write_node /proc/sys/kernel/sched_wakeup_granularity_ns "2000000"
write_node /proc/sys/kernel/sched_rt_runtime_us "950000"
write_node /proc/sys/kernel/sched_rt_period_us "1000000"

write_node "/dev/stune/top-app/schedtune.boost" "10"
write_node "/dev/stune/top-app/schedtune.prefer_idle" "1"

write_node "/dev/stune/foreground/schedtune.boost" "5"
write_node "/dev/stune/foreground/schedtune.prefer_idle" "1"

write_node "/dev/stune/background/schedtune.boost" "0"
write_node "/dev/stune/background/schedtune.prefer_idle" "0"
write_node "/dev/stune/system-background/schedtune.boost" "0"

write_node "/dev/cpuset/top-app/cpus" "0-7"
write_node "/dev/cpuset/foreground/cpus" "0-7"
write_node "/dev/cpuset/background/cpus" "0-3"
write_node "/dev/cpuset/system-background/cpus" "0-2"

write_node "/dev/cpuctl/top-app/cpu.shares" "2048"
write_node "/dev/cpuctl/background/cpu.shares" "256"

# Schedutil governor rate limits, if present.
write_node "/sys/devices/system/cpu/cpufreq/policy0/schedutil/up_rate_limit_us" "1500"
write_node "/sys/devices/system/cpu/cpufreq/policy0/schedutil/down_rate_limit_us" "16000"
write_node "/sys/devices/system/cpu/cpufreq/policy4/schedutil/up_rate_limit_us" "1500"
write_node "/sys/devices/system/cpu/cpufreq/policy4/schedutil/down_rate_limit_us" "16000"

# Optional memory tuning, low-risk only.
write_node "/proc/sys/vm/swappiness" "100"
write_node "/proc/sys/vm/vfs_cache_pressure" "100"

log "EMS profile applied"
exit 0
