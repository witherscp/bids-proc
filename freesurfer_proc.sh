#!/bin/bash
#====================================================================================================================

# Name: 		freesurfer_proc.sh

# Author:   	Price Withers
# Date:     	4/17/23

#====================================================================================================================

# INPUT

# set usage
function display_usage {
	echo -e "\033[0;35m++ usage: $0 [-h|--help] [-p|--postop] SUBJ ++\033[0m"
	exit 1
}

# set defaults
postop=false

# parse options
while [ -n "$1" ]; do
	case "$1" in
		-h|--help)		display_usage ;; 			# help
		-p|--postop)	postop=true ; shift;;
		*)				subj=$1; break ;;			# subject code (prevent any further shifting by breaking)
	esac
done

# check that only one parameter was given (subj)
if [ ! $# -eq 1 ]; then
	display_usage
fi

#---------------------------------------------------------------------------------------------------------------------

# VARIABLES

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     NEU_dir="/shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be Linux in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

#---------------------------------------------------------------------------------------------------------------------

# SYSTEM CHECK

my_version=$(recon-all -version)
if [[ "${my_version}" == *"-stable-pub-v6.0.0-"* ]]; then
	version=6.0.0
else
	echo -e "\033[0;35m++ Unrecognized FreeSurfer release. Please make sure Freesurfer stable v6.0.0 is installed and setup. Exiting... ++\033[0m"
	exit 1
fi

#---------------------------------------------------------------------------------------------------------------------

bids_root="${NEU_dir}/Data"
derivatives_dir="${bids_root}/derivatives"
fs_dir="${derivatives_dir}/freesurfer-${version}"
registration_qc_dir="$bids_root/derivatives/registration_qc/"

# set variables based on postop flag
if [ $postop = true ]; then
	session_suffix="postop"
else
	session_suffix=""
fi

session=clinical${session_suffix}

if [[ ! -d $bids_root/sub-"$subj"/ses-$session/anat ]]; then
    session=altclinical${session_suffix}
    if [[ ! -d $bids_root/sub-"$subj"/ses-$session/anat ]]; then
        echo -e "\033[0;35m++ Subject does not have ses-clinical${session_suffix} or ses-altclinical${session_suffix} necessary to run Freesurfer. ++\033[0m"
        exit 1
    fi
fi

subj_qc_dir=$registration_qc_dir/sub-${subj}
qc_output_file="$subj_qc_dir"/qc_output.txt
if [[ ! -f $qc_output_file ]]; then
	echo -e "\033[0;35m++ Subject does not have registration qc output file. Please run bids_qc.sh to check whether registration succeeded. Exiting... ++\033[0m"
    exit 1
else
	ses_status=''
	for line in $(cat $qc_output_file); do
        if [[ $line == ses-$session=* ]]; then
            ses_status=$(echo "${line#*'='}" | tr -d '\r' 2>&1)
			break
        fi
    done
	
	if [[ $ses_status == 'success' ]]; then
		echo -e "\033[0;32m++ Subject registration was a success. ++\033[0m"
	elif [[ $ses_status == 'failure' ]]; then
		echo -e "\033[0;35m++ $subj registration failed for ses-$session. Please fix registration before running Freesurfer. Exiting... ++\033[0m"
    	exit 1
	elif [[ $ses_status == '' ]]; then
		echo -e "\033[0;35m++ $subj does not have registration qc output for ses-$session. Please run bids_qc.sh again to check whether registration succeeded. Exiting... ++\033[0m"
    	exit 1
	fi
fi
#---------------------------------------------------------------------------------------------------------------------

# SCRIPT

subj_fs_dir=$fs_dir/sub-${subj}_ses-$session
anat_dir=$bids_root/sub-$subj/ses-$session/anat

if [ -d "${subj_fs_dir}" ]; then
	echo -e "\033[0;35m++ Freesurfer has already been run. Please delete to rerun. ++\033[0m"
elif [[ -f "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz ]] && [[ -f "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T2w.nii.gz  ]]; then
	echo -e "\033[0;32m++ Running Freesurfer with T1 and T2 images. ++\033[0m"
	recon-all \
		-s sub-"${subj}"_ses-$session \
		-sd $fs_dir \
		-all \
		-i "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz \
		-T2 "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T2w.nii.gz \
		-T2pial \
		-contrasurfreg
elif [[ -f "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz ]] && [[ -f "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_FLAIR.nii.gz  ]]; then
	echo -e "\033[0;32m++ Running Freesurfer with T1 and FLAIR images. ++\033[0m"
	recon-all \
		-s sub-"${subj}"_ses-$session \
		-sd $fs_dir \
		-all \
		-i "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz \
		-FLAIR "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_FLAIR.nii.gz \
		-FLAIRpial \
		-contrasurfreg
elif [[ -f "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz ]]; then
	echo -e "\033[0;32m++ Running Freesurfer with T1 image only. ++\033[0m"
	recon-all \
		-s sub-"${subj}"_ses-$session \
		-sd $fs_dir \
		-all \
		-i "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz \
		-contrasurfreg
fi
