import csv
import sys

input_file = sys.argv[1]
output_file = sys.argv[2]

header = [
    "timestamp(us)",
    "gx(rad/s)",
    "gy(rad/s)",
    "gz(rad/s)",
    "ax(m/s^2)",
    "ay(m/s^2)",
    "az(m/s^2)",
]

with open(input_file, "r") as fin, open(output_file, "w", newline="") as fout:
    writer = csv.writer(fout)
    writer.writerow(header)

    for line in fin:
        line = line.strip()

        # skip comments or empty lines
        if not line or line.startswith("#"):
            continue

        parts = line.split(" ")

        # timestamp as integer (microseconds)
        timestamp_us = int(float(parts[0]) * 1e6)
        if timestamp_us < 0:
            continue

        # format IMU values without scientific notation
        imu_values = ["{:.6f}".format(float(x)) for x in parts[1:7]]

        writer.writerow([timestamp_us] + imu_values)

print(f"Converted data written to {output_file}")