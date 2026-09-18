#!/bin/bash
set -euo pipefail

in_path="$(realpath -m "$1")"
out_path="$(realpath -m "$2")"
out_shape="344x256"
if [ "$#" == 3 ]; then
    out_shape="$3"
fi

# the helpers are called by relative path, so work from the repository root
cd "$(dirname "$0")"
export PYTHONPATH="${PYTHONPATH:-}:$PWD"

# the encoder ships with openeb as a standalone sample; point EVT2_ENCODER at the
# build output if it is not on PATH. --t-offset-us requires the fork noted in the README
ENCODER="${EVT2_ENCODER:-metavision_evt2_raw_file_encoder}"
if ! command -v "$ENCODER" > /dev/null; then
    echo "EVT2 encoder not found: $ENCODER" >&2
    echo "Build openeb's standalone samples and put it on PATH, or set EVT2_ENCODER (see README)" >&2
    exit 1
fi

mkdir -p "$out_path"

for h5_file in "$in_path"/*_data.hdf5     # list MVSEC sequence files, one per recording
do
    if [ ! -f "$h5_file" ]; then
        echo "No *_data.hdf5 files in $in_path"
        break
    fi

    sequence="$(basename "$h5_file" _data.hdf5)"

    if [ -d "$out_path/$sequence" ]; then
        echo "Skipping $sequence (already exists)"
        continue
    fi
    mkdir -p "$out_path/$sequence"/{cam0,cam1,imu0,imu1}

    # shared start timestamp: EVT2 only encodes ~4h46m of range per raw file, so absolute
    # Unix time cannot be used as-is; --t-offset-us keeps the encoded timestamps small
    # while still recording the true absolute start in the header. Read it from the h5 so
    # only one camera's csv, several GB of it, is on disk at a time
    first="$(python - "$h5_file" <<'PY'
import sys

import h5py

f = h5py.File(sys.argv[1], "r")
print(min(int(round(f[f"davis/{camera}/events"][0, 2] * 1e6)) for camera in ("left", "right")))
PY
)"

    # h5 -> csv (x,y,polarity,t ; absolute t in us). The target shape keeps a centred
    # region and, where a stride fits, every n-th row and column; coordinates are left
    # untouched, so the geometry below stays the native sensor size
    for camera in cam0:left cam1:right
    do
        name="${camera%%:*}"
        side="${camera##*:}"
        python h5/h52txt_mvsec.py "$h5_file" "$side" "$out_path/$sequence/$name/data.csv" "$out_shape"
        "$ENCODER" "$out_path/$sequence/$name/data.raw" "$out_path/$sequence/$name/data.csv" \
            --t-offset-us "$first" --geometry 346x260
        rm "$out_path/$sequence/$name/data.csv"
    done

    # imu0 (left) and imu1 (right); both T_cam_imu of the dataset refer to the left one
    python imu/imu_mvsec2okvis.py "$h5_file" left "$out_path/$sequence/imu0/data.csv"
    python imu/imu_mvsec2okvis.py "$h5_file" right "$out_path/$sequence/imu1/data.csv"

    echo "Converted data moved to $out_path/$sequence"
done
