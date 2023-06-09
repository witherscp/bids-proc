#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Created on Thu Apr 20 2023

@author: Price Withers
"""

from argparse import ArgumentParser
import json
from pathlib import Path
import shutil
import sys
from datetime import datetime

from mne import read_trans
from mne.io import read_raw_ctf
from mne_bids import get_anat_landmarks, update_anat_landmarks, write_raw_bids, BIDSPath, update_sidecar_json
import numpy as np

from colors import Colors
from retrieve_emptyroom import nearest, anonymize_date

neu_dir = Path("/Volumes/shares/NEU")
meg_key = neu_dir / "Scripts_and_Parameters/meg_key"
pnum_key = neu_dir / "Scripts_and_Parameters/14N0061_key"
bids_root = neu_dir / 'Data'
fs_dir = bids_root / 'derivatives' / 'freesurfer-6.0.0'

def get_task_dict_and_sessions(data_dir):
    
    runs = []
    
    for meg_session in [d for d in data_dir.iterdir() if d.is_dir()]:
        try:
            run = int(meg_session.stem[-2:])
            runs.append(run)
        except ValueError:
            message = (f"{meg_session} is not a valid directory. It will be ign"
            "ored. If you don't want this to happen, then type ctr"
            "l-c now. Otherwise, hit the return key.")
            input(f"{Colors.PURPLE} {message} {Colors.END}")
            continue
    
    ordered_runs = sorted(runs)
    task_dict = {}
    
    for i, run in enumerate(ordered_runs):
        if i == 0:
            task_dict[run] = 'resteyesopen'
        else:
            task_dict[run] = 'resteyesclosed'
            
    for run,task in task_dict.items():
        print(f'Run {run}: {task}')
    
    resp = input(f'{Colors.PURPLE} Everything look OK? Enter n if not, otherwise hit return.\n {Colors.END}')
    if resp in ["N","n","'n'","'N'"]:
        print('Please type in the correct task for each run (resteyesopen / resteyesclosed).')
        for run in task_dict.keys():
            task_val = input(f'Run {run}: ')
            if task_val not in ('resteyesopen','resteyesclosed'):
                print(Colors.RED, 'Bad input value! Exiting ++', Colors.END)
                sys.exit(1)
            else:
                task_dict[run] = task_val

    final_runs = sorted([k for k,v in task_dict.items() if v == 'resteyesopen'])
    closed_runs = sorted([k for k,v in task_dict.items() if v == 'resteyesclosed'])
    for r in closed_runs:
        final_runs.append(r)

    return task_dict, final_runs

def update_daysback(current_date, new_date=19050101):
    
    date_a = datetime.strptime(str(current_date), "%Y%m%d")
    date_b = datetime.strptime(str(new_date), "%Y%m%d")
    
    difference = date_a - date_b

    return difference.days

if __name__ == "__main__":

    # parse arguments
    purpose = "convert subject MEG data into bids formatting"
    parser = ArgumentParser(description=purpose)
    parser.add_argument("--pnum", help="subject p-number")
    parser.add_argument("--fs_subj", help="sub-{pnum}_ses-{session}")
    parser.add_argument("--files_dir", help="location of daysback.txt")

    args = parser.parse_args()
    pnum = args.pnum
    fs_subj = args.fs_subj
    fs_session = fs_subj.split('_')[-1].split('-')[1]
    files_dir = Path(args.files_dir)

    subj_source_meg_dir = bids_root / 'sourcedata' / f'sub-{pnum}' / 'ses-meg' / 'meg'
    subj_fs_dir = fs_dir / fs_subj
    temp_bids_root = bids_root / f'temp_{pnum}'
    
    if temp_bids_root.is_dir():
        shutil.rmtree(temp_bids_root)
    
    trans_file = subj_fs_dir / 'bem' / f"{fs_subj}-trans.fif"
    if not trans_file.is_file():
        print(
            Colors.RED,
            f"++ {pnum} does not have trans file created. ++",
            Colors.END,
        )
        sys.exit(1)
    trans = read_trans(trans_file)
    
    key_file = subj_source_meg_dir / 'source_to_bids_key.txt'
    if key_file.is_file():
        key_file.unlink()
    
    run2task_dict, final_runs = get_task_dict_and_sessions(subj_source_meg_dir)
    n_eyesopen, n_eyesclosed = 1,1
    
    mri_path = BIDSPath(
        subject=pnum,
        session=fs_session,
        root=bids_root,
        datatype='anat',
        recording='axialized',
        suffix='T1w',
        extension='.nii.gz'
    )
    
    er_dir = bids_root / 'sub-emptyroom'
    er_dates = []
    for er_path in er_dir.glob('ses-*'):
        er_date = int(er_path.stem.split('-')[1])
        er_dates.append(er_date)
        
    daysback=int(np.loadtxt((files_dir / 'daysback.txt')))
    
    task_w_spaces_dict = {
        'resteyesopen': 'rest eyes open',
        'resteyesclosed': 'rest eyes closed'
    }
    
    # iterate through raw session dates
    i = 0
    for meg_run in final_runs:

        # set bids path
        meg_session = next(subj_source_meg_dir.glob(f'????????_epilepsy_????????_*{meg_run}.ds'))
        task = run2task_dict[meg_run]
        
        bids_path = BIDSPath(
            subject=pnum,
            session='meg',
            root=temp_bids_root,
            task=task,
            datatype='meg'
        )
        
        if task == 'resteyesopen':
            bids_path.update(run=n_eyesopen)
            n_eyesopen+=1
        elif task == 'resteyesclosed':
            bids_path.update(run=n_eyesclosed)
            n_eyesclosed+=1
        
        try:
            raw = read_raw_ctf(
                directory=meg_session,
                preload=False
            )
        except OSError:
            raw = read_raw_ctf(
                directory=meg_session,
                preload=False,
                system_clock='ignore'
            )
        except RuntimeError as e:
            if "HPI information not available" in e.args[0]:
                if task == 'resteyesopen':
                    print(
                        Colors.RED,
                        f'Error reading the CTF dataset {meg_session.stem}. Since this was marked as resting state eyes open, all later .ds task markings (eyes open vs. closed) may be wrong. Exiting ...',
                        Colors.END
                    )
                    sys.exit(1)
                elif task == 'resteyesclosed':
                    n_eyesclosed-=1
                continue
        
        # update mri landmarks and retrieve emptyroom path for first run only
        if i==0:
            landmarks = get_anat_landmarks(
                image=mri_path.fpath,
                info=raw.info,
                trans=trans,
                fs_subject=fs_subj,
                fs_subjects_dir=fs_dir
            )
            update_anat_landmarks(
                bids_path=mri_path,
                landmarks=landmarks,
                fs_subject=fs_subj,
                fs_subjects_dir=fs_dir,
                on_missing='ignore'
            )
            
            ses_date = anonymize_date(int(meg_session.stem.split('_')[2]),daysback)
            nearest_er = nearest(items=er_dates, pivot=ses_date)
            nearest_er_fpath = str(BIDSPath(
                root=bids_root,
                subject='emptyroom',
                session=str(nearest_er),
                task='noise',
                datatype='meg',
                extension='.fif'
            ).fpath)
            
            final_er_path = nearest_er_fpath.split(bids_root.stem)[1][1:]
            i+=1
        
        # remove events from bids file
        raw.set_annotations(None)
        raw.info['line_freq'] = 60.0
        
        if ses_date < 19050101:
            daysback = update_daysback(
                current_date=int(meg_session.stem.split('_')[2])
            )
        write_raw_bids(
            raw=raw,
            bids_path=bids_path,
            anonymize={'daysback':daysback,'keep_his':False},
            events=None,
            event_id=None,
            overwrite=True
        )
        
        bids_path.update(extension='.json')
        update_sidecar_json(
            bids_path=bids_path,
            entries={
                'AssociatedEmptyRoom':final_er_path,
                'TaskName':task_w_spaces_dict[task]
            }
        )
        
        with open(key_file, 'a') as f:
            if task == 'resteyesopen':
                f.write(f'{meg_session.stem}, task: {task}, run: {n_eyesopen-1}\n')
            elif task == 'resteyesclosed':
                f.write(f'{meg_session.stem}, task: {task}, run: {n_eyesclosed-1}\n')
        
    # delete unnecessary entries
    json_file = BIDSPath(
        root=temp_bids_root,
        subject=pnum,
        session='meg',
        datatype='meg',
        extension='.json',
        suffix='coordsystem'
    )
    
    mri_json_path = str(mri_path.fpath).split(bids_root.stem)[1][1:]
    update_sidecar_json(
        bids_path=json_file,
        entries={'IntendedFor':mri_json_path}
    )
    
    with open(json_file.fpath, 'r') as f:
        data = json.load(f)
    
    out_data = data.copy()
    for key in data.keys():
        if 'AnatomicalLandmarkCoordinate' in key:
            del out_data[key]

    with open(json_file.fpath, "w") as f:
        json.dump(out_data, f, indent=4)
    
    temp_meg_bids = temp_bids_root / f'sub-{pnum}' / 'ses-meg'
    temp_meg_bids.rename((bids_root / f'sub-{pnum}' / 'ses-meg'))
    
    shutil.rmtree(temp_bids_root)