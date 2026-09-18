"""Extract events, imu and optitrack ground truth from an RPG DAVIS .bag.

The RPG dataset ships one ROS bag per sequence, so this is the first step of
convert_rpg.sh. Only the topics the conversion needs are read; the two image_raw
topics in the bag are skipped.

Writes, relative to the output directory:
    cam0/data.csv   t(us) x y polarity, space separated, as convert_rpg.sh expects
    cam1/data.csv
    imu0/data.csv   t(ns),gx,gy,gz,ax,ay,az
    gt.txt          timestamp tx ty tz qx qy qz qw, in seconds (TUM format)
"""

import os
import sys

from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore
from tqdm import tqdm

from pathlib import Path

EVENT_TOPICS = {"/davis_left/events": "cam0", "/davis_right/events": "cam1"}
IMU_TOPIC = "/davis_left/imu"  # the right davis has its own imu, the pipeline uses the left
GT_TOPIC = "/optitrack/davis_stereo"

bag_path = Path(sys.argv[1])
out_dir = sys.argv[2].rstrip("/")

assert bag_path.exists(), f"{bag_path} does not exist"

for sub in ("cam0", "cam1", "imu0"):
    os.makedirs(f"{out_dir}/{sub}", exist_ok=True)

typestore = get_typestore(Stores.ROS1_NOETIC)
counts = {"cam0": 0, "cam1": 0, "imu": 0, "gt": 0}

with AnyReader([bag_path], default_typestore=typestore) as reader:
    wanted = set(EVENT_TOPICS) | {IMU_TOPIC, GT_TOPIC}
    connections = [c for c in reader.connections if c.topic in wanted]
    missing = wanted - {c.topic for c in connections}
    assert not missing & set(EVENT_TOPICS), f"{bag_path} has no event topics: {sorted(missing)}"
    if missing:
        print(f"Warning: {bag_path} has no {sorted(missing)}, those outputs are skipped")

    files = {name: open(f"{out_dir}/{name}/data.csv", "w") for name in ("cam0", "cam1", "imu0")}
    files["gt"] = open(f"{out_dir}/gt.txt", "w")
    files["gt"].write("# timestamp tx ty tz qx qy qz qw\n")

    total = sum(c.msgcount for c in connections)
    for connection, _, rawdata in tqdm(reader.messages(connections=connections), total=total):
        msg = reader.deserialize(rawdata, connection.msgtype)

        if connection.topic in EVENT_TOPICS:
            camera = EVENT_TOPICS[connection.topic]
            # one message carries a whole array of events, so build the block and write once
            files[camera].write("".join(
                f"{1000000 * event.ts.sec + (event.ts.nanosec + 500) // 1000}"
                f" {event.x} {event.y} {int(event.polarity)}\n" for event in msg.events))
            counts[camera] += len(msg.events)

        elif connection.topic == IMU_TOPIC:
            stamp = msg.header.stamp
            values = (msg.angular_velocity.x, msg.angular_velocity.y, msg.angular_velocity.z,
                      msg.linear_acceleration.x, msg.linear_acceleration.y, msg.linear_acceleration.z)
            files["imu0"].write(f"{1000000000 * stamp.sec + stamp.nanosec},"
                                + ",".join(f"{v:.9f}" for v in values) + "\n")
            counts["imu"] += 1

        elif connection.topic == GT_TOPIC:
            stamp = msg.header.stamp
            values = (msg.pose.position.x, msg.pose.position.y, msg.pose.position.z,
                      msg.pose.orientation.x, msg.pose.orientation.y, msg.pose.orientation.z,
                      msg.pose.orientation.w)
            files["gt"].write(f"{stamp.sec + 1e-9 * stamp.nanosec:.9f} "
                              + " ".join(f"{v:.9f}" for v in values) + "\n")
            counts["gt"] += 1

    for f in files.values():
        f.close()

assert counts["cam0"] and counts["cam1"], f"no events extracted from {bag_path}"
print(f"Extracted {counts['cam0']} + {counts['cam1']} events, {counts['imu']} imu samples "
      f"and {counts['gt']} poses to {out_dir}")
