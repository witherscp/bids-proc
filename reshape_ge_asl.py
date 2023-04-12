#!/usr/bin/env python

import nibabel as nb
from argparse import ArgumentParser

if __name__ == "__main__":

    # parse arguments
    parser = ArgumentParser()
    parser.add_argument(
        "--in_file"
    )
    parser.add_argument(
        "--out_file"
    )

    args = parser.parse_args()
    in_fname = args.in_file
    out_fname = args.out_file

    img = nb.load(in_fname)
    reshaped = img.slicer[:, :, :, None]
    reshaped.to_filename(out_fname)