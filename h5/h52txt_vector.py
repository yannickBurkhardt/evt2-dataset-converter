import numpy as np
import h5py
import hdf5plugin
import math
import sys
from tqdm import tqdm
from utils.downsample_util import *

in_shape = (480, 640)
out_shape = in_shape
if len(sys.argv) > 3 and sys.argv[3]:
    out_shape = res_str_to_tuple(sys.argv[3])
downsample_parameters = calculate_downsampling_parameters(in_shape, out_shape)

in_path = sys.argv[1]
out_path = sys.argv[2]
data=h5py.File(in_path, 'r')
t_offset = data["t_offset"][0]
data = data["events"]
data_len=len(data["t"])

out_file = open(out_path, "w")

chunk_size = 100000
required_chunks = math.ceil(data_len / chunk_size)
for i in tqdm(range(required_chunks)):
    t_chunk = np.array(data["t"][i*chunk_size:(i+1)*chunk_size] + t_offset, dtype=np.int64)
    x_chunk = np.array(data["x"][i*chunk_size:(i+1)*chunk_size], dtype=np.int64)
    y_chunk = np.array(data["y"][i*chunk_size:(i+1)*chunk_size], dtype=np.int64)
    p_chunk = np.array(data["p"][i*chunk_size:(i+1)*chunk_size], dtype=np.int64)

    # Downsampling
    mask = keep_events_after_downsampling(x_chunk, y_chunk, downsample_parameters)

    event_chunk = np.vstack([
        t_chunk[mask],
        x_chunk[mask],
        y_chunk[mask],
        p_chunk[mask]
    ]).T
    np.savetxt(out_file, event_chunk, fmt='%i', delimiter=" ", newline="\n")
