#!/bin/bash

#====================================================================================================================

# INPUT

# parse options
while [ -n "$1" ]; do
	# check case; if valid option found, toggle its respective variable on
    case "$1" in
        --folder_type)         folder_type=$2; shift ;;
        --raw_session_dir)     raw_session_dir=$2; shift ;;
	    *) 				       subj=$1; break ;;
    esac
    shift 	# shift to next argument
done

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

#======================================================================================

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS DWI SCANS
subj_session_dwi_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/dwi

# check for existence of GE DTI directory structure
if [ -d $raw_session_dir/edti_2mm_45vols_bdown ]; then

    # check to make sure both directions have complete dataset of 3600 files
    bdown_files=$(find $raw_session_dir/edti_2mm_45vols_bdown -iname "*.dcm" | wc -l | xargs)
    bup_files=$(find $raw_session_dir/edti_2mm_45vols_bup -iname "*.dcm" | wc -l | xargs)
    if [[ $bup_files != 3600 ]] || [[ $bdown_files != 3600 ]]; then
        exit
    fi

    if [ ! -d $subj_session_dwi_dir ]; then
        mkdir -p $subj_session_dwi_dir
    fi
    scanner=GE

    # dwi dicom to NIFTI
    for direction in "up" "down"; do
        if [ ! -f "$subj_session_dwi_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi.nii.gz ]; then
            # run dicom2nii conversion on blip up and blip down datasets
            dcm2niix_afni -o "$subj_session_dwi_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi "${raw_session_dir}"/edti_2mm_45vols_b${direction}
            # .bvec and .bval files are already in bids_root directory, so remove them
            rm -f $subj_session_dwi_dir/*.bv??
        fi
    done

# check for existence of SIEMENS DTI directory structure
elif [ -d $raw_session_dir/nih_diff_2mm_45vol ]; then

    all_files=$(find "$raw_session_dir"/nih_diff_2mm_45vol -iname "*.dcm" | wc -l | xargs)
    if [ "$all_files" != 7200 ]; then
        exit
    fi

    if [ ! -d $subj_session_dwi_dir ]; then
        mkdir -p $subj_session_dwi_dir
    fi

    scanner=Siemens

    for direction in "up" "down"; do
        if [ ! -f "$subj_session_dwi_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi.nii.gz ]; then
            # move files to temporary folder
            mkdir "$subj_session_dwi_dir"/temp

            if [ $direction == 'up' ]; then
                for i in "${raw_session_dir}"/nih_diff_2mm_45vol/*-?????.dcm; do ln -s "$i" "$subj_session_dwi_dir"/temp; done
                cp "${raw_session_dir}"/nih_diff_2mm_45vol/README-Series.txt "$subj_session_dwi_dir"/temp
            else
                for i in "${raw_session_dir}"/nih_diff_2mm_45vol/*-?????_v*2.dcm; do ln -s "$i" "$subj_session_dwi_dir"/temp; done
                cp "${raw_session_dir}"/nih_diff_2mm_45vol/README-Series_v*2.txt "$subj_session_dwi_dir"/temp
            fi

            # convert dicom to nifti
            dcm2niix_afni -o "$subj_session_dwi_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi "$subj_session_dwi_dir"/temp
        
            # clean directory
            rm -rf "$subj_session_dwi_dir"/temp
            rm -f $subj_session_dwi_dir/*.bv??
        fi
    done

    # manually override phase encoding direction in siemens blip up .json sidecar
    json_file="$subj_session_dwi_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-up_dwi.json
    jq '.PhaseEncodingDirection="j"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"

fi