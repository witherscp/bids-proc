#!/bin/bash

#====================================================================================================================

# INPUT

# parse options
while [ -n "$1" ]; do
	# check case; if valid option found, toggle its respective variable on
    case "$1" in
        --folder_type)         folder_type=$2; shift ;;
	    *) 				       subj=$1; break ;;
    esac
    shift 	# shift to next argument
done

#--------------------------------------------------------------------------------------------------------------------

# REQUIREMENT CHECK

cmd_output=$(which afni)
if [ "$cmd_output" == '' ]; then
	echo -e "\033[0;35m++ AFNI not found. Exiting... ++\033[0m"
	exit 1
fi
cmd_output=$(which mne)
if [ "$cmd_output" == '' ]; then
	echo -e "\033[0;35m++ MNE-Python not found. Check that your mne environment is active or install using https://mne.tools/stable/install/manual_install.html#manual-install. Exiting... ++\033[0m"
	exit 1
fi
cmd_output=$(which calc_mnetrans.py)
if [ "$cmd_output" == '' ]; then
	echo -e "\033[0;35m++ calc_mnetrans.py not found. Check that your mne environment is active or install with \`pip install git+https://github.com/nih-megcore/nih_to_mne\`. Exiting... ++\033[0m"
	exit 1
fi

#---------------------------------------------------------------------------------------------------------------------

#VARIABLES

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     NEU_dir="/shares/NEU";;
    Darwin*)    NEU_dir="/Volumes/shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be either Linux or Mac OS in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

bids_root="${NEU_dir}/Data"
fs_dir="${bids_root}"/derivatives/freesurfer-6.0.0
scripts_dir=${NEU_dir}/Users/price/dev/bids-proc/scripts
files_dir=${NEU_dir}/Users/price/dev/bids-proc/files

#======================================================================================

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS MEG SCANS
subj_session_meg_dir=$bids_root/sub-${subj}/ses-meg
subj_meg_dir=$subj_session_meg_dir/meg
subj_fs_dir=$fs_dir/sub-${subj}_ses-clinical${ses_suffix}

if [ ! -d $subj_fs_dir ]; then
    subj_fs_dir=$fs_dir/sub-${subj}_ses-altclinical${ses_suffix}
    if [ ! -d $subj_fs_dir ]; then
        echo -e "\033[0;35m++ Subject does not have Freesurfer directory. Run freesurfer_proc.sh. ++\033[0m"
        exit 1
    fi
fi

fs_subj=${subj_fs_dir##*/}
    
# copy all .ds into meg folder
python $scripts_dir/retrieve_meg.py "$subj"

# retrieve emptyroom and convert to bids format
python $scripts_dir/retrieve_emptyroom.py \
    --pnum "$subj"  \
    --files_dir "$files_dir"

# if subject does not have bem files, then run mne_watershed_bem
if [ ! -f "$subj_fs_dir/bem/inner_skull.surf" ]; then
    mne watershed_bem \
        -d $fs_dir \
        -s "$fs_subj"
else
    echo -e "\033[1;33m ++ Bem surfaces already exist for ${subj} ++\033[0m"
fi

# this line is necessary to allow running afni GUI from python script
export DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}:/opt/X11/lib/flat_namespace

# create .trans file
python $scripts_dir/create_trans_meg.py \
    --fs_subj "$fs_subj" \
    --pnum "$subj"

if [ ! -f "$subj_meg_dir"/sub-"${subj}"_ses-meg_task-resteyesclosed_run-01_meg.fif ]; then
    # convert meg to bids format
    python $scripts_dir/convert_meg.py \
        --fs_subj "$fs_subj" \
        --pnum "$subj"  \
        --files_dir "$files_dir"
else
    echo -e "\033[0;35m++ Do you want to delete and re-convert all MEG .ds to fif? Enter y if yes, n if not. ++\033[0m"
    read -r ynresponse
    ynresponse=$(echo "$ynresponse" | tr '[:upper:]' '[:lower:]')

    if [ "$ynresponse" == "y" ]; then

        rm -rf "$subj_session_meg_dir"

        # convert meg to bids format
        python $scripts_dir/convert_meg.py \
            --fs_subj "$fs_subj" \
            --pnum "$subj"  \
            --files_dir "$files_dir"
    else
        exit 1
    fi
fi