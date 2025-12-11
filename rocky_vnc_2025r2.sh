#!/usr/bin/env bash
set -euo pipefail

echo "****************** STARTING ROCKY VNC SESSION (H200 Optimized + NSS Fix) ******************"

##############################
# A. Configurable paths
##############################
export IMG="/mnt/ufs18/nodr/research/WMUCFDLAB/virtualgl-turbovnc-ros2_latest.sif"

# export IMG="/mnt/scratch/k0006390/virtualgl-turbovnc-ros2_latest.sif"
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
# C. Cleanup (hard reset)
##############################
echo "[INFO] Cleaning up stale processes and VNC..."
pkill -9 -f Rocky 2>/dev/null || true
pkill -9 -f RockySolver 2>/dev/null || true
pkill -9 -f vglclient 2>/dev/null || true
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver -kill :2 2>/dev/null || true

##############################
# D. Start new VNC session :2
##############################
echo "[INFO] Starting fresh VNC :2..."
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver :2 -localhost -geometry 1600x900 -depth 24
export DISPLAY=:2

NODE=$(hostname)
echo "-----------------------------------------------------------"
echo "[INFO] Connect from local machine with:"
echo "  ssh -L 5902:localhost:5902 k0006390@gateway.hpcc.msu.edu -J k0006390@${NODE}"
echo "  VNC Viewer → localhost:5902"
echo "-----------------------------------------------------------"

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
# F. Launch Rocky (GPU-Accelerated, H200 Fast Path)
##############################
echo "[INFO] Launching Rocky GUI (GPU-accelerated, optimized for H200)..."

singularity exec --nv \
  -B /cvmfs:/cvmfs \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /usr/lib/x86_64-linux-gnu/nss:/usr/lib/x86_64-linux-gnu/nss \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  -B /etc/fonts:/etc/fonts \
  -B /usr/share/fontconfig:/usr/share/fontconfig \
  -B /usr/share/fonts:/usr/share/fonts \
  "$IMG" /bin/bash --noprofile --norc <<'EOF'

echo "[INFO] Inside container. Preparing GPU environment..."

# === Core ===
export DISPLAY=:2
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PERL_BADLANG=0
export XAUTHORITY="$HOME/.Xauthority"

# === Temp isolation dirs ===
export TMPDIR="/tmp/rocky_h200_$USER_$$"
mkdir -p "$TMPDIR"/{cache,config,data,runtime,qtwebengine_locales,qtwebengine_resources}
chmod 700 "$TMPDIR/runtime"

export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_CONFIG_HOME="$TMPDIR/config"
export XDG_DATA_HOME="$TMPDIR/data"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export QTWEBENGINE_LOCALEDIR="$TMPDIR/qtwebengine_locales"
export QTWEBENGINE_RESOURCES_PATH="$TMPDIR/qtwebengine_resources"

cp -r "$ROCKY_LIB/qtwebengine_locales/"* "$QTWEBENGINE_LOCALEDIR/" 2>/dev/null || true
cp -r "$ROCKY_LIB/resources/"* "$QTWEBENGINE_RESOURCES_PATH/" 2>/dev/null || true

# === VirtualGL / EGL tuning for NVIDIA H200 ===
export VGL_DISPLAY=egl
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1
export VGL_COMPRESS=rgb
export VGL_QUAL=95
export VGL_SUBSAMP=0
export OMP_NUM_THREADS=4
export CUDA_DEVICE_MAX_CONNECTIONS=32
export NCCL_P2P_DISABLE=1

# === Qt/WebEngine tweaks ===
export QT_QPA_PLATFORM=xcb
export QTWEBENGINE_DISABLE_SANDBOX=1
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu-watchdog --disable-gpu-sandbox --in-process-gpu --ignore-gpu-blocklist --single-process"
export LD_LIBRARY_PATH="$ROCKY_LIB:/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/nss:/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export FONTCONFIG_FILE=/etc/fonts/fonts.conf

# === Clean Python/Conda contamination ===
unset PYTHONHOME PYTHONPATH CONDA_PREFIX MAMBA_ROOT_PREFIX LD_PRELOAD

# === Auto-cleanup on exit ===
trap "echo '[INFO] Cleaning up temp files...'; rm -rf \"$TMPDIR\"; exit" EXIT

echo "[INFO] Checking GPU renderer..."
glxinfo | grep -E 'OpenGL renderer|vendor' || true

# === Launch Rocky ===
echo "[INFO] Launching Rocky now..."
/usr/bin/vglrun -d egl "$ROCKY_BIN" & wait $!

echo "[INFO] Rocky exited successfully."
EOF

echo "****************** ROCKY VNC SESSION ENDED ******************"

