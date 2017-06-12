#!/bin/bash -l

# Get current working directory
export OUTPUT_ROOT="${PWD}"

# Get source directory of this script
export STAGED_ROOT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Set working directory to home directory
cd "${HOME}"

#
# Launch Fluxbox
#

FLUXBOX_RC_FILE="${OUTPUT_ROOT}/fluxbox.rc"
FLUXBOX_ASSETS_ROOT="${STAGED_ROOT}/fluxbox"

# Create Fluxbox root or it will override the below init file
(
  umask 077
  mkdir -p "${HOME}/.fluxbox"
)

# Build Fluxbox init file
cat > "${FLUXBOX_RC_FILE}" << EOT
session.configVersion: 13
session.screen0.toolbar.widthPercent: 60
session.screen0.toolbar.tools: prevworkspace, workspacename, nextworkspace, iconbar, systemtray, prevwindow, nextwindow, clock
session.menuFile: $FLUXBOX_ASSETS_ROOT/menu
session.keyFile: $FLUXBOX_ASSETS_ROOT/keys
session.styleOverlay: $FLUXBOX_ASSETS_ROOT/overlay
EOT

# Export the module function for the terminal
[[ $(type -t module) == "function" ]] && export -f module

# Start the Fluxbox window manager (it likes to crash on occassion, make it
# persistent)
(
  export FLUXBOX_ASSETS_ROOT="${FLUXBOX_ASSETS_ROOT}"
  until fluxbox -display "${DISPLAY}.0" -rc "${FLUXBOX_RC_FILE}"; do
    echo "Fluxbox crashed with exit code $?. Respawning..." >&2
    sleep 1
  done
) &

#
# Start ANSYS Workbench
#

# Restore the module environment to avoid conflicts
module restore

# Load the ANSYS module
module load ${ANSYS_MODULE}

# Another ANSYS job with the same job name (file) is already running in this
# directory or the file.lock file has not been deleted from an abnormally
# terminated ANSYS run.  To disable this check, set the ANSYS_LOCK environment
# variable to OFF.
export ANSYS_LOCK="OFF"

#
# CFX Related Options
#

# Disable hardware rendering mode
[[ ${ENABLE_VIS} ]] || export CUE_GRAPHICS="mesa"

# Fix bug when running Intel MPI code on OSC
export I_MPI_PMI_EXTENSIONS=on

# Add custom "OSC MPI" as a start method
export CFX5_START_METHODS_CCL="${STAGED_ROOT}/cfx_assets/start-methods.ccl"

# Make a hosts file that CFX will use in Parallel Distributed
mkdir -p "${HOME}/.cfx"
export CFX5_HOSTS_CCL="${HOME}/.cfx/hostinfo.${PBS_JOBID}"
NODES=$(tr '\n' ',' < "${PBS_NODEFILE}" | sed 's/,$//g')
touch "${CFX5_HOSTS_CCL}"
cfx5parhosts -add "${NODES}" -user -file "${CFX5_HOSTS_CCL}"

# Only give OSC MPI option to user through GUI
HOSTINFO=$(head -n -2 "${CFX5_HOSTS_CCL}")
cat > "${CFX5_HOSTS_CCL}" << EOL
${HOSTINFO}
    SOLVER STEP CONTROL:
      Runtime Priority = Standard
      MEMORY CONTROL:
        Memory Allocation Factor = 1.0
      END
      PARALLEL ENVIRONMENT:
        Parallel Host List = ${NODES}
        Start Method = OSC MPI Distributed Parallel
      END
    END
  END # EXECUTION CONTROL
END # SIMULATION CONTROL
EOL

#
# Fluent Related Options
#

# Fluent fix so that is uses pbsrsh set in MPI_REMSH by module load
export HPMPI_MPIRUN_FLAGS="-e MPI_REMSH=$MPI_REMSH"

# Launch ANSYS Workbench
if [[ ${ENABLE_VIS} ]]; then
  module load virtualgl
  vglrun runwb2
else
  runwb2
fi
