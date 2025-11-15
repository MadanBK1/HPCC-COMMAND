#!/usr/bin/env bash
set -euo pipefail

echo "****************** STARTING ROCKY VNC SESSION ******************"

##############################
# A. Configurable paths
##############################

#export IMG="/mnt/research/WMUCFDLAB/singularity/virtualgl-turbovnc-ros2_latest.sif"
export IMG="/mnt/scratch/k0006390/virtualgl-turbovnc-ros2_latest.sif"
export ROCKY_BIN="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/rocky/bin/Rocky"
export ROCKY_LIB="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/rocky/lib"

##############################
# B. Sanity check
##############################

if [[ ! -f "$IMG" ]]; then
  echo "[ERROR] Singularity image not found: $IMG"
  exit 1
fi

if ! singularity exec -B /cvmfs:/cvmfs "$IMG" test -x "$ROCKY_BIN"; then
  echo "[ERROR] Rocky binary not executable inside container: $ROCKY_BIN"
  exit 1
else
  echo "[INFO] Rocky binary is visible and executable inside container."
fi

##############################
# C. Full cleanup (hard reset)
##############################

echo "[INFO] Cleaning up stale processes and VNC..."
jobs -l || true
kill %1 %2 %3 2>/dev/null || true

pkill -9 -f Rocky            2>/dev/null || true
pkill -9 -f RockySolver      2>/dev/null || true
pkill -9 -f vglclient        2>/dev/null || true
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver -kill :2 2>/dev/null || true

##############################
# D. Start new VNC session :2
##############################

echo "[INFO] Starting fresh VNC :2..."
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver :2 -localhost -geometry 1600x900 -depth 24
export DISPLAY=:2
#xhost +SI:localuser:$USER

##############################
# E. Start vglclient (GPU bridge)
##############################

echo "[INFO] Starting fresh vglclient..."
singularity exec "$IMG" /usr/bin/vglclient -display :2 -port 4242 >/dev/null 2>&1 &
VGL_PID=$!
export VGL_CLIENT=127.0.0.1:4242

for i in {1..5}; do
    if ps -p "$VGL_PID" > /dev/null 2>&1; then
        echo "[INFO] vglclient is running (PID $VGL_PID)"
        break
    fi
    sleep 1
    if [[ $i -eq 5 ]]; then
        echo "[ERROR] vglclient failed to start"
        exit 1
    fi
done

##############################
# F. Launch Rocky with full isolation + cleanup
##############################

echo "[INFO] Launching Rocky GUI (GPU-accelerated)..."

singularity exec --nv \
  -B /cvmfs:/cvmfs \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  -B /etc/fonts:/etc/fonts \
  -B /usr/share/fontconfig:/usr/share/fontconfig \
  -B /usr/share/fonts:/usr/share/fonts \
  "$IMG" /bin/bash --noprofile --norc <<'EOF'

echo "[INFO] Inside container. Launching Rocky with full GPU + WebEngine support..."

# === Core ===
export DISPLAY=:2
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PERL_BADLANG=0
export XAUTHORITY="$HOME/.Xauthority"

# === Temporary runtime isolation ===
export TMPDIR="/tmp/rocky_tmp_$USER_$$"
mkdir -p "$TMPDIR"

export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_DATA_HOME="$TMPDIR/data"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export QTWEBENGINE_LOCALEDIR="$TMPDIR/qtwebengine_locales"
export QTWEBENGINE_RESOURCES_PATH="$TMPDIR/qtwebengine_resources"

mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"  # ✅ Fix Qt warning
mkdir -p "$QTWEBENGINE_LOCALEDIR" "$QTWEBENGINE_RESOURCES_PATH"

cp -r "$ROCKY_LIB/qtwebengine_locales/"* "$QTWEBENGINE_LOCALEDIR/" 2>/dev/null || true
cp -r "$ROCKY_LIB/resources/"* "$QTWEBENGINE_RESOURCES_PATH/" 2>/dev/null || true

# === VirtualGL + Qt setup ===
export QT_QPA_PLATFORM=xcb
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu-compositing --disable-gpu-watchdog --no-sandbox --in-process-gpu --single-process --disable-seccomp-filter-sandbox"
export VGL_DISPLAY=egl
export VGL_CLIENT=127.0.0.1:4242
export VGL_COMPRESS=1
export VGL_QUAL=80
export VGL_SUBSAMP=1
export FONTCONFIG_FILE=/etc/fonts/fonts.conf
export LD_LIBRARY_PATH="$ROCKY_LIB:/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/nss:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# === Auto-cleanup trap ===
trap "echo '[INFO] Cleaning up temp files...'; rm -rf \"$TMPDIR\"; exit" EXIT

echo "[INFO] Running Rocky using vglrun..."
/usr/bin/vglrun "$ROCKY_BIN" & wait $!

echo "[INFO] Rocky exited."

EOF

echo "****************** ROCKY VNC SESSION ENDED ******************"
