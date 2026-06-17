#!/system/bin/sh
# AegisCore V32.0 — KernelSU / MMRL-safe installer
# No set_perm / set_perm_recursive — not available in all MMRL metainstall contexts.
# Uses plain chmod on $MODPATH instead.

SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ui_print " "
ui_print "╔════════════════════════════════════════════╗"
ui_print "║  AegisCore V32.0 Sentinel (Stabilitas)     ║"
ui_print "║  AegisDevLabs — star2lte / Exynos 9810     ║"
ui_print "╚════════════════════════════════════════════╝"
ui_print " "

DEVICE="$(getprop ro.product.device 2>/dev/null || echo unknown)"
ROM="$(getprop ro.build.version.release 2>/dev/null || echo unknown)"
ui_print "  Device : $DEVICE"
ui_print "  Android: $ROM"

if [ "$DEVICE" != "star2lte" ]; then
    abort "! Unsupported device: $DEVICE (expected star2lte)"
fi

ui_print "  ✓ Device supported"

# Remove conflicting module
if [ -d /data/adb/modules/audio_fix ]; then
    ui_print "  ⚠  Removing conflicting module: audio_fix"
    rm -rf /data/adb/modules/audio_fix
    ui_print "  ✓ audio_fix removed"
fi

# Remove previous V31 to avoid duplicate service.sh
if [ -d /data/adb/modules/aegis_core_v31 ]; then
    rm -rf /data/adb/modules/aegis_core_v31
    ui_print "  ✓ Superseded aegis_core_v31"
fi

# Clear stale Brain Core lock files
rm -f /data/local/tmp/brain_core.lock
rm -f /data/local/tmp/brain_core.lock.pid
ui_print "  ✓ Stale lock files cleared"

# Set permissions via chmod — works in all KernelSU/MMRL contexts
chmod 0755 "$MODPATH/service.sh"                           2>/dev/null || true
chmod 0755 "$MODPATH/customize.sh"                         2>/dev/null || true
chmod 0755 "$MODPATH/verify_tuning.sh"                     2>/dev/null || true
chmod 0755 "$MODPATH/revert_chimera.sh"                    2>/dev/null || true
chmod 0755 "$MODPATH/scripts/brain_core_v32.sh"            2>/dev/null || true
chmod 0755 "$MODPATH/scripts/99chimera_ems_v22_flow.sh"    2>/dev/null || true
chmod 0644 "$MODPATH/module.prop"                          2>/dev/null || true
chmod 0644 "$MODPATH/system/etc/init/audio_postboot_aegis.rc" 2>/dev/null || true
ui_print "  ✓ Permissions set"

# schedtune sanity check
if [ -d /dev/stune ]; then
    ui_print "  ✓ /dev/stune confirmed — EMS Flow cgroup writes active"
else
    ui_print "  ⚠  /dev/stune not found — EMS Flow schedtune writes will skip"
fi

ui_print " "
ui_print "  ════════════════════════════════════════"
ui_print "  Install complete. Reboot to activate."
ui_print " "
ui_print "  Boot sequence:"
ui_print "    1. service.sh waits for boot_completed + 30s"
ui_print "    2. EMS Flow v2.2 sets cgroup profiles"
ui_print "    3. Brain Core V32 starts as persistent daemon"
ui_print " "
ui_print "  Verify after reboot:"
ui_print "    sh /data/adb/modules/aegis_core_v32/verify_tuning.sh"
ui_print " "
ui_print "  Log: /data/local/tmp/brain_core.log"
ui_print "  ════════════════════════════════════════"
