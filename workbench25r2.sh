#!/usr/bin/env bash
set -euo pipefail

echo "****************** STARTING WORKBENCH VNC SESSION ******************"

##############################
# A. Configurable paths
##############################

export IMG="/mnt/research/WMUCFDLAB/singularity/virtualgl-turbovnc-ros2_latest.sif"
export WORKBENCH_BIN="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/Framework/bin/Linux64/runwb2"
export WORKBENCH_LIB="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/Framework/lib"

##############################
# B. Sanity check
##############################

if [[ ! -f "$IMG" ]]; then
  echo "[ERROR] Singularity image not found: $IMG"
  exit 1
fi

if ! singularity exec -B /cvmfs:/cvmfs "$IMG" test -x "$WORKBENCH_BIN"; then
  echo "[ERROR] Workbench binary not executable inside container: $WORKBENCH_BIN"
  exit 1
else
  echo "[INFO] Workbench binary is visible and executable inside container."
fi

##############################
# C. Cleanup old sessions
##############################

echo "[INFO] Cleaning up stale processes and VNC..."
pkill -9 -f runwb2         2>/dev/null || true
pkill -9 -f ansys          2>/dev/null || true
pkill -9 -f vglclient      2>/dev/null || true
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver -kill :2 2>/dev/null || true

##############################
# D. Start new VNC :2
##############################

echo "[INFO] Starting fresh VNC :2..."
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver :2 -localhost -geometry 1600x900 -depth 24
export DISPLAY=:2
xhost +SI:localuser:$USER

##############################
# E. Start vglclient bridge
##############################

echo "[INFO] Starting vglclient..."
singularity exec "$IMG" /usr/bin/vglclient -display :2 -port 4242 >/dev/null 2>&1 &
VGL_PID=$!
export VGL_CLIENT=127.0.0.1:4242

for i in {1..5}; do
  if ps -p "$VGL_PID" > /dev/null 2>&1; then
    echo "[INFO] vglclient is running (PID $VGL_PID)"
    break
  fi
  sleep 1
  [[ $i -eq 5 ]] && { echo "[ERROR] vglclient failed to start"; exit 1; }
done

##############################
# F. Launch Workbench
##############################

echo "[INFO] Launching ANSYS Workbench GUI (GPU-accelerated)..."

singularity exec --nv \
  -B /cvmfs:/cvmfs \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  -B /etc/fonts:/etc/fonts \
  -B /usr/share/fontconfig:/usr/share/fontconfig \
  -B /usr/share/fonts:/usr/share/fonts \
  "$IMG" /bin/bash --noprofile --norc <<'EOF'

export DISPLAY=:2
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PERL_BADLANG=0

# Qt / WebEngine fixes
export QT_QPA_PLATFORM=xcb
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu-compositing --disable-gpu-watchdog --no-sandbox --in-process-gpu --single-process --disable-seccomp-filter-sandbox"

# VirtualGL
export VGL_DISPLAY=egl
export VGL_CLIENT=127.0.0.1:4242
export VGL_COMPRESS=1
export VGL_QUAL=80
export VGL_SUBSAMP=1

# Temp dirs for Qt runtime
TMPDIR="/tmp/workbench_tmp_$USER_$$"
mkdir -p "$TMPDIR"/{cache,config,data,runtime,qtwebengine_locales,qtwebengine_resources}
chmod 700 "$TMPDIR/runtime"

export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_DATA_HOME="$TMPDIR/data"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export QTWEBENGINE_LOCALEDIR="$TMPDIR/qtwebengine_locales"
export QTWEBENGINE_RESOURCES_PATH="$TMPDIR/qtwebengine_resources"

cp -r "$WORKBENCH_LIB/qtwebengine_locales/"* "$QTWEBENGINE_LOCALEDIR/" 2>/dev/null || true
cp -r "$WORKBENCH_LIB/resources/"* "$QTWEBENGINE_RESOURCES_PATH/" 2>/dev/null || true

export FONTCONFIG_FILE=/etc/fonts/fonts.conf
export LD_LIBRARY_PATH="$WORKBENCH_LIB:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

trap "rm -rf $TMPDIR" EXIT

echo "[INFO] Running Workbench using vglrun..."
/usr/bin/vglrun "$WORKBENCH_BIN" & wait $!

echo "[INFO] Workbench exited."
EOF

echo "****************** WORKBENCH VNC SESSION ENDED ******************"
