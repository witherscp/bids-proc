#!/bin/bash
#====================================================================================================================

# Name: 		bids_proc.sh

# Author:   	Price Withers
# Date:     	3/17/23

#====================================================================================================================

# INPUT

# set usage
function display_usage {
	echo -e "\033[0;35m++ usage: $0 [-h|--help] [--modality [research | clinical | altclinical | meg]] [-l|--list SUBJ_LIST] [SUBJ [SUBJ ...]] ++\033[0m"
	exit 1
}

#set defaults
subj_list=false;
proc_research=true; proc_clinical=true; proc_altclinical=true; proc_meg=true

# parse options
while [ -n "$1" ]; do
	# check case; if valid option found, toggle its respective variable on
    case "$1" in
    	-h|--help) 		display_usage ;;	# help
        --modality)     modality=$2; shift ;; # modality to use
        -l|--list)      subj_list=$2; shift ;; #subject_list
	    *) 				subj=$1; break ;;	# prevent any further shifting by breaking)
    esac
    shift 	# shift to next argument
done

# choose which modalities to process
if [ "$modality" == 'research' ]; then
    proc_clinical=false; proc_altclinical=false; proc_meg=false
elif [ "$modality" == 'clinical' ]; then
    proc_research=false; proc_altclinical=false; proc_meg=false
elif [ "$modality" == 'altclinical' ]; then
    proc_research=false; proc_clinical=false; proc_meg=false
elif [ "$modality" == 'meg' ]; then
    proc_altclinical=false; proc_clinical=false; proc_research=false
fi

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
    Linux*)     NEU_dir="/shares/NEU";;
    Darwin*)    NEU_dir="/Volumes/shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be either Linux or Mac OS in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

scripts_dir=${NEU_dir}/Users/price/dev/bids-proc/scripts
raw_dir="${NEU_dir}/Raw_Data"
raw_clinical_dir="${raw_dir}/Multicontrast_MRI"
raw_altclinical_dir="${raw_dir}/Other_MRI"
raw_research_dir="${raw_dir}/fMRI_DTI"
raw_meg_dir="${raw_dir}/MEG"

key=${NEU_dir}/Scripts_and_Parameters/14N0061_key

#======================================================================================

# iterate through subjects
for subj in "${subj_arr[@]}"; do

    echo -e "\033[0;35m++ Working on $subj ++\033[0m"

    if [[ "$subj" = "hv"* ]]; then
        folder_arr=("Healthy_Volunteers")
    else
        folder_arr=("Patients" "Post-op")
    fi

    # get patient names so you can retrieve their raw dicom path
    for line in $(cat $key); do
        if [[ $line = $subj=* ]]; then
            subj_name=$(echo ${line#*'='} | tr -d '\r' 2>&1)
        fi
    done

    if [[ $subj_name == '' ]]; then
        echo -e "\033[0;35m++ Subject ${subj} does not exist. ++\033[0m"
        exit 1
    fi

    # iterate over pre-op and post-op raw folders
    for folder_type in "${folder_arr[@]}"; do

        subj_raw_research_dir=${raw_research_dir}/${folder_type}/$subj_name
        subj_raw_clinical_dir=${raw_clinical_dir}/${folder_type}/$subj_name/mri
        subj_raw_altclinical_dir=${raw_altclinical_dir}/${folder_type}/$subj_name
        subj_raw_meg_dir=${raw_meg_dir}/${folder_type}/$subj_name

        ## PROCESS RESEARCH SCANS
        if [[ -d $subj_raw_research_dir ]] && [[ $proc_research == "true" ]]; then

            session_dates=( $(ls "$subj_raw_research_dir" ) )
            for session_date in "${session_dates[@]}"; do
                
                raw_session_dir=$subj_raw_research_dir/$session_date

                if [ -d "$raw_session_dir" ]; then

                    bash $scripts_dir/proc_research_anat.sh   \
                        --folder_type "$folder_type"  \
                        --raw_session_dir "$raw_session_dir"  \
                        "$subj"

                    bash $scripts_dir/proc_dwi.sh   \
                        --folder_type "$folder_type"  \
                        --raw_session_dir "$raw_session_dir"  \
                        "$subj"

                    bash $scripts_dir/proc_perf.sh   \
                        --folder_type "$folder_type"  \
                        --raw_session_dir "$raw_session_dir"  \
                        "$subj"

                    bash $scripts_dir/proc_rsfmri.sh   \
                        --folder_type "$folder_type"  \
                        --raw_session_dir "$raw_session_dir"  \
                        "$subj"
                fi
            done
        fi

        ## PROCESS CLINICAL SCANS
        if [[ -d $subj_raw_clinical_dir ]] && [[ $proc_clinical == "true" ]]; then
            
            bash $scripts_dir/proc_clinical_anat.sh \
                --folder_type "$folder_type" \
                --subj_name "$subj_name" \
                "$subj"
        fi

        ## PROCESS ALTERNATE CLINICAL SCANS
        if [[ -d $subj_raw_altclinical_dir ]] && [[ $proc_altclinical == "true" ]]; then
            
            bash $scripts_dir/proc_altclinical_anat.sh \
                --folder_type "$folder_type" \
                --subj_name "$subj_name" \
                "$subj"
        fi

        ## PROCESS MEG SCANS
        if [[ -d $subj_raw_meg_dir ]] && [[ $proc_meg == "true" ]]; then
            
            bash $scripts_dir/proc_meg.sh \
                --folder_type "$folder_type" \
                "$subj"
        fi
    done
done