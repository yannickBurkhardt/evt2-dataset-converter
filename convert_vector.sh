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
# build output if it is not on PATH. --t-offset-us requires the fork noted in the README
ENCODER="${EVT2_ENCODER:-metavision_evt2_raw_file_encoder}"
if ! command -v "$ENCODER" > /dev/null; then
    echo "EVT2 encoder not found: $ENCODER" >&2
    echo "Build openeb's standalone samples and put it on PATH, or set EVT2_ENCODER (see README)" >&2
    exit 1
fi

convert_csv() {
    local input_file="$1"
    local output_file="$2"

    # h52txt_vector.py writes space-delimited "t x y p"; reorder to the encoder's "x,y,polarity,t"
    awk -v OFS=, 'NF != 4 { print "Malformed line " NR " in " FILENAME ": <" $0 ">" > "/dev/stderr"; exit 1 }
                  { print $2, $3, $4, $1 }' "$input_file" > "$output_file"
}

mkdir -p "$out_path"

for left_h5 in "$in_path"/*.synced.left_event.hdf5     # one set of files per sequence
do
    if [ ! -f "$left_h5" ]; then
        echo "No *.synced.left_event.hdf5 files in $in_path"
        break
    fi

    # "corridors_dolly1.synced.left_event.hdf5" -> prefix "corridors_dolly1", sequence
    # "corridors-dolly", the name the dataset uses on its website
    prefix="$(basename "$left_h5" .synced.left_event.hdf5)"
    sequence="$(echo "$prefix" | sed -E 's/[0-9]+$//; s/_/-/g')"

    right_h5="$in_path/${prefix}.synced.right_event.hdf5"
    imu_txt="$in_path/${prefix}.synced.imu.txt"
    if [ ! -f "$right_h5" ] || [ ! -f "$imu_txt" ]; then
        echo "Skipping $sequence (missing ${prefix}.synced.right_event.hdf5 or .imu.txt)"
        continue
    fi

    if [ -d "$out_path/$sequence" ]; then
        echo "Skipping $sequence (already exists)"
        continue
    fi
    mkdir -p "$out_path/$sequence"/{cam0,cam1,imu0}

    # h5 -> "t x y p" csv, written into the output tree so the source is never touched
    python h5/h52txt_vector.py "$left_h5"  "$out_path/$sequence/cam0/raw.csv" "$out_shape"
    python h5/h52txt_vector.py "$right_h5" "$out_path/$sequence/cam1/raw.csv" "$out_shape"

    # find start timestamp: EVT2 only encodes ~4h46m of range per raw file, so
    # --t-offset-us keeps the encoded timestamps small while recording the true start
    read -r t1 _ < "$out_path/$sequence/cam0/raw.csv"
    read -r t2 _ < "$out_path/$sequence/cam1/raw.csv"

    if (( t1 < t2 )); then
        first="$t1"
    else
        first="$t2"
    fi

    for camera in cam0 cam1
    do
        convert_csv "$out_path/$sequence/$camera/raw.csv" "$out_path/$sequence/$camera/data.csv"
        "$ENCODER" "$out_path/$sequence/$camera/data.raw" "$out_path/$sequence/$camera/data.csv" \
            --t-offset-us "$first" --geometry 640x480
        rm "$out_path/$sequence/$camera/data.csv" "$out_path/$sequence/$camera/raw.csv"
    done

    # imu
    python imu/imu_vector2okvis.py "$imu_txt" "$out_path/$sequence/imu0/data.csv"

    echo "Converted data moved to $out_path/$sequence"
done
