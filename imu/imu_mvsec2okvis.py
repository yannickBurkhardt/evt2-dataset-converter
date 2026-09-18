import sys

import h5py
import numpy as np

in_path = sys.argv[1]
camera = sys.argv[2]  # "left" or "right"
out_path = sys.argv[3]

assert camera in ("left", "right"), "camera must be 'left' or 'right'"

header = "timestamp(us),gx(rad/s),gy(rad/s),gz(rad/s),ax(m/s^2),ay(m/s^2),az(m/s^2)"

f = h5py.File(in_path, "r")
imu = f[f"davis/{camera}/imu"][:]  # columns: ax, ay, az, gx, gy, gz
imu_ts = f[f"davis/{camera}/imu_ts"][:]  # absolute Unix time in seconds

timestamp_us = np.round(imu_ts * 1e6).astype(np.int64)
ax, ay, az, gx, gy, gz = imu.T

# reorder mvsec's accel-first layout into okvis's gyro-first layout
out_data = np.column_stack([timestamp_us, gx, gy, gz, ax, ay, az])

with open(out_path, "w") as fout:
    fout.write(header + "\n")
    np.savetxt(fout, out_data, fmt=["%d"] + ["%.6f"] * 6, delimiter=",")

print(f"Converted data written to {out_path}")
