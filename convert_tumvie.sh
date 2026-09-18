#!/bin/bash
set -euo pipefail

in_path="$(realpath -m "$1")"
out_path="$(realpath -m "$2")"
out_shape=""
if [ "$#" == 3 ]; then
    out_shape="$3"
fi

# the helpers are called by relative path, so work from the repository root
cd "$(dirname "$0")"
export PYTHONPATH="${PYTHONPATH:-}:$PWD"

# the encoder ships with openeb as a standalone sample; point EVT2_ENCODER at the
# build output if it is not on PATH. tumvie does not need the --t-offset-us fork
ENCODER="${EVT2_ENCODER:-metavision_evt2_raw_file_encoder}"
if ! command -v "$ENCODER" > /dev/null; then
    echo "EVT2 encoder not found: $ENCODER" >&2
    echo "Build openeb's standalone samples and put it on PATH, or set EVT2_ENCODER (see README)" >&2
    exit 1
fi

mkdir -p "$out_path"

for left_h5 in "$in_path"/*-events_left.h5     # one set of files per sequence
do
    if [ ! -f "$left_h5" ]; then
        echo "No *-events_left.h5 files in $in_path"
        break
    fi

    sequence="$(basename "$left_h5" -events_left.h5)"
    right_h5="$in_path/${sequence}-events_right.h5"
    if [ ! -f "$right_h5" ]; then
        echo "Skipping $sequence (no ${sequence}-events_right.h5)"
        continue
    fi

    if [ -d "$out_path/$sequence" ]; then
        echo "Skipping $sequence (already exists)"
        continue
    fi
    mkdir -p "$out_path/$sequence"/{cam0,cam1,imu0}

    # the imu lives inside <sequence>-vi_gt_data.tar.gz together with several GB of jpgs.
    # Use an already extracted copy when there is one, because gzip has no random access
    # and pulling the one member means streaming the whole archive. Only per-sequence
    # names are accepted: a bare imu_data.txt would be ambiguous in a multi-sequence folder
    imu_txt=""
    for candidate in "$in_path/${sequence}-imu_data.txt" "$in_path/$sequence/imu_data.txt"; do
        if [ -f "$candidate" ]; then
            imu_txt="$candidate"
            break
        fi
    done
    if [ -z "$imu_txt" ]; then
        tarball="$in_path/${sequence}-vi_gt_data.tar.gz"
        if [ ! -f "$tarball" ]; then
            echo "Skipping $sequence (no ${sequence}-imu_data.txt and no ${sequence}-vi_gt_data.tar.gz)"
            rm -r "$out_path/$sequence"
            continue
        fi
        echo "Extracting imu_data.txt from $(basename "$tarball"), this streams the whole archive"
        tar xzf "$tarball" -C "$out_path/$sequence" imu_data.txt
        imu_txt="$out_path/$sequence/imu_data.txt"
    fi

    # cam0 (left)
    python h5/h52txt_tumvie.py "$left_h5" "$out_path/$sequence/cam0/data.csv" "$out_shape"
    "$ENCODER" "$out_path/$sequence/cam0/data.raw" "$out_path/$sequence/cam0/data.csv" --geometry 1280x720
    rm "$out_path/$sequence/cam0/data.csv"

    # cam1 (right)
    python h5/h52txt_tumvie.py "$right_h5" "$out_path/$sequence/cam1/data.csv" "$out_shape"
    "$ENCODER" "$out_path/$sequence/cam1/data.raw" "$out_path/$sequence/cam1/data.csv" --geometry 1280x720
    rm "$out_path/$sequence/cam1/data.csv"

    # imu
    python imu/imu_tumvie2okvis.py "$imu_txt" "$out_path/$sequence/imu0/data.csv"
    rm -f "$out_path/$sequence/imu_data.txt"

    echo "Converted data moved to $out_path/$sequence"
done
