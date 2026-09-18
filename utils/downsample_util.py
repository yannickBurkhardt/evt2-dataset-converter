import numpy as np

def res_str_to_tuple(out_str):
    x_pos = out_str.find('x')
    assert x_pos > 0, "Format for out shape must be WxH"
    return (int(out_str[x_pos+1:]), int(out_str[:x_pos]))

class DownsampleParameters:
    def __init__(self, roi, divisor=1):
        """
        roi: [y_min, x_min, y_max, x_max]
        """
        self.roi = roi
        self.divisor = divisor

    def shift(self):
        return (self.divisor - 1) // 2

def keep_events_after_downsampling(x, y, downsample_parameters):
    if downsample_parameters is None:
        return np.ones_like(x, dtype=bool)

    roi = downsample_parameters.roi
    shift = downsample_parameters.shift()
    divisor = downsample_parameters.divisor

    # ROI check
    mask = (
        (y >= roi[0]) & (y < roi[2]) &
        (x >= roi[1]) & (x < roi[3])
    )

    if divisor > 1:
        dx = x - roi[1] - shift
        dy = y - roi[0] - shift

        mask &= (x >= roi[1] + shift) & (y >= roi[0] + shift)
        mask &= (dx % divisor == 0)
        mask &= (dy % divisor == 0)

    return mask

def calculate_downsampling_parameters(shape_in, shape_out):
    """
    shape_in  : (height, width)
    shape_out : (height, width)
    """
    in_h, in_w = shape_in
    out_h, out_w = shape_out

    assert out_h <= in_h
    assert out_w <= in_w

    # Step 1: Maximize FOV -> find largest divisor
    divisor = 2
    while (divisor * out_h <= in_h) and (divisor * out_w <= in_w):
        divisor += 1
    divisor -= 1

    # Step 2: Calculate ROI in center
    crop_px_h = in_h - out_h * divisor
    crop_px_w = in_w - out_w * divisor

    roi = [0, 0, 0, 0]
    roi[0] = crop_px_h // 2
    roi[1] = crop_px_w // 2
    roi[2] = in_h - crop_px_h // 2 - (crop_px_h % 2)
    roi[3] = in_w - crop_px_w // 2 - (crop_px_w % 2)

    return DownsampleParameters(
        roi=roi,
        divisor=divisor
    )

def downsample(t, x, y, p, downsample_parameters):
    mask = keep_events_after_downsampling(x, y, downsample_parameters)
    t = t[mask]
    x = x[mask]
    y = y[mask]
    p = p[mask]

    x = (x - downsample_parameters.roi[1] - downsample_parameters.shift()) // downsample_parameters.divisor
    y = (y - downsample_parameters.roi[0] - downsample_parameters.shift()) // downsample_parameters.divisor

    return t, x, y, p