#!/bin/bash
set -euo pipefail

# Force everything to attach to the TurboVNC display
export DISPLAY=:2
export SINGULARITYENV_DISPLAY=:2

# VirtualGL must attach to the VNC X server
export VGL_DISPLAY=:2

# PBO readback is fastest and prevents black windows
export VGL_READBACK=pbo

# Recommended NVIDIA overrides
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __NV_PRIME_RENDER_OFFLOAD=1

# Load modules
module use /cvmfs/ubuntu_2204.icer.msu.edu/2023.06/x86_64/generic/modules/all
module load ParaView/5.11.2-foss-2023a Qt5/5.15.10-GCCcore-12.3.0

PV_BIN="$(which paraview)"

# Forward host environment into container
export SINGULARITYENV_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
export SINGULARITYENV_QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-}"
export SINGULARITYENV_PATH="$PATH"

# Run ParaView under VirtualGL inside Singularity
singularity exec --nv \
  -B /opt/software-current:/opt/software-current \
  -B /cvmfs:/cvmfs \
  -B /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu \
  -B /lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu \
  -B /lib64:/lib64 \
  virtualgl-turbovnc-ros2_latest.sif \
  vglrun "$PV_BIN"




  ************** ise this*************** 
  export DISPLAY=:1
./paraview_vnc.sh


#  run above code and run pvserver and connect pvserver to vnc session.
#it will be capable of cglrun and pvserver parallel capability
