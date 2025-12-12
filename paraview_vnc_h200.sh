#!/bin/bash
set -euo pipefail

###########################################
# DISPLAY for TurboVNC + VirtualGL
###########################################
export DISPLAY=${DISPLAY:-:1}
export SINGULARITYENV_DISPLAY="$DISPLAY"
export VGL_DISPLAY="$DISPLAY"
export VGL_READBACK=pbo

###########################################
# Load ParaView + Qt + Python
###########################################
module use /cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/modules/all
module load ParaView/5.11.2-foss-2023a Qt5/5.15.10-GCCcore-12.3.0

PV_BIN="$(which paraview)"
echo "[INFO] Using ParaView: $PV_BIN"

###########################################
# Qt paths
###########################################
HOST_QT_BASE=/opt/software-current/2023.06/x86_64/generic/software/Qt5/5.15.10-GCCcore-12.3.0
HOST_QT_PLUGINS="$HOST_QT_BASE/plugins"
HOST_QT_LIBS="$HOST_QT_BASE/lib"

###########################################
# Python libs
###########################################
PY_EXE="$(which python3 || which python || true)"
HOST_PY_BASE="$(dirname "$(dirname "$PY_EXE")")"
HOST_PY_LIBS="$HOST_PY_BASE/lib"

###########################################
# double-conversion libs
###########################################
HOST_DBL_LIBS="/opt/software-current/2023.06/x86_64/intel/skylake_avx512/software/double-conversion/3.2.0-GCCcore-11.3.0/lib"

###########################################
# ICU libs
###########################################
HOST_ICU_LIBS="/opt/software-current/2023.06/x86_64/generic/software/ICU/73.2-GCCcore-12.3.0/lib"

###########################################
# FFmpeg libs
###########################################
HOST_FFMPEG_LIBS="/opt/software-current/2023.06/x86_64/generic/software/FFmpeg/6.0-GCCcore-12.3.0/lib"

###########################################
# x264 libs  (FOUND ON YOUR SYSTEM)
###########################################
HOST_X264_LIBS="/opt/software-current/2023.06/x86_64/intel/haswell/software/x264/20230226-GCCcore-12.3.0/lib"

###########################################
# System GL / X11 libs
###########################################
HOST_SYS_LIB=/usr/lib/x86_64-linux-gnu
HOST_SYS_LIB64=/lib/x86_64-linux-gnu

###########################################
# Container LD_LIBRARY_PATH
###########################################
export SINGULARITYENV_QT_PLUGIN_PATH=/qtplugins
export SINGULARITYENV_LD_LIBRARY_PATH="/qtlibs:/pylibs:/dblibs:/iculibs:/ffmpeglibs:/x264libs:$HOST_SYS_LIB:$HOST_SYS_LIB64"

echo "[INFO] Qt Plugin Path          : $HOST_QT_PLUGINS"
echo "[INFO] Qt Lib Path             : $HOST_QT_LIBS"
echo "[INFO] Python Libs             : $HOST_PY_LIBS"
echo "[INFO] double-conversion Libs  : $HOST_DBL_LIBS"
echo "[INFO] ICU Libs                : $HOST_ICU_LIBS"
echo "[INFO] FFmpeg Libs             : $HOST_FFMPEG_LIBS"
echo "[INFO] x264 Libs               : $HOST_X264_LIBS"
echo "[INFO] SINGULARITYENV_LD_LIBRARY_PATH: $SINGULARITYENV_LD_LIBRARY_PATH"
echo "[INFO] Starting ParaView..."

###########################################
# Run ParaView inside Singularity
###########################################
singularity exec --nv \
    -B "$HOST_QT_PLUGINS":/qtplugins \
    -B "$HOST_QT_LIBS":/qtlibs \
    -B "$HOST_PY_LIBS":/pylibs \
    -B "$HOST_DBL_LIBS":/dblibs \
    -B "$HOST_ICU_LIBS":/iculibs \
    -B "$HOST_FFMPEG_LIBS":/ffmpeglibs \
    -B "$HOST_X264_LIBS":/x264libs \
    -B "$HOST_SYS_LIB":"$HOST_SYS_LIB" \
    -B "$HOST_SYS_LIB64":"$HOST_SYS_LIB64" \
    -B /opt/software-current:/opt/software-current \
    -B /cvmfs:/cvmfs \
    virtualgl-turbovnc-ros2_latest.sif \
    vglrun "$PV_BIN"



************** also working and gpu utilization*********** 
#!/bin/bash
set -euo pipefail

export DISPLAY=:2
export VGL_DISPLAY=egl

############################################
# Load modules on host
############################################
module use /cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/modules/all
module load ParaView/5.11.2-foss-2023a Qt5/5.15.10-GCCcore-12.3.0

PV_BIN="$(which paraview)"
echo "[INFO] Host ParaView = $PV_BIN"

############################################
# Host library paths
############################################
export HOST_QT_PLUGINS="/opt/software-current/2023.06/x86_64/generic/software/Qt5/5.15.10-GCCcore-12.3.0/plugins"
export HOST_QT_LIBS="/opt/software-current/2023.06/x86_64/generic/software/Qt5/5.15.10-GCCcore-12.3.0/lib"
export HOST_PY_LIBS="/opt/software-current/2023.06/x86_64/generic/software/Python/3.11.3-GCCcore-12.3.0/lib"
export HOST_ICU_LIBS="/opt/software-current/2023.06/x86_64/generic/software/ICU/73.2-GCCcore-12.3.0/lib"

############################################
# Start TurboVNC
############################################
singularity exec --nv \
  -B $HOME/.vnc:$HOME/.vnc \
  virtualgl-turbovnc-ros2_latest.sif \
  /opt/TurboVNC/bin/vncserver :2

echo "[INFO] VNC READY"

############################################
# Start ParaView with correct library paths
############################################
echo "[INFO] Launching ParaView..."

singularity exec --nv \
  --env DISPLAY=:2 \
  --env QT_PLUGIN_PATH=/qtplugins \
  --env QT_QPA_PLATFORM_PLUGIN_PATH=/qtplugins/platforms \
  --env LD_LIBRARY_PATH=/qtlibs:/iculibs:/pylibs:$LD_LIBRARY_PATH \
  -B ${HOST_QT_PLUGINS}:/qtplugins \
  -B ${HOST_QT_LIBS}:/qtlibs \
  -B ${HOST_ICU_LIBS}:/iculibs \
  -B ${HOST_PY_LIBS}:/pylibs \
  -B /opt/software-current:/opt/software-current \
  virtualgl-turbovnc-ros2_latest.sif \
  vglrun "$PV_BIN"

