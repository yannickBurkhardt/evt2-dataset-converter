# evt2-dataset-converter

Convert public event-camera datasets into Prophesee **EVT2 `.raw`** files, so recordings
can be replayed through the Metavision SDK as if they came from a live camera.

Each converter goes from the files you download to one directory per sequence:

```
<sequence>/
  cam0/data.raw      left event camera, EVT2
  cam1/data.raw      right event camera, EVT2
  imu0/data.csv      timestamp(us),gx,gy,gz,ax,ay,az
```

## Requirements

### EVT2 encoder

The `.raw` files are written by the EVT2 encoder from
[openeb-soa](https://github.com/yannickBurkhardt/openeb-soa), a fork of
[OpenEB](https://github.com/prophesee-ai/openeb). Build it either way below, then put the
binary on your `PATH` or export `EVT2_ENCODER` as shown.

<details>
<summary><b>Full OpenEB build</b> — what you want if you also run aero-vis</summary>

Install the apt prerequisites listed in
[OpenEB's own instructions](https://github.com/prophesee-ai/openeb#compiling-on-linux),
then from the repository root:

```bash
git clone https://github.com/yannickBurkhardt/openeb-soa.git
cd openeb-soa
mkdir build && cd build
cmake .. -DBUILD_TESTING=OFF -DCOMPILE_PYTHON3_BINDINGS=OFF
cmake --build . --config Release -- -j 4
export EVT2_ENCODER=$PWD/bin/metavision_evt2_raw_file_encoder
```

The standalone samples are part of this build: `BUILD_SAMPLES` defaults to `ON`, so the
encoder ends up in `build/bin/` along with everything else.

</details>

<details>
<summary><b>Encoder only</b> — CMake and a C++17 compiler, nothing else</summary>

The samples under `standalone_samples/` each carry their own `CMakeLists.txt` and include
nothing but the C++ standard library, so the encoder can be built on its own without any of
OpenEB's dependencies:

```bash
git clone https://github.com/yannickBurkhardt/openeb-soa.git
cd openeb-soa/standalone_samples/metavision_evt2_raw_file_encoder
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
export EVT2_ENCODER=$PWD/build/metavision_evt2_raw_file_encoder
```

</details>
<br />

> The fork is needed for `--t-offset-us`, which upstream OpenEB does not have. It records
> the recording's absolute start time in the `.raw` header, which is what keeps events on
> the same clock as `imu0/data.csv`. MVSEC, VECTOR and RPG all use it; TUM-VIE does not and
> works with upstream OpenEB.

### Python environment

```bash
conda create -n evt2 python=3.12
conda activate evt2
pip install -r requirements.txt
```

For RPG only, the bag extraction additionally needs:

```bash
pip install rosbags
```

## Usage

Put everything you downloaded for one dataset into a single folder and run:

```bash
./convert_mvsec.sh   <mvsec_dir>   <out_dir> [WxH]
./convert_vector.sh  <vector_dir>  <out_dir> [WxH]
./convert_tumvie.sh  <tumvie_dir>  <out_dir> [WxH]
./convert_rpg.sh     <rpg_dir>     <out_dir> [WxH]
```

A sequence whose output directory already exists is skipped, so an interrupted run resumes by deleting that one
directory. Anything in the source folder that is not a sequence is skipped with a message.

### The optional shape argument

`WxH` reduces the event stream the way a live event camera would: by **deactivating rows
and columns**, which in our experience is the most practical and efficient way to cut both
the event rate and the resolution. The scripts emulate that in two steps.

1. **Decimate.** Pick the largest integer stride `d` with `d*W <= sensor width` and
   `d*H <= sensor height`, then keep only every `d`-th row and column. This maximises the
   field of view and cuts the event rate by roughly `d^2`.
2. **Crop.** Whatever does not divide evenly is trimmed off as a centred border.

So a target that is close to the sensor size is a pure crop, while one that is half or less
is mostly decimation:

| sensor | target | stride | border trimmed | events kept |
|---|---|---|---|---|
| MVSEC 346x260 | `344x256` | 1 | 2x4 px | all inside the crop |
| RPG 240x180 | `240x176` | 1 | 0x4 px | all inside the crop |
| VECTOR 640x480 | `320x240` | 2 | none | ~1/4 |
| TUM-VIE 1280x720 | `424x240` | 3 | 8x0 px | ~1/9 |

**Coordinates are not remapped and the `.raw` header keeps the native sensor geometry** —
events are only dropped, never moved. Tell the consumer the target shape separately (in
OKVIS, via `downsample_event_stream_resolution_to`) so it applies the matching remap and
adjusts the intrinsics. Both sides derive the stride and border from `WxH` the same way, so
they agree.

Defaults: MVSEC `344x256` and RPG `240x176`, which are pure crops that make both dimensions
divisible by 8 as SuperLitE requires. VECTOR (640x480) and TUM-VIE (1280x720) already are,
so they default to no reduction.

## Datasets

| Dataset | Download | Files per sequence |
|---|---|---|
| [MVSEC](https://daniilidis-group.github.io/mvsec/) | HDF5 per sequence | `<seq>_data.hdf5` |
| [VECTOR](https://star-datasets.github.io/vector/) | "Event" + "IMU" per sequence | `<seq>.synced.left_event.hdf5`, `<seq>.synced.right_event.hdf5`, `<seq>.synced.imu.txt` |
| [TUM-VIE](https://cvg.cit.tum.de/data/datasets/visual-inertial-event-dataset) | events + VI/GT archive | `<seq>-events_left.h5`, `<seq>-events_right.h5`, `<seq>-vi_gt_data.tar.gz` |
| [RPG DAVIS](https://rpg.ifi.uzh.ch/davis_data.html) | ROS bag per sequence | `<seq>.bag` |

Every file name already carries its sequence, so one flat folder per dataset is enough:

```
mvsec_dir/   indoor_flying1_data.hdf5  indoor_flying2_data.hdf5  ...
vector_dir/  corridors_dolly1.synced.left_event.hdf5  corridors_dolly1.synced.imu.txt  ...
tumvie_dir/  mocap-desk2-events_left.h5  mocap-desk2-vi_gt_data.tar.gz  ...
rpg_dir/     boxes1.bag  desk1.bag  ...
```

If your download unpacked into one folder per sequence, flatten it first, e.g.
`find . -mindepth 2 -maxdepth 2 -type f -exec mv -t . {} +`.

Not needed and ignored if present: MVSEC's `_gt.bag` and `calib.txt`, VECTOR's `.gt.txt`,
TUM-VIE's `mocap_data.txt`, RPG's `calib` folder.

## Things to be aware of

- **Timestamps.** Event times are absolute and written to the `.raw` header as
  `% t_offset_us`; the encoded times are relative to it. `imu0/data.csv` is in absolute
  microseconds on the same clock. Both cameras of a sequence share one offset, so the
  stereo pair stays aligned. TUM-VIE timestamps start near zero and carry no offset.
- **Disk.** An intermediate csv of roughly 18-28 bytes per event is written into the output
  directory and removed as each camera finishes, so only one camera's worth exists at a
  time. Budget a few times the source size while a sequence is in flight.
- **Ground truth** is only produced for RPG, as `gt.txt` in TUM format
  (`timestamp tx ty tz qx qy qz qw`, seconds) from the `/optitrack/davis_stereo` topic.
  The other three ship poses in their own formats, which are not converted.
- **No calibration.** These scripts convert events, IMU and (for RPG) poses only. Camera
  intrinsics and extrinsics have to come from the dataset's own calibration.
- **MVSEC** has an IMU per camera, so it also writes `imu1/data.csv` from the right DAVIS.
  Both `T_cam_imu` in the dataset's calibration refer to the *left* IMU, so use `imu0`.
- **VECTOR** output directories use the hyphenated sequence name from the dataset website
  (`corridors_dolly1.synced.*` becomes `corridors-dolly`).
- **TUM-VIE's IMU** lives inside `<seq>-vi_gt_data.tar.gz` next to several GB of jpgs.
  gzip has no random access, so extracting that one member streams the whole archive, which
  can take minutes. If `<seq>-imu_data.txt` or `<seq>/imu_data.txt` already exists next to
  the h5 files it is used instead.
- **RPG** is converted straight from the `.bag`; `rosbag/extract_rpg_bag.py` pulls out the
  event, IMU and optitrack topics first. The two `image_raw` topics are skipped. This step
  needs `rosbags`, which is not in `requirements.txt` — install it separately if you use
  this dataset. No ROS installation is required.
- **Polarity** is normalised to 0/1 in the `.raw` regardless of how the source encodes it.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
