#!/bin/bash
set -euo pipefail

in_path="$(realpath -m "$1")"
out_path="$(realpath -m "$2")"
# the davis240c is 240x180, and superevent needs both dimensions divisible by 8, so the
# default trims the two outermost rows at the top and bottom. The geometry written into
# the .raw header stays 240x180: the coordinates are not remapped, only filtered
out_shape="240x176"
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

    # reorder "t x y p" to the encoder's "x,y,polarity,t" and keep only the pixels the
    # target shape selects. Done in awk rather than python because this runs over every
    # event of the recording
    awk -v OFS=, -v y0="$roi_y0" -v y1="$roi_y1" -v x0="$roi_x0" -v x1="$roi_x1" -v d="$roi_div" '
        $3 >= y0 && $3 < y1 && ($3 - y0) % d == 0 &&
        $2 >= x0 && $2 < x1 && ($2 - x0) % d == 0 {
            print $2, $3, $4, $1
        }
    ' "$input_file" > "$output_file"
}

# same roi the okvis side would compute for this target shape, so the two agree
read -r roi_y0 roi_y1 roi_x0 roi_x1 roi_div <<< "$(python - "$out_shape" <<'PY'
import sys

from utils.downsample_util import calculate_downsampling_parameters, res_str_to_tuple

p = calculate_downsampling_parameters((180, 240), res_str_to_tuple(sys.argv[1]))
print(p.roi[0] + p.shift(), p.roi[2], p.roi[1] + p.shift(), p.roi[3], p.divisor)
PY
)"
echo "Keeping x in [$roi_x0, $roi_x1) and y in [$roi_y0, $roi_y1) with stride $roi_div"

mkdir -p "$out_path"

for bag_file in "$in_path"/*.bag     # one bag per sequence, as downloaded
do
    if [ ! -f "$bag_file" ]; then
        echo "No *.bag files in $in_path"
        break
    fi

    sequence="$(basename "$bag_file" .bag)"

    if [ -d "$out_path/$sequence" ]; then
        echo "Skipping $sequence (already exists)"
        continue
    fi
    mkdir -p "$out_path/$sequence"

    # bag -> "t x y p" event csv, imu csv and optitrack gt, straight into the output tree
    python rosbag/extract_rpg_bag.py "$bag_file" "$out_path/$sequence"

    # find start timestamp: EVT2 only encodes ~4h46m of range per raw file, so
    # --t-offset-us keeps the encoded timestamps small while recording the true start
    read -r t1 _ < "$out_path/$sequence/cam0/data.csv"
    read -r t2 _ < "$out_path/$sequence/cam1/data.csv"

    if (( t1 < t2 )); then
        first="$t1"
    else
        first="$t2"
    fi

    for camera in cam0 cam1
    do
        convert_csv "$out_path/$sequence/$camera/data.csv" "$out_path/$sequence/$camera/events.csv"
        "$ENCODER" "$out_path/$sequence/$camera/data.raw" "$out_path/$sequence/$camera/events.csv" \
            --t-offset-us "$first" --geometry 240x180
        rm "$out_path/$sequence/$camera/events.csv" "$out_path/$sequence/$camera/data.csv"
    done

    # imu
    python imu/imu_rpg2okvis.py "$out_path/$sequence/imu0/data.csv" "$out_path/$sequence/imu0/okvis.csv"
    mv "$out_path/$sequence/imu0/okvis.csv" "$out_path/$sequence/imu0/data.csv"

    echo "Converted data moved to $out_path/$sequence"
done
