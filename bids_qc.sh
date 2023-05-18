#!/bin/bash -i
#====================================================================================================================

# Name: 		bids_qc.sh

# Author:   	Price Withers
# Date:     	5/3/23

#====================================================================================================================

# INPUT

# set usage
function display_usage {
	echo -e "\033[0;35m++ usage: $0 [-h|--help] [-l|--list SUBJ_LIST] [SUBJ [SUBJ ...]] ++\033[0m"
	exit 1
}

#set defaults
subj_list=false

# parse options
while [ -n "$1" ]; do
	# check case; if valid option found, toggle its respective variable on
    case "$1" in
    	-h|--help) 		display_usage ;;	# help
        -l|--list)      subj_list=$2; shift ;; #subject_list
	    *) 				subj=$1; break ;;	# prevent any further shifting by breaking)
    esac
    shift 	# shift to next argument
done

# check if subj_list argument was given; if not, get positional arguments
if [[ ${subj_list} != "false" ]]; then
    #check to see if subj list exist
    if [ ! -f ${subj_list} ]; then
        echo -e "\033[0;35m++ subject_list doesn't exist. ++\033[0m"
        exit 1
    else
        subj_arr=($(cat ${subj_list}))
    fi
else
    subj_arr=("$@")
fi

# check that length of subject list is greater than zero
if [[ ! ${#subj_arr} -gt 0 ]]; then
	echo -e "\033[0;35m++ Subject list length is zero; please specify at least one subject to perform batch processing on ++\033[0m"
	display_usage
fi

#---------------------------------------------------------------------------------------------------------------------

#VARIABLES

unameOut="$(uname -s)"
case "${unameOut}" in
    Darwin*)    NEU_dir="/Volumes/shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be Mac OS in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

bids_root="${NEU_dir}/Data"
registration_qc_dir="$bids_root/derivatives/registration_qc/"

#--------------------------------------------------------------------------------------------------------------------

# REQUIREMENT CHECK

cmd_output=$(which afni)
if [ "$cmd_output" == '' ]; then
	echo -e "\033[0;35m++ AFNI not found. Exiting... ++\033[0m"
	exit 1
fi

#--------------------------------------------------------------------------------------------------------------------

# iterate through subjects
for subj in "${subj_arr[@]}"; do

    echo -e "\033[0;35m++ Working on $subj ++\033[0m"

    if [[ "$subj" = "hv"* ]]; then
        ses_suffix_arr=("")
    else
        ses_suffix_arr=("" "postop")
    fi

    subj_bids_dir=$bids_root/sub-${subj}

    subj_qc_dir=$registration_qc_dir/sub-${subj}
    if [[ ! -d $subj_qc_dir ]]; then
        mkdir "$subj_qc_dir"
    fi

    qc_output_file="$subj_qc_dir"/qc_output.txt
    if [[ -f $qc_output_file ]]; then
        echo -e "\033[0;35m++ Registration QC has already been run on $subj. Do you want to run again and overwrite the previous results? Enter y if yes and n if no. ++\033[0m"
        read -r ynresponse
        ynresponse=$(echo "$ynresponse" | tr '[:upper:]' '[:lower:]')

        if [ "$ynresponse" == "y" ]; then
            echo -e "\033[0;35m++ Running QC on $subj again. ++\033[0m"
            rm -f "$qc_output_file"
        else
            echo -e "\033[0;35m++ OK. Exiting... ++\033[0m"
            exit 1
        fi
    fi

    if [[ ! -d $subj_bids_dir ]]; then
        echo -e "\033[0;35m++ Subject ${subj} does not exist. ++\033[0m"
        continue
    fi

    # iterate over pre-op and post-op raw folders
    for ses_suffix in "${ses_suffix_arr[@]}"; do

        ses_prefix_arr=("" "alt")
        
        # QC clinical anat directories
        for ses_prefix in "${ses_prefix_arr[@]}"; do

            subj_clinical_anat_dir=$subj_bids_dir/ses-${ses_prefix}clinical${ses_suffix}/anat
            if [[ -d $subj_clinical_anat_dir ]]; then
                cd "$subj_clinical_anat_dir" || exit                
                afni
                sleep 5
                echo -e "\033[0;35m++ Are registrations correct for T1, T2 (if available), and FLAIR (if available)? Enter y if correct and n if not. ++\033[0m"
                read -r ynresponse
                ynresponse=$(echo "$ynresponse" | tr '[:upper:]' '[:lower:]')

                if [ "$ynresponse" == "y" ]; then
                    echo -e "\033[0;35m++ Registration correct. Continuing... ++\033[0m"
                    echo "ses-${ses_prefix}clinical${ses_suffix}=success" >> "$qc_output_file"
                else
                    echo -e "\033[0;35m++ Registration not correct. You need to fix registrations for sub-${subj}/ses-${ses_prefix}clinical${ses_suffix}/anat. Continuing... ++\033[0m"
                    echo "ses-${ses_prefix}clinical${ses_suffix}=failure" >> "$qc_output_file"
                fi
            fi

        done

        subj_research_anat_dir=$subj_bids_dir/ses-research${ses_suffix}/anat

        # QC research anat directory
        if [[ -d $subj_research_anat_dir ]]; then
            cd "$subj_research_anat_dir" || exit                
            afni
            sleep 5
            echo -e "\033[0;35m++ Are registrations correct for T1 and T2-fatsat (if available)? Enter y if correct and n if not. ++\033[0m"
            read -r ynresponse
            ynresponse=$(echo "$ynresponse" | tr '[:upper:]' '[:lower:]')

            if [ "$ynresponse" == "y" ]; then
                echo -e "\033[0;35m++ Registration correct. Continuing... ++\033[0m"
                echo "ses-research${ses_suffix}=success" >> "$qc_output_file"
            else
                echo -e "\033[0;35m++ Registration not correct. You need to fix registrations for sub-${subj}/ses-research${ses_suffix}/anat. Continuing... ++\033[0m"
                echo "ses-research${ses_suffix}=failure" >> "$qc_output_file"
            fi
        fi

    done
done