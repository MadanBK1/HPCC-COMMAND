#!/usr/bin/env bash
set -euo pipefail

echo "****************** STARTING ENSIGHT VNC SESSION (DISPLAY :3) ******************"

########################################
# A. Paths
########################################
export IMG="/mnt/ufs18/nodr/research/WMUCFDLAB/virtualgl-turbovnc-ros2_latest.sif"
export ENSIGHT_BIN="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/CEI/ensight252/machines/linux_2.6_64/ensight25.launcher"
export QTWEB_PREFIX="/cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/software/ANSYS/2025R2/v252/AnsysEM/tp/qt/5.15.18/linx64"

########################################
# B. Basic checks
########################################
if [[ ! -f "$IMG" ]]; then
  echo "[ERROR] Missing SIF image: $IMG"
  exit 1
fi
if [[ ! -x "$ENSIGHT_BIN" ]]; then
  echo "[ERROR] EnSight launcher not executable: $ENSIGHT_BIN"
  exit 1
fi
echo "[INFO] EnSight launcher found: $ENSIGHT_BIN"
echo "[INFO] Qt prefix: $QTWEB_PREFIX"

########################################
# C. Stop any previous VNC :3
########################################
echo "[INFO] Cleaning old VNC session..."
singularity exec "$IMG" /opt/TurboVNC/bin/vncserver -kill :3 2>/dev/null || true
pkill -f "vglclient.*:3" 2>/dev/null || true
sleep 1

########################################
# D. Start TurboVNC
########################################
echo "[INFO] Starting TurboVNC on :3..."
singularity exec --nv \
  -B /cvmfs \
  "$IMG" /opt/TurboVNC/bin/vncserver :3 -localhost -geometry 1600x900 -depth 24

export DISPLAY=:3
echo "[INFO] VNC display ready: $DISPLAY"

########################################
# E. Start VirtualGL client
########################################
echo "[INFO] Starting vglclient..."
singularity exec "$IMG" /usr/bin/vglclient -display :3 -port 4242 >/dev/null 2>&1 &
sleep 1

########################################
# F. Run EnSight with all correct binds
########################################
echo "[INFO] Launching EnSight inside container..."
singularity exec --nv \
  -B /cvmfs \
  -B "${QTWEB_PREFIX}:/opt/qtweb" \
  -B "${QTWEB_PREFIX}/bin/archdatadir/plugins/platforms:/opt/qt_platforms" \
  -B /usr/lib/x86_64-linux-gnu:/usr_host_libs \
  -B /usr/lib/x86_64-linux-gnu/nss:/usr_host_libs_nss \
  -B /lib/x86_64-linux-gnu:/lib_host_libs \
  -B /usr/lib/x86_64-linux-gnu/libsqlite3.so.0:/usr/lib/x86_64-linux-gnu/libsqlite3.so \
  "$IMG" bash -c '

  export DISPLAY=:3
  export VGL_CLIENT=127.0.0.1:4242
  export VGL_DISPLAY=egl

  export QT_X11_NO_MITSHM=1
  export QTWEBENGINE_DISABLE_SANDBOX=1
  export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"

  export QT_QPA_PLATFORM=xcb
  export QT_QPA_PLATFORM_PLUGIN_PATH=/opt/qt_platforms

  export LD_LIBRARY_PATH="/opt/qtweb/lib:/usr_host_libs:/usr_host_libs_nss:/lib_host_libs:${LD_LIBRARY_PATH}"

  echo "[INFO] Running EnSight..."
  vglrun "'"$ENSIGHT_BIN"'"
'



echo "****************** ENSIGHT SESSION FINISHED ******************"

########################################
# G. Cleanup VNC session
########################################
echo "[INFO] Cleaning up VNC..."
singularity exec "$IMG" /opt/TurboVNC/bin/vncserver -kill :3 2>/dev/null || true
pkill -f "vglclient.*:3" 2>/dev/null || true

echo "[INFO] Done."
