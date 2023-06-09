#!/bin/bash

#====================================================================================================================

# INPUT

# parse options
while [ -n "$1" ]; do
	# check case; if valid option found, toggle its respective variable on
    case "$1" in
        --folder_type)         folder_type=$2; shift ;;     # modality to use
        --subj_name)           subj_name=$2; shift ;;       #subject_list
	    *) 				       subj=$1; break ;;	        # prevent any further shifting by breaking)
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
raw_dir="${NEU_dir}/Raw_Data"
raw_clinical_dir="${raw_dir}/Multicontrast_MRI"

#======================================================================================

subj_raw_clinical_dir=${raw_clinical_dir}/${folder_type}/$subj_name/mri

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS ANAT SCANS
subj_session_anat_dir=$bids_root/sub-${subj}/ses-clinical${ses_suffix}/anat
subj_source_anat_dir=$sourcedata_dir/sub-${subj}/ses-clinical${ses_suffix}/anat

if [ ! -d $subj_session_anat_dir ]; then
    mkdir -p $subj_session_anat_dir
fi

if [ ! -d $subj_source_anat_dir ]; then
    mkdir -p $subj_source_anat_dir
fi

# anat t1 dicom to nifti
if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz ]] && [[ -d "${subj_raw_clinical_dir}"/mprage ]]; then

    # convert dicom to nifti
    dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_T1w "${subj_raw_clinical_dir}"/mprage

    # check that conversion worked
    if [[ -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T1w.json ]]; then
        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T1w.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.json

        cd "$subj_session_anat_dir" || exit

        # axialize t1 nifti
        fat_proc_axialize_anat                                                  \
            -inset   sub-"${subj}"_ses-clinical${ses_suffix}_T1w.nii.gz           \
            -refset  ${files_dir}/TT_N27+tlrc                 \
            -prefix  sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w_temp    \
            -mode_t1w         							             \
            -extra_al_inps "-nomask"					             \
            -focus_by_ss    \
            -no_qc_view     \
            -no_cmd_out

        # deface scan
        @afni_refacer_run \
            -input sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w_temp.nii.gz \
            -mode_deface \
            -no_images \
            -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz

        # clean directory
        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T1w.nii.gz "$subj_source_anat_dir"
        mv sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w_temp.nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz
        rm sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w_temp_12dof.param.1D
        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.face.nii.gz "$subj_source_anat_dir"
    else
        echo -e "\033[0;35m++ $subj ses-clinical${ses_suffix} T1 conversion failed. ++\033[0m"
    fi
fi

# anat t2 dicom to nifti
if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.nii.gz ]] && [[ -d "${subj_raw_clinical_dir}"/t2 ]]; then

    if [[ ! -f "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.face.nii.gz ]]; then
        echo -e "\033[0;35m++ $subj ses-clinical${ses_suffix} T2 will not be converted to BIDS because T1 conversion failed. ++\033[0m"
    fi

    # convert dicom to nifti
    dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_T2w "${subj_raw_clinical_dir}"/t2

    # check that conversion worked
    if [[ -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T2w.json ]]; then
        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T2w.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.json

        cd "$subj_session_anat_dir" || exit

        3dAllineate \
            -base sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
            -master sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz \
            -input sub-"${subj}"_ses-clinical${ses_suffix}_T2w.nii.gz \
            -cost lpc \
            -source_automask \
            -cmass \
            -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w_temp.nii.gz

        3dcalc \
            -a "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.face.nii.gz   \
            -b sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w_temp.nii.gz     \
            -expr 'iszero(a)*b' \
            -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.nii.gz

        # clean directory
        mv sub-"${subj}"_ses-clinical${ses_suffix}_T2w.nii.gz "$subj_source_anat_dir"
        mv sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w_temp.nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.nii.gz
    else
        echo -e "\033[0;35m++ $subj ses-clinical${ses_suffix} T2 conversion failed. ++\033[0m"
    fi
fi

# anat flair dicom to nifti
if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.nii.gz ]] && [[ -d "${subj_raw_clinical_dir}"/flair ]]; then

    if [[ ! -f "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.face.nii.gz ]]; then
        echo -e "\033[0;35m++ $subj ses-clinical${ses_suffix} FLAIR will not be converted to BIDS because T1 conversion failed. ++\033[0m"
    fi

    # convert dicom to nifti
    dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR "${subj_raw_clinical_dir}"/flair

    # check that conversion worked
    if [[ -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.json ]]; then
        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.json

        cd "$subj_session_anat_dir" || exit

        3dAllineate \
            -base sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
            -master sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz \
            -input sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.nii.gz \
            -cost nmi \
            -source_automask \
            -cmass \
            -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR_temp.nii.gz

        3dcalc \
            -a "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.face.nii.gz   \
            -b sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR_temp.nii.gz     \
            -expr 'iszero(a)*b' \
            -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.nii.gz

        # clean directory
        mv sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.nii.gz "$subj_source_anat_dir"
        mv sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR_temp.nii.gz "$subj_source_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.nii.gz
    else
        echo -e "\033[0;35m++ $subj ses-clinical${ses_suffix} FLAIR conversion failed. ++\033[0m"
    fi
fi