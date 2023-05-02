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

files_dir=${NEU_dir}/Users/price/dev/bids-proc/files
bids_root="${NEU_dir}/Data"
sourcedata_dir=${bids_root}/sourcedata

#======================================================================================

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS ANAT SCANS
subj_session_anat_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/anat
subj_source_anat_dir=$sourcedata_dir/sub-${subj}/ses-research${ses_suffix}/anat

if [ ! -d $subj_session_anat_dir ]; then
    mkdir -p $subj_session_anat_dir
fi

if [ ! -d $subj_source_anat_dir ]; then
    mkdir -p $subj_source_anat_dir
fi


if [ -d "${raw_session_dir}"/anat_t1w_mp_rage_1mm_pure ]; then
    t1_raw_folder=anat_t1w_mp_rage_1mm_pure
    t1_raw_suffix=""
    t2_raw_folder=t2fatsat_17mm
elif [ -d "${raw_session_dir}"/t1_memprage-e02 ]; then
    t1_raw_folder=t1_memprage-e02
    t1_raw_suffix=_e2
    t2_raw_folder=t2_ax_fatsat_1mm
fi

# anat t1 dicom to nifti
if [ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz ]; then
    # convert dicom to nifti
    dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_T1w "${raw_session_dir}"/"$t1_raw_folder"
    mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_T1w"${t1_raw_suffix}".json "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.json

    cd "$subj_session_anat_dir" || exit

    # axialize t1 nifti
    fat_proc_axialize_anat                                                  \
        -inset   sub-"${subj}"_ses-research${ses_suffix}_T1w"${t1_raw_suffix}".nii.gz           \
        -refset  ${files_dir}/TT_N27+tlrc                 \
        -prefix  sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w_temp    \
        -mode_t1w         							             \
        -extra_al_inps "-nomask"					             \
        -focus_by_ss    \
        -no_qc_view     \
        -no_cmd_out

    # deface scan
    @afni_refacer_run \
        -input sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w_temp.nii.gz \
        -mode_deface \
        -no_images \
        -prefix sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz

    # clean directory
    mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_T1w"${t1_raw_suffix}".nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_T1w.nii.gz
    mv sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w_temp.nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz
    rm sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w_temp_12dof.param.1D
    mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.face.nii.gz "$subj_source_anat_dir"
fi

# anat t2_fatsat dicom to nifti
if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.nii.gz ]] && [[ -d "${raw_session_dir}"/"$t2_raw_folder" ]]; then
    # convert dicom to nifti
    dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w "${raw_session_dir}"/"${t2_raw_folder}"
    mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.json "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.json

    cd "$subj_session_anat_dir" || exit

    3dAllineate \
        -base sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz	\
        -master sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz \
        -input sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.nii.gz \
        -cost lpc \
        -source_automask \
        -cmass \
        -prefix sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w_temp.nii.gz

    3dcalc \
        -a "$subj_source_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.face.nii.gz   \
        -b sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w_temp.nii.gz     \
        -expr 'iszero(a)*b' \
        -prefix sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.nii.gz

    # clean directory
    mv sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.nii.gz "$subj_source_anat_dir"
    mv sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w_temp.nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.nii.gz
fi