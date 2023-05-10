#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Created on Tue Apr 18 2023

@author: Price Withers
"""

from argparse import ArgumentParser
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from time import sleep

from nih2mne.calc_mnetrans import coords_from_bsight_txt
import numpy as np
import pandas as pd

from colors import Colors

neu_dir = Path("/Volumes/shares/NEU")
bids_root = neu_dir / 'Data'
meg_dir = neu_dir / 'Projects' / 'MEG'
fs_dir = bids_root / 'derivatives' / 'freesurfer-6.0.0'
meg_key = neu_dir / 'Scripts_and_Parameters' / 'meg_key'
pnum_key = neu_dir / 'Scripts_and_Parameters' / '14N0061_key'

def retrieve_key_dicts(meg_key_path, pnum_key_path):

    # create dictionary to look-up MEG codes
    df = pd.read_csv(meg_key_path, delimiter="=", header=None, names=["meg", "pnum"])
    meg2pnum_dict = dict(zip(df.meg, df.pnum))

    # create dictionary to look-up subject names
    df = pd.read_csv(pnum_key_path, delimiter="=", header=None, names=["pnum", "name"])
    pnum2name_dict = dict(zip(df.pnum, df.name))

    return meg2pnum_dict, pnum2name_dict


def view_afni(
    message="Press return when finished", underlay=None, overlay=None, plugout=False
):

    plugout_str1, plugout_str2 = "", ""
    if plugout:
        plugout_str1 = " -yesplugouts"
        plugout_str2 = " -com 'OPEN_WINDOW A.plugin.Edit_Tagset'"
    underlay_str = ""
    if underlay:
        underlay_str = f" -com 'SWITCH_UNDERLAY {underlay}'"
    overlay_str = ""
    if overlay:
        overlay_str = f" -com 'SWITCH_OVERLAY {overlay}'"

    cmd = shlex.split(f"afni{plugout_str1}{underlay_str}{overlay_str}{plugout_str2}")
    print(cmd)
    subprocess.call(cmd)
    sleep(5)
    user_input = input(f"{Colors.PURPLE} {message} {Colors.END} ")

    return user_input


def check_failure(
    err, errors=["N", "'N'", "n", "'n'"], message="++ Tagset marked as bad. Skipping ++"
):

    if err in errors:
        print(Colors.RED, message, Colors.END)
        sys.exit(1)


def create_null_tag_file():

    # create null.tag file which facilitates tagset labeling
    fids = ["'Nasion'", "'Left Ear'", "'Right Ear'"]
    with open("null.tag", "w") as f:
        for fid in fids:
            f.write(fid + " 0 0 0\n")


if __name__ == "__main__":

    # parse arguments
    purpose = "create -trans.fif file"
    parser = ArgumentParser(description=purpose)
    parser.add_argument("--pnum", help="subject p-number")
    parser.add_argument("--fs_subj", help="sub-{pnum}_ses-{session}")

    args = parser.parse_args()
    pnum = args.pnum
    fs_subj = args.fs_subj
    fs_session = fs_subj.split('_')[-1]
    
    if fs_subj.endswith('postop'):
        postop=True
        ses_suffix='postop'
    else:
        postop=False
        ses_suffix=''

    meg2pnum_dict, _ = retrieve_key_dicts(meg_key, pnum_key)

    subj_fs_dir = fs_dir / fs_subj
    subj_bids_dir = bids_root / f'sub-{pnum}'
    subj_source_dir = bids_root / 'sourcedata' / f'sub-{pnum}'
    subj_source_meg_dir = subj_source_dir / 'ses-meg' / 'meg'
    fs_t1_dir = subj_source_dir / fs_session / 'anat'

    # if subject already has -trans.fif, then skip patient
    trans_file = subj_fs_dir / 'bem' / f"{fs_subj}-trans.fif"
    if trans_file.exists():
        print(Colors.YELLOW, f"++ Trans file already exists for {pnum} ++", Colors.END)
        sys.exit(1)

    # get path to a .ds folder
    if not subj_source_meg_dir.exists():
        print(
            Colors.RED,
            f"++ {pnum} does not have MEG data stored in {subj_source_meg_dir}. ++",
            Colors.END,
        )
        sys.exit(1)
    else:
        ds_dir = next(subj_source_meg_dir.glob("*.ds"))

    # check whether patient has Brainsight available
    subj_brainsight_dir = meg_dir / f"Brainsight/{pnum}"
    brainsight_used = False
    if subj_brainsight_dir.exists():
        brainsight_used = True

    # check whether patient has research Brainsight available
    if not brainsight_used:
        subj_research_brainsight_dir = meg_dir / f"Brainsight/{pnum}_research"
        research_brainsight_used = False
        if subj_research_brainsight_dir.exists():
            research_brainsight_used = True

    if brainsight_used:
        # patient has Brainsight completed
        electrodes_path = subj_brainsight_dir / "Exported_Electrodes.txt"
        if electrodes_path.is_file():
            trans_cmd = shlex.split(
                f"calc_mnetrans.py -subjects_dir {fs_dir} -subject {fs_subj} -dsname {ds_dir} -elec_txt {electrodes_path}"
            )
        else:
            electrodes_path = subj_brainsight_dir / "Exported_Electrodes.tag"
            trans_cmd = shlex.split(
                f"calc_mnetrans.py -subjects_dir {fs_dir} -subject {fs_subj} -dsname {ds_dir} -tagfile {electrodes_path}"
            )
        subprocess.run(trans_cmd)

    elif research_brainsight_used:
        # patient has Brainsight completed but the research scan was used
        # therefore, the coordinates need to be transformed into the clinical
        # space

        # temporarily copy research into clinical directory
        shutil.copy(
            src=(subj_source_dir / f'ses-research{ses_suffix}' / 'anat' / f'sub-{pnum}_ses-research{ses_suffix}_rec-axialized_T1w.nii.gz'),
            dst=fs_t1_dir
        )

        # align research T1 to freesurfer T1 and save out transformation matrix
        os.chdir(fs_t1_dir)
        allineate_cmd = shlex.split(f'3dAllineate -base {fs_subj}_rec-axialized_T1w.nii.gz -input sub-{pnum}_ses-research{ses_suffix}_rec-axialized_T1w.nii.gz -cost lpa -prefix research_aligned2clinical -source_automask -cmass -autoweight -1Dmatrix_save transform.1D')
        subprocess.run(allineate_cmd)

        alignment = view_afni(
            message="Check alignment, then press return when finished or type 'N' if failed.",
            underlay=f'{fs_subj}_rec-axialized_T1w.nii.gz',
            overlay='research_aligned2clinical+orig.BRIK',
        )
        if alignment == 'N':
            print(Colors.RED, f"Alignment failed for {pnum}. Delete files modified in {fs_t1_dir} ++", Colors.END)
            sys.exit(1)

        # read in research coordinates
        electrodes_path = subj_research_brainsight_dir / "Exported_Electrodes.txt"
        coords_dict = coords_from_bsight_txt(electrodes_path)
        fid_xyz_coords = np.array((
            (coords_dict['Nasion']),
            (coords_dict['Left Ear']),
            (coords_dict['Right Ear'])
        ))
        np.savetxt("research_fiducials.1D", X=fid_xyz_coords)

        # transform research coordinates to clinical
        with open('clinical_fiducials.1D', 'w') as f:
            transform_cmd = shlex.split("Vecwarp -matvec transform.1D -backward -input research_fiducials.1D")
            subprocess.run(transform_cmd, stdout=f)

        # prepend labels to each row
        fids = ["'Nasion'","'Left Ear'","'Right Ear'"]
        output_str = ""
        with open('clinical_fiducials.1D', 'r') as f:
            for i, line in enumerate(f):
                output_str += (fids[i] + ' ' + line)

        # write out new clinical fiducials file
        with open('clinical_fiducials.tag','w') as f:
            f.write(output_str)

        # view transformed dataset open clinical_fiducials.tag to make sure they look good, then save into header
        err = view_afni(
            message=(f"Open research_aligned2clinical+orig Dataset, type clinic"
                    "al_fiducials.tag in 'Tag File' and click 'Read', then che"
                    "ck that fiducials are correctly positioned. 'Save' to header when finished then press ret"
                    "urn or type 'N' if failed."),
            underlay='research_aligned2clinical+orig.BRIK',
            plugout=True
        )
        check_failure(err)

        # create -trans.fif file
        trans_cmd = shlex.split(
            f"calc_mnetrans.py -subjects_dir {fs_dir} -subject {fs_subj} -dsname {ds_dir} -afni_mri research_aligned2clinical+orig.BRIK"
        )
        subprocess.run(trans_cmd)

        for file in fs_t1_dir.glob("*fiducials.*"):
            os.remove(file)
        for file in fs_t1_dir.glob("research_aligned2clinical+orig*"):
            os.remove(file)
        for file in fs_t1_dir.glob("transform.1D"):
            os.remove(file)
        os.remove(f'sub-{pnum}_ses-research{ses_suffix}_rec-axialized_T1w.nii.gz')

    else:
        
        # change to subject t1 directory
        os.chdir(fs_t1_dir)
        create_null_tag_file()
        nii_mri_file = f'{fs_subj}_rec-axialized_T1w.nii.gz'
        mri_file_stem = 't1+orig'
        # convert scan from .nii.gz to HEAD/BRIK format
        copy_cmd = shlex.split(f"3dcopy {nii_mri_file} {mri_file_stem}.")
        subprocess.run(copy_cmd)

        # check for fiducial markers in clinical scan and label
        err = view_afni(
            message=(f"If fiducials are present, open {mri_file_stem} Dataset, type "
                     "null.tag in 'Tag File' and click 'Read', reposition labe"
                     "ls, 'Save' to header, then hit return in terminal when finished. O"
                     "therwise, type 'N' and press return."),
            underlay=f'{mri_file_stem}.BRIK',
            plugout=True,
        )

        os.remove("null.tag")
        use_clinical=True

        # no fiducials are available in clinical scan, so check research scan
        if err in ["N", "'N'", "n", "'n'"]:
            
            use_clinical=False
            subj_research_dir = subj_source_dir / f'ses-research{ses_suffix}' / 'anat'
            research_scan = f'sub-{pnum}_ses-research{ses_suffix}_rec-axialized_T1w.nii.gz'
            research_scan_path = subj_research_dir / research_scan

            # no research scans available
            if not research_scan_path.is_file():
                print(
                    Colors.YELLOW,
                    f"++ No research scan available. Opening clinical scan again to label fiducials.++",
                    Colors.END
                )
                os.chdir(fs_t1_dir)
                create_null_tag_file()

                # check for fiducial markers in clinical scan and label
                err = view_afni(
                    message=(f"If fiducials are present, open {mri_file_stem} Dataset, type "
                            "null.tag in 'Tag File' and click 'Read', reposition labe"
                            "ls, 'Save' to header, then hit return in terminal when finished. O"
                            "therwise, type 'N' and press return."),
                    underlay=f'{mri_file_stem}.BRIK',
                    plugout=True,
                )
                
                os.remove("null.tag")
                
                check_failure(
                    err,
                    message=f"++ Quitting out. ++",
                )
                use_clinical=True
            
            # research scan is available
            else:
                # change to research directory
                os.chdir(subj_research_dir)

                # check if patient has fiducials in research scan
                err = view_afni(
                    message="Does patient have fiducials? If yes, press return. Otherwise, type 'N' and press return.",
                    underlay=research_scan,
                )

                # no fiducials in research scan
                if err in ["N", "'N'", "n", "'n'"]:
                    print(
                        Colors.YELLOW,
                        f"++ Opening clinical scan again to label fiducials.++",
                        Colors.END
                    )
                    os.chdir(fs_t1_dir)
                    create_null_tag_file()

                    # label clinical scan
                    err = view_afni(
                        message=(f"If fiducials are present, open {mri_file_stem} Dataset, type "
                                "null.tag in 'Tag File' and click 'Read', reposition labe"
                                "ls, 'Save' to header, then hit return in terminal when finished. O"
                                "therwise, type 'N' and press return."),
                        underlay=f'{mri_file_stem}.BRIK',
                        plugout=True,
                    )
                    
                    os.remove("null.tag")
                    
                    check_failure(
                        err,
                        message=f"++ Quitting out. ++",
                    )
                    
                    use_clinical=True

        # calculate trans from research t1
        if not use_clinical:
            
            # change to research directory
            os.chdir(subj_research_dir)
            
            # convert scan from .nii.gz to HEAD/BRIK format
            copy_cmd = shlex.split(f"3dcopy {research_scan} research+orig.")
            subprocess.run(copy_cmd)
            # move clinical scan into research dir
            copy_cmd = shlex.split(f"3dcopy {fs_t1_dir / nii_mri_file} clinical+orig.")
            subprocess.run(copy_cmd)

            # Align research T1 to clinical T1
            aligned_stem = "research_aligned2clinical+orig"
            allineate_cmd = shlex.split(
                f"3dAllineate -base clinical+orig -input research+orig. -cost lpa -prefix research_aligned2clinical -source_automask -cmass -autoweight"
            )
            subprocess.run(allineate_cmd)
            alignment = view_afni(
                message="Check alignment, then press return when finished or type 'N' if failed.",
                underlay=(fs_t1_dir / nii_mri_file),
                overlay=f"{aligned_stem}.BRIK",
            )
            if alignment == "N":
                print(
                    Colors.RED, f"Alignment failed for {pnum}. Skipping ++", Colors.END
                )
                for suff in [".BRIK", ".HEAD"]:
                    os.remove(f"{aligned_stem}{suff}")
                for file in subj_research_dir.glob("research+orig*"):
                    os.remove(file)
                for file in subj_research_dir.glob("clinical+orig*"):
                    os.remove(file)
                sys.exit(1)

            create_null_tag_file()

            view_afni(
                message=(f"If fiducials are present, open {aligned_stem}.BRIK Dataset, type "
                        "null.tag in 'Tag File' and click 'Read', reposition labe"
                        "ls, 'Save' to header, then hit return in terminal when finished. O"
                        "therwise, type 'N' and press return."),
                underlay=f"{aligned_stem}.BRIK",
                plugout=True,
            )

            os.remove("null.tag")

            # create -trans.fif file
            trans_cmd = shlex.split(
                f"calc_mnetrans.py -subjects_dir {fs_dir} -subject {fs_subj} -dsname {ds_dir} -afni_mri {aligned_stem}.BRIK"
            )
            subprocess.run(trans_cmd)

            for suff in [".BRIK", ".HEAD"]:
                os.remove(f"{aligned_stem}{suff}")
            for file in subj_research_dir.glob("research+orig*"):
                os.remove(file)
            for file in subj_research_dir.glob("clinical+orig*"):
                os.remove(file)
        
        # calculate trans from clinical t1
        else:
            # create -trans.fif file
            trans_cmd = shlex.split(
                f"calc_mnetrans.py -subjects_dir {fs_dir} -subject {fs_subj} -dsname {ds_dir} -afni_mri {mri_file_stem}.BRIK"
            )
            subprocess.run(trans_cmd)
            
        for suff in [".BRIK", ".HEAD"]:
            delete_file = fs_t1_dir / f'{mri_file_stem}{suff}'
            os.remove(delete_file)

    if trans_file.exists():
        print(Colors.GREEN, f"++ Trans file created for {pnum} ++", Colors.END)
    else:
        print(Colors.RED, f"++ Trans file not created for {pnum} ++", Colors.END)
