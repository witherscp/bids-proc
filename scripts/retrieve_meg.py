#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Created on Tue Apr 18 2023

@author: Price Withers
"""

from argparse import ArgumentParser
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

import pandas as pd

from colors import Colors

neu_dir = Path("/Volumes/shares/NEU")
raw_dir = neu_dir / "Raw_Data/MEG/Patients"
ctf_dir = neu_dir / 'Projects/CTF_MEG'
meg_key = neu_dir / "Scripts_and_Parameters/meg_key"
pnum_key = neu_dir / "Scripts_and_Parameters/14N0061_key"
bids_root = neu_dir / 'Data'

# create dictionary to look-up p-numbers
df = pd.read_csv(meg_key, delimiter="=", header=None, names=["meg", "pnum"])
pnum2meg_dict = dict(zip(df.pnum, df.meg))

# create dictionary to look-up subject names
df = pd.read_csv(pnum_key, delimiter="=", header=None, names=["pnum", "name"])
pnum2name_dict = dict(zip(df.pnum, df.name))

if __name__ == "__main__":

    # parse arguments
    purpose = "download emptyroom recording with closest date to subject MEG session"
    parser = ArgumentParser(description=purpose)
    parser.add_argument("pnum", help="subject p-number")

    args = parser.parse_args()
    pnum = args.pnum
    
    subj_name = pnum2name_dict[pnum]
    meg_code = pnum2meg_dict[pnum]
    subj_raw_dir = raw_dir / subj_name
    subj_source_dir = bids_root / 'sourcedata' / f'sub-{pnum}' / 'ses-meg' / 'meg'
    subj_ctf_dir = ctf_dir / pnum / 'CTF'
    
    if len(list(subj_source_dir.glob(f"{meg_code}_epilepsy_????????_*.ds"))) > 0:
        print(Colors.YELLOW, f"++ {pnum} already has MEG data in {subj_source_dir}++", Colors.END)
        sys.exit(1)
    
    # iterate through raw session dates
    for raw_session in [d for d in subj_raw_dir.iterdir() if d.is_dir()]:

        # move .ds directories into orig dir
        for src_dir in raw_session.glob(f"{meg_code}_epilepsy_????????_*.ds"):
            shutil.copytree(src_dir, (subj_source_dir / (src_dir.stem + src_dir.suffix)))

        # if EEGImpedance files exist, move them into separate directory
        impedance_dir = subj_source_dir / "EEG"
        for src_dir in raw_session.glob("*EEGImpedance*.ds"):
            impedance_dir.mkdir(exist_ok=True, parents=True)
            shutil.copytree(src_dir, (impedance_dir / (src_dir.stem + src_dir.suffix)))

        # unzip .meg4 files in each .ds dir
        zipped_files = subj_source_dir.glob("*.ds/*.meg4.bz2")
        for zipped_file in zipped_files:
            cmd = shlex.split(f"bzip2 -d {zipped_file}")
            subprocess.run(cmd)

        # check to see if patient has been Markerfiles
        if subj_ctf_dir.exists():
            # copy MarkerFile.mrk from -c.ds dir
            marker_files = subj_ctf_dir.glob(
                f"{meg_code}_epilepsy_*-c.ds/MarkerFile.mrk"
            )
            for marker_file in marker_files:
                output_stem = marker_file.parent.stem[:-2] + marker_file.parent.suffix
                outfile = subj_source_dir / output_stem / 'MarkerFile.mrk'
                if not outfile.exists():
                    shutil.copy(marker_file, (subj_source_dir / output_stem))
