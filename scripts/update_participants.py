#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Created on Fri Apr 28 2023

@author: Price Withers
"""

from argparse import ArgumentParser
from pathlib import Path

import pandas as pd

from colors import Colors

neu_dir = Path("/Volumes/shares/NEU")
bids_root = neu_dir / 'Data'

def add_session_to_dict(session, subj_dict):
    
    if subj_dict[session] == [0]:
        subj_dict[session] = [1]
        
        print(
            Colors.GREEN,
            f'Adding {session} to participants.tsv for {pnum}',
            Colors.END
        )
        
    return subj_dict
    

if __name__ == "__main__":

    # parse arguments
    purpose = "update participants.tsv with new subject"
    parser = ArgumentParser(description=purpose)
    parser.add_argument("pnum", help="subject p-number")

    args = parser.parse_args()
    pnum = args.pnum
    
    print(
        Colors.YELLOW,
        '++ Updating participants.tsv ... ++',
        Colors.END
    )
    
    df = pd.read_csv(
        (bids_root / 'participants.tsv'),
        delimiter='\t',
        keep_default_na=False
    )
    
    if f'sub-{pnum}' in df.participant_id.unique():
        is_new_subject = False
        subj_df = df.loc[df.participant_id == f'sub-{pnum}']
        subj_dict = subj_df.to_dict('list')
    else:
        is_new_subject = True
        subj_dict = {
            'participant_id':[f'sub-{pnum}'],
            'sex':['n/a'],
            'handedness':['n/a'],
            'ses-clinical':[0],
            'ses-clinicalpostop':[0],
            'ses-research':[0],
            'ses-research_anat-t2fatsat':[0],
            'ses-research_dwi':[0],
            'ses-research_perf':[0],
            'ses-research_task-resteyesopen':[0],
            'ses-research_task-resteyesopen_physio':[0],
            'ses-research_task-resteyesclosed':[0],
            'ses-research_task-resteyesclosed_physio':[0],
            'ses-researchpostop':[0],
            'ses-researchpostop_anat-t2fatsat':[0],
            'ses-researchpostop_dwi':[0],
            'ses-researchpostop_perf':[0],
            'ses-researchpostop_task-resteyesopen':[0],
            'ses-researchpostop_task-resteyesopen_physio':[0],
            'ses-researchpostop_task-resteyesclosed':[0],
            'ses-researchpostop_task-resteyesclosed_physio':[0],
            'ses-meg':[0],
            'ses-meg_task-resteyesopen':[0],
            'ses-meg_task-resteyesclosed':[0],
            'ses-megpostop':[0],
            'ses-megpostop_task-resteyesopen':[0],
            'ses-megpostop_task-resteyesclosed':[0],
            'ses-altclinical':[0],
            'ses-altclinical_anat-t1':[0],
            'ses-altclinical_anat-t2':[0],
            'ses-altclinical_anat-flair':[0],
            'ses-altclinicalpostop':[0],
            'ses-altclinicalpostop_anat-t1':[0],
            'ses-altclinicalpostop_anat-t2':[0],
            'ses-altclinicalpostop_anat-flair':[0],
        }
    
    val_options_dict = {
        'sex': [('M','F','n/a'),'M, F, n/a if unknown'],
        'handedness': [('L','R','n/a'),'L, R, n/a if unknown']
    }
    
    subj_path = bids_root / f'sub-{pnum}'
    
    # update session values (1 if present)
    for ses_path in subj_path.glob('ses-*'):
        session = ses_path.stem
        
        if session not in subj_dict.keys():
            continue
        
        subj_dict = add_session_to_dict(session=session,subj_dict=subj_dict)
    
    for ses_suffix in ('', 'postop'):
        
        if subj_dict[('ses-research' + ses_suffix)] == [1]:
            
            # set paths
            ses_path = subj_path / ('ses-research' + ses_suffix)
            anat_path = ses_path / 'anat'
            dwi_path = ses_path / 'dwi'
            perf_path = ses_path / 'perf'
            func_path = ses_path / 'func'
            
            # check for paths
            if len(list(anat_path.glob('*fatsat*T2w*'))) > 0:
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_anat-t2fatsat'),
                    subj_dict=subj_dict
                )

            if dwi_path.is_dir():
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_dwi'),
                    subj_dict=subj_dict
                )

            if perf_path.is_dir():
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_perf'),
                    subj_dict=subj_dict
                )
                
            if len(list(func_path.glob('*resteyesopen*'))) > 0:
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_task-resteyesopen'),
                    subj_dict=subj_dict
                )
                
            if len(list(func_path.glob('*resteyesopen*physio*'))) > 0:
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_task-resteyesopen_physio'),
                    subj_dict=subj_dict
                )
        
            if len(list(func_path.glob('*resteyesclosed*'))) > 0:
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_task-resteyesclosed'),
                    subj_dict=subj_dict
                )
            
            if len(list(func_path.glob('*resteyesclosed*physio*'))) > 0:
                add_session_to_dict(
                    session=('ses-research' + ses_suffix + '_task-resteyesclosed_physio'),
                    subj_dict=subj_dict
                )
        
        if subj_dict[('ses-meg' + ses_suffix)] == [1]:
            
            ses_path = subj_path / ('ses-meg' + ses_suffix)
            meg_path = ses_path / 'meg'
            
            if len(list(meg_path.glob('*resteyesopen*'))) > 0:
                add_session_to_dict(
                    session=('ses-meg' + ses_suffix + '_task-resteyesopen'),
                    subj_dict=subj_dict
                )
        
            if len(list(meg_path.glob('*resteyesclosed*'))) > 0:
                add_session_to_dict(
                    session=('ses-meg' + ses_suffix + '_task-resteyesclosed'),
                    subj_dict=subj_dict
                )
        
        if subj_dict[('ses-altclinical' + ses_suffix)] == [1]:
            
            ses_path = subj_path / ('ses-altclinical' + ses_suffix)
            anat_path = ses_path / 'anat'

            if len(list(anat_path.glob('*T1w*'))) > 0:
                add_session_to_dict(
                    session=('ses-altclinical' + ses_suffix + '_anat-t1'),
                    subj_dict=subj_dict
                )
                
            if len(list(anat_path.glob('*T2w*'))) > 0:
                add_session_to_dict(
                    session=('ses-altclinical' + ses_suffix + '_anat-t2'),
                    subj_dict=subj_dict
                )
                
            if len(list(anat_path.glob('*FLAIR*'))) > 0:
                add_session_to_dict(
                    session=('ses-altclinical' + ses_suffix + '_anat-flair'),
                    subj_dict=subj_dict
                )
    
    # request user for missing values
    for key, val in subj_dict.items():
    
        if val == ['n/a']:
            new_val = input(
                f'Please enter {key} for {pnum} (options are {val_options_dict[key][1]}):\n'
            )

            if new_val in val_options_dict[key][0]:
                subj_dict[key] = [new_val]
                print(
                    Colors.GREEN,
                    f"{key.capitalize()} set to '{new_val}' in participants.tsv for {pnum}",
                    Colors.END
                )
            else:
                print(
                    Colors.RED,
                    f'Failed to enter correct option. Setting {key} to n/a.',
                    Colors.END
                )
    
    # load again in case it has been modified while script is running
    df = pd.read_csv(
        (bids_root / 'participants.tsv'),
        delimiter='\t',
        keep_default_na=False
    )
    
    # delete old version from df
    if not is_new_subject:
        df.drop(df.loc[df.participant_id == f'sub-{pnum}'].index, inplace=True)
    
    append_df = pd.DataFrame(subj_dict)
    out_df = pd.concat([df,append_df], ignore_index=True)
    
    out_df.sort_values(
        by='participant_id',
        inplace=True,
        ascending=True,
        ignore_index=True
    )
    
    out_df.to_csv(
        (bids_root / 'participants.tsv'),
        sep='\t',
        index=False
    )