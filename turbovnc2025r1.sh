#!/usr/bin/env bash
set -euo pipefail
echo "****************** STARTING ROCKY VNC SESSION (2025R1) ******************"

##############################
# A. CONFIG
##############################
export IMG="/mnt/scratch/$USER/virtualgl-turbovnc-ros2_latest.sif"
export ROCKY_BIN="/opt/software-current/2023.06/x86_64/generic/software/ANSYS/2025R1/v251/rocky/bin/Rocky"
export ROCKY_LIB="/opt/software-current/2023.06/x86_64/generic/software/ANSYS/2025R1/v251/rocky/bin"
export VGL_PORT=4242

##############################
# B. Check container + Rocky
##############################
if [[ ! -f "$IMG" ]]; then
    echo "[ERROR] Singularity image missing: $IMG"
    exit 1
fi
if singularity exec -B /opt/software-current:/opt/software-current "$IMG" test -x "$ROCKY_BIN"; then
    echo "[INFO] Rocky 2025R1 detected inside container."
else
    echo "[ERROR] Rocky not accessible inside container: $ROCKY_BIN"
    exit 1
fi

##############################
# C. Cleanup old sessions
##############################
echo "[INFO] Cleaning old VNC/VGL/Rocky processes..."
pkill -9 -f vglclient      2>/dev/null || true
pkill -9 -f Rocky          2>/dev/null || true
pkill -9 -f RockySolver    2>/dev/null || true
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver -kill :2 2>/dev/null || true
sleep 1

# Kill any process using VGL port
fuser -k ${VGL_PORT}/tcp 2>/dev/null || true
sleep 1

##############################
# D. Increase file descriptor limits
##############################
echo "[INFO] Increasing file descriptor limits..."
ulimit -n 8192 2>/dev/null || echo "[WARN] Could not set ulimit (may need sysadmin help)"

##############################
# E. Start TurboVNC :2
##############################
echo "[INFO] Starting TurboVNC :2 ..."
singularity exec --nv "$IMG" /opt/TurboVNC/bin/vncserver :2 -localhost -geometry 1600x900 -depth 24
export DISPLAY=:2
sleep 3

##############################
# F. Start vglclient with proper environment
##############################
echo "[INFO] Starting vglclient on port ${VGL_PORT}..."

# Start vglclient inside container with output redirect
singularity exec "$IMG" bash -c "
    ulimit -n 8192 2>/dev/null || true
    export DISPLAY=:2
    echo '[VGL] Starting vglclient on display :2, port ${VGL_PORT}...' >&2
    exec /usr/bin/vglclient -display :2 -port ${VGL_PORT}
" > /tmp/vglclient_${USER}.log 2>&1 &

VGL_PID=$!
sleep 4

# Verify vglclient is running
if ! ps -p $VGL_PID > /dev/null 2>&1; then
    echo "[ERROR] vglclient failed to start. Check log:"
    cat /tmp/vglclient_${USER}.log 2>/dev/null || echo "No log file found"
    exit 1
fi

echo "[INFO] vglclient started with PID $VGL_PID"

# Verify port is listening (wait up to 10 seconds)
echo "[INFO] Waiting for vglclient to open port ${VGL_PORT}..."
for i in {1..10}; do
    if netstat -tln 2>/dev/null | grep -q ":${VGL_PORT} " || ss -tln 2>/dev/null | grep -q ":${VGL_PORT} "; then
        echo "[INFO] vglclient port ${VGL_PORT} is listening"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "[ERROR] vglclient port ${VGL_PORT} not listening after 10 seconds"
        cat /tmp/vglclient_${USER}.log 2>/dev/null || true
        exit 1
    fi
    sleep 1
done

echo "[INFO] vglclient running with PID $VGL_PID on port ${VGL_PORT}"

##############################
# G. Launch Rocky inside container with VGL
##############################
echo "[INFO] Launching Rocky 2025R1 inside container..."
singularity exec --nv \
  -B /opt/software-current:/opt/software-current \
  -B /etc/fonts:/etc/fonts \
  -B /usr/share/fonts:/usr/share/fonts \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  "$IMG" bash -c "
    echo '[INFO] Inside container. Preparing environment...';
    
    ##############################
    # File descriptor limit & inotify workaround
    ##############################
    ulimit -n 8192 2>/dev/null || true;
    
    # Disable Qt file system watcher to avoid inotify issues
    export QT_NO_GLIB=1;
    export QT_QPA_PLATFORM_PLUGIN_PATH=;
    export QT_FILESYSTEMWATCHER=off;
    
    ##############################
    # Locale FIX
    ##############################
    export LANG=C.UTF-8;
    export LC_ALL=C.UTF-8;
    export LANGUAGE=en;
    
    ##############################
    # XDG FIX
    ##############################
    export XDG_RUNTIME_DIR=/tmp/runtime-$USER;
    mkdir -p \$XDG_RUNTIME_DIR;
    chmod 700 \$XDG_RUNTIME_DIR;
    
    ##############################
    # Fontconfig FIX
    ##############################
    export FONTCONFIG_PATH=/etc/fonts;
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf;
    
    ##############################
    # QtWebEngine FIX
    ##############################
    export QT_QPA_PLATFORM=xcb;
    export QTWEBENGINE_DISABLE_SANDBOX=1;
    export QTWEBENGINE_CHROMIUM_FLAGS='--no-sandbox --disable-gpu-compositing --single-process';
    
    ##############################
    # VirtualGL GPU acceleration
    ##############################
    export DISPLAY=:2;
    export VGL_DISPLAY=egl;
    export VGL_CLIENT=127.0.0.1:${VGL_PORT};
    export VGL_COMPRESS=proxy;
    export VGL_READBACK=sync;
    
    ##############################
    # Libs
    ##############################
    export LD_LIBRARY_PATH='$ROCKY_LIB':\$LD_LIBRARY_PATH;
    
    echo '[INFO] Verifying VGL connection to 127.0.0.1:${VGL_PORT}...';
    if ! timeout 5 bash -c '</dev/tcp/127.0.0.1/${VGL_PORT}' 2>/dev/null; then
        echo '[ERROR] Cannot connect to vglclient port ${VGL_PORT}';
        echo '[ERROR] Check if vglclient is running: ps aux | grep vglclient';
        exit 1;
    fi
    echo '[INFO] VGL connection verified. Starting Rocky...';
    
    vglrun +v $ROCKY_BIN
  "

# Cleanup on exit
kill $VGL_PID 2>/dev/null || true

echo "****************** ROCKY VNC SESSION ENDED ******************"
