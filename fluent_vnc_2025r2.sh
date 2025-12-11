#!/usr/bin/env bash
set -euo pipefail

echo "****************** STARTING FLUENT VNC SESSION ******************"

##############################
# A. Configurable paths
##############################

export IMG="/mnt/research/WMUCFDLAB/singularity/virtualgl-turbovnc-ros2_latest.sif"
export FLUENT_BIN="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/fluent/bin/fluent"

##############################
# B. Sanity check
##############################

if [[ ! -f "$IMG" ]]; then
  echo "[ERROR] Singularity image not found: $IMG"
  exit 1
fi

if ! singularity exec -B /cvmfs:/cvmfs "$IMG" test -x "$FLUENT_BIN"; then
  echo "[ERROR] Fluent binary not executable: $FLUENT_BIN"
  exit 1
else
  echo "[INFO] Fluent binary is visible inside container."
fi

##############################
# C. Start VNC :2
##############################

echo "[INFO] Starting fresh VNC :2..."
singularity exec --nv "$IMG" \
  /opt/TurboVNC/bin/vncserver :2 -localhost -geometry 1600x900 -depth 24

export DISPLAY=:2
xhost +SI:localuser:$USER

##############################
# D. Start VirtualGL client
##############################

echo "[INFO] Starting vglclient..."
singularity exec "$IMG" /usr/bin/vglclient -display :2 -port 4242 >/dev/null 2>&1 &
VGL_PID=$!

sleep 1
if ps -p "$VGL_PID" > /dev/null 2>&1; then
  echo "[INFO] vglclient running (PID $VGL_PID)"
else
  echo "[ERROR] vglclient failed to start"
  exit 1
fi

##############################
# E. Launch Fluent Launcher GUI
##############################

echo "[INFO] Launching Fluent Launcher GUI (GPU-accelerated)..."

singularity exec --nv \
  -B /cvmfs:/cvmfs \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  -B /usr/share/glvnd:/usr/share/glvnd \
  -B /usr/share/fonts:/usr/share/fonts \
  -B /usr/share/fontconfig:/usr/share/fontconfig \
  -B /etc/fonts:/etc/fonts \
  -B /usr/lib/nvidia:/usr/lib/nvidia \
  -B /usr/lib/x86_64-linux-gnu/nvidia:/usr/lib/x86_64-linux-gnu/nvidia \
  "$IMG" /bin/bash --noprofile --norc <<'EOF'


export DISPLAY=:2
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Qt + Chromium fixes
export QT_QPA_PLATFORM=xcb
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu-watchdog --no-sandbox --in-process-gpu --disable-seccomp-filter-sandbox"

# NVIDIA + OpenGL routing
export VGL_DISPLAY=egl
export VGL_CLIENT=127.0.0.1:4242
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export MESA_LOADER_DRIVER_OVERRIDE=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1

echo "[INFO] Running Fluent Launcher..."
/usr/bin/vglrun -d :2 "$FLUENT_BIN" -driver opengl & wait $!

echo "[INFO] Fluent exited."
EOF

echo "****************** FLUENT VNC SESSION ENDED ******************"
