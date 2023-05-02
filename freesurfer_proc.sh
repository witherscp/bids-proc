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

# SYSTEM CHECK

my_version=$(recon-all -version)
if [[ "${my_version}" == *"-stable-pub-v6.0.0-"* ]]; then
	version=6.0.0
else
	echo -e "\033[0;35m++ Unrecognized FreeSurfer release. Please make sure Freesurfer stable v6.0.0 is installed and setup. Exiting... ++\033[0m"
	exit 1
fi

#---------------------------------------------------------------------------------------------------------------------

# VARIABLES

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     NEU_dir="/shares/NEU";;
	Darwin*)    NEU_dir="/Volumes/Shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be either Linux or Mac OS in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

if [[ "$unameOut" == 'Darwin*' ]]; then
	echo -e "\033[0;35m++ Are you sure that you want to run recon-all on Mac OS? Enter y if yes, anything else if not. ++\033[0m"
	read -r ynresponse
	ynresponse=$(echo "$ynresponse" | tr '[:upper:]' '[:lower:]')

	if [[ "$ynresponse" != 'y' ]]; then
		echo -e "\033[0;35m++ Run in Linux. Exiting... ++\033[0m"
		exit 1
	fi
fi

bids_root="${NEU_dir}/Data"
derivatives_dir="${bids_root}/derivatives"
fs_dir="${derivatives_dir}/freesurfer-${version}"

# set variables based on postop flag
if [ $postop = true ]; then
	session_suffix="postop"
else
	session_suffix=""
fi

session=clinical${session_suffix}

if [ ! -d $bids_root/sub-$subj/ses-$session/anat ]; then
    session=altclinical${session_suffix}
    if [ ! -d $bids_root/sub-$subj/ses-$session/anat ]; then
        echo -e "\033[0;35m++ Subject does not have ses-clinical${session_suffix} necessary to run Freesurfer. ++\033[0m"
        exit 1
    fi
fi
#---------------------------------------------------------------------------------------------------------------------

# SCRIPT

subj_fs_dir=$fs_dir/sub-${subj}_ses-$session
anat_dir=$bids_root/sub-$subj/ses-$session/anat

if [ -d "${subj_fs_dir}" ]; then
	echo -e "\033[0;35m++ Freesurfer has already been run. Please delete to rerun. ++\033[0m"
else
	recon-all \
		-s sub-"${subj}"_ses-$session \
		-sd $fs_dir \
		-all \
		-i "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T1w.nii.gz \
		-T2 "${anat_dir}"/sub-"${subj}"_ses-${session}_rec-axialized_T2w.nii.gz \
		-T2pial \
		-contrasurfreg
fi
