import math
import sys

import h5py
import numpy as np
from tqdm import tqdm

from utils.downsample_util import calculate_downsampling_parameters, keep_events_after_downsampling, res_str_to_tuple

in_path = sys.argv[1]
camera = sys.argv[2]  # "left" or "right"
out_path = sys.argv[3]

assert camera in ("left", "right"), "camera must be 'left' or 'right'"

in_shape = (260, 346)
out_shape = in_shape
if len(sys.argv) > 4 and sys.argv[4]:
    out_shape = res_str_to_tuple(sys.argv[4])
downsample_parameters = calculate_downsampling_parameters(in_shape, out_shape)

data = h5py.File(in_path, "r")[f"davis/{camera}/events"]
data_len = data.shape[0]

chunk_size = 100000
required_chunks = math.ceil(data_len / chunk_size)
with open(out_path, "w") as out_file:
    for i in tqdm(range(required_chunks)):
        chunk = data[i * chunk_size:(i + 1) * chunk_size]

        x_chunk = chunk[:, 0].astype(np.int64)
        y_chunk = chunk[:, 1].astype(np.int64)
        # mvsec stores absolute Unix time in seconds; encoder expects absolute microseconds
        t_chunk = np.round(chunk[:, 2] * 1e6).astype(np.int64)
        # mvsec polarity is -1/1; the raw encoder treats any nonzero p as ON, so remap to 0/1
        p_chunk = (chunk[:, 3] > 0).astype(np.int64)

        # Downsampling: crop to a centered ROI only, coordinates are left unchanged
        mask = keep_events_after_downsampling(x_chunk, y_chunk, downsample_parameters)
        if not np.any(mask):
            continue

        event_chunk = np.vstack([x_chunk[mask], y_chunk[mask], p_chunk[mask], t_chunk[mask]]).T  # openeb format
        np.savetxt(out_file, event_chunk, fmt="%i", delimiter=",", newline="\n")
