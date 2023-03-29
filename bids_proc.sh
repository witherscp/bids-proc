#!/bin/bash
#====================================================================================================================

# Name: 		bids_proc.sh

# Author:   	Price Withers
# Date:     	3/17/23

# Syntax:       ./bids_proc.sh [-h|--help] [-l|--list SUBJ_LIST] [subj1 [subj2 ..]]
# Arguments:    SUBJ: 		   	   subject code(s)
# 				-l SUBJ_LIST:      path to list of subjects to process. if given, all positional arguments will be ignored
# Description:	
# Requirements:

#====================================================================================================================

# INPUT

# set usage
function display_usage {
	echo -e "\033[0;35m++ usage: $0 [-h|--help] [-l|--list SUBJ_LIST] [SUBJ [SUBJ ...]] ++\033[0m"
	exit 1
}

#set defaults
subj_list=false;

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
    Linux*)     NEU_dir="/shares/NEU";;
    Darwin*)    NEU_dir="/Volumes/shares/NEU";;
    *)          echo -e "\033[0;35m++ Unrecognized OS. Must be either Linux or Mac OS in order to run script.\
						 Exiting... ++\033[0m"; exit 1
esac

scripts_file_dir=${NEU_dir}/Scripts_and_Parameters/scripts/__files
bids_root="${NEU_dir}/Data"
sourcedata_dir=${bids_root}/sourcedata
raw_dir="${NEU_dir}/Raw_Data"
raw_clinical_dir="${raw_dir}/Multicontrast_MRI"
raw_altclinical_dir="${raw_dir}/Other_MRI"
raw_research_dir="${raw_dir}/fMRI_DTI"

key=${NEU_dir}/Scripts_and_Parameters/14N0061_key

#======================================================================================

# iterate through subjects
for subj in "${subj_arr[@]}"; do

    echo -e "\033[0;35m++ Working on $subj ++\033[0m"

    if [[ "$subj" = "hv"* ]]; then
        subj_prefix="hv"
        folder_arr=("Healthy_Volunteers")
    else
        subj_prefix="p"
        folder_arr=("Patients" "Post-op")
    fi

    # get patient names so you can retrieve their raw dicom path
    for line in $(cat $key); do
        if [[ $line = $subj=* ]]; then
            subj_name=$(echo ${line#*'='} | tr -d '\r' 2>&1)
        fi
    done

    # iterate over pre-op and post-op raw folders
    for folder_type in "${folder_arr[@]}"; do

        subj_raw_research_dir=${raw_research_dir}/${folder_type}/$subj_name
        subj_raw_clinical_dir=${raw_clinical_dir}/${folder_type}/$subj_name/mri
        subj_raw_altclinical_dir=${raw_altclinical_dir}/${folder_type}/$subj_name

        if [[ $folder_type = "Post-op" ]]; then
            ses_suffix='postop'
        else
            ses_suffix=''
        fi

        ## PROCESS RESEARCH SCANS
        if [ -d $subj_raw_research_dir ]; then

            session_dates=( $(ls "$subj_raw_research_dir" ) )
            for session_date in "${session_dates[@]}"; do
                
                raw_session_dir=$subj_raw_research_dir/$session_date

                if [ -d $raw_session_dir ]; then

                    ## PROCESS DWI SCANS
                    subj_session_dwi_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/dwi

                    # check for existence of GE DTI directory structure
                    if [ -d $raw_session_dir/edti_2mm_45vols_bdown ]; then

                        # check to make sure both directions have complete dataset of 3600 files
                        bdown_files=$(find $raw_session_dir/edti_2mm_45vols_bdown -iname "*.dcm" | wc -l | xargs)
                        bup_files=$(find $raw_session_dir/edti_2mm_45vols_bup -iname "*.dcm" | wc -l | xargs)
                        if [[ $bup_files != 3600 ]] || [[ $bdown_files != 3600 ]]; then
                            continue
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
                    
                        t1_raw_folder=anat_t1w_mp_rage_1mm_pure
                        t1_raw_suffix=""
                        t2_raw_folder=t2fatsat_17mm

                    # check for existence of SIEMENS DTI directory structure
                    elif [ -d $raw_session_dir/nih_diff_2mm_45vol ]; then

                        all_files=$(find "$raw_session_dir"/nih_diff_2mm_45vol -iname "*.dcm" | wc -l | xargs)
                        if [ "$all_files" != 7200 ]; then
                            continue
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

                        t1_raw_folder=t1_memprage-e02
                        t1_raw_suffix=_e2
                        t2_raw_folder=t2_ax_fatsat_1mm

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

                    # anat t1 dicom to nifti
                    if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz ]] && [[ -d "${raw_session_dir}"/"$t1_raw_folder" ]]; then
                        # convert dicom to nifti
                        dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_T1w_temp "${raw_session_dir}"/"$t1_raw_folder"
                        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_T1w_temp"${t1_raw_suffix}".json "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.json

                        cd "$subj_session_anat_dir" || exit

                        # deface scan
                        @afni_refacer_run \
                            -input sub-"${subj}"_ses-research${ses_suffix}_T1w_temp"${t1_raw_suffix}".nii.gz \
                            -mode_deface \
                            -no_images \
                            -prefix sub-"${subj}"_ses-research${ses_suffix}_T1w.nii.gz

                        # axialize t1 nifti
                        fat_proc_axialize_anat                                       \
                            -inset   sub-"${subj}"_ses-research${ses_suffix}_T1w.nii.gz           \
                            -refset  ${scripts_file_dir}/TT_N27+tlrc                 \
                            -prefix  sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w    \
                            -mode_t1w         							             \
                            -extra_al_inps "-nomask"					             \
                            -focus_by_ss    \
                            -no_qc_view     \
                            -no_cmd_out

                        # clean directory
                        rm sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w_12dof.param.1D
                        mv sub-"${subj}"_ses-research${ses_suffix}_T1w.nii.gz "$subj_source_anat_dir"
                        rm sub-"${subj}"_ses-research${ses_suffix}_T1w_temp"${t1_raw_suffix}".nii.gz
                        rm sub-"${subj}"_ses-research${ses_suffix}_T1w.face.nii.gz
                    fi

                    # anat t2_fatsat dicom to nifti
                    if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.nii.gz ]] && [[ -d "${raw_session_dir}"/"$t2_raw_folder" ]]; then
                        # convert dicom to nifti
                        dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w_temp "${raw_session_dir}"/"${t2_raw_folder}"
                        mv "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.json

                        cd "$subj_session_anat_dir" || exit

                        # deface scan
                        @afni_refacer_run \
                            -input sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w_temp.nii.gz \
                            -mode_deface \
                            -no_images \
                            -prefix sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.nii.gz

                        3dAllineate \
                            -base sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz	\
                            -master sub-"${subj}"_ses-research${ses_suffix}_rec-axialized_T1w.nii.gz \
                            -input sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.nii.gz \
                            -cost lpc \
                            -source_automask \
                            -cmass \
                            -prefix sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_rec-axialized_T2w.nii.gz

                        # clean directory
                        mv sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.nii.gz "$subj_source_anat_dir"
                        rm sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w_temp.nii.gz
                        rm sub-"${subj}"_ses-research${ses_suffix}_acq-fatsat_T2w.face.nii.gz
                    fi

                    ## PROCESS fMRI RESTING STATE SCANS
                    subj_session_func_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/func
                    subj_session_fmap_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/fmap

                    # check for existence of GE fMRI directory structure
                    if [ -d $raw_session_dir/epi_3_mm_forward_blip ]; then

                        # TODO: ADD PROCESSING
                        scanner=GE

                    # check for existence of SIEMENS fMRI directory structure
                    elif [ -d $raw_session_dir/epi_forward ]; then

                        if [ ! -d $subj_session_func_dir ]; then
                            mkdir -p $subj_session_func_dir
                        fi
                        if [ ! -d $subj_session_fmap_dir ]; then
                            mkdir -p $subj_session_fmap_dir
                        fi
                        scanner=SIEMENS

                        # func dicom to NIFTI
                        cd "$raw_session_dir" || exit

                        # eyes open
                        eyes_open_runs=( rest_run? )
                        run_num=0
                        for run_name in "${eyes_open_runs[@]}"; do
                            ((run_num+=1))
                            if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-1_bold.nii.gz ]; then
                                # run dicom2nii conversion
                                dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-1_bold "$run_name"
                            fi

                            for echo_num in 2 3; do
                                if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                                    # run dicom2nii conversion
                                    dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold "$run_name"-e0${echo_num}
                                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.json
                                fi
                            done
                        done

                        # eyes closed
                        eyes_closed_runs=( rest_run?_eyes_closed )
                        run_num=0
                        for run_name in "${eyes_closed_runs[@]}"; do
                            ((run_num+=1))
                            if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-1_bold.nii.gz ]; then
                                # run dicom2nii conversion
                                dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-1_bold "$run_name"
                            fi

                            for echo_num in 2 3; do
                                if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                                    # run dicom2nii conversion
                                    dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold "$run_name"-e0${echo_num}
                                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.json
                                fi
                            done
                        done

                        # update .json file taskname attributes
                        cd "$subj_session_func_dir" || exit
                        func_json_files=( *_bold.json )
                        for json_file in "${func_json_files[@]}"; do
                            if [[ $json_file == *task-resteyesclosed_* ]]; then
                                jq '.TaskName="rest eyes closed"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
                            elif [[ $json_file == *task-resteyesopen_* ]]; then
                                jq '.TaskName="rest eyes open"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
                            fi
                        done

                        # fmap dicom to NIFTI
                        for direction in "forward" "reverse"; do
                            if [ ! -f "$subj_session_fmap_dir"/sub-"${subj}"_ses-research${ses_suffix}_dir-${direction}_epi.nii.gz ]; then
                                # run dicom2nii conversion on epi_forward and epi_reverse datasets
                                dcm2niix_afni -o "$subj_session_fmap_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_dir-${direction}_epi "$raw_session_dir"/epi_${direction}
                            fi
                        done

                        func_nifti_files=( *.nii.gz )

                        # update .json file IntendedFor attributes
                        cd "$subj_session_fmap_dir" || exit
                        fmap_json_files=( *_epi.json )

                        for json_file in "${fmap_json_files[@]}"; do
                            jq '.IntendedFor=[]' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
                            for func_nifti_file in "${func_nifti_files[@]}"; do
                                jq '.IntendedFor|= . + ["bids::'$func_nifti_file'"]' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
                            done
                        done
                    fi
                fi
            done
        fi

        ## PROCESS CLINICAL SCANS
        if [ -d $subj_raw_clinical_dir ]; then

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
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_T1w_temp "${subj_raw_clinical_dir}"/mprage
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T1w_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-clinical${ses_suffix}_T1w_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-clinical${ses_suffix}_T1w.nii.gz

                # axialize t1 nifti
                fat_proc_axialize_anat                                       \
                    -inset   sub-"${subj}"_ses-clinical${ses_suffix}_T1w.nii.gz           \
                    -refset  ${scripts_file_dir}/TT_N27+tlrc                 \
                    -prefix  sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w    \
                    -mode_t1w         							             \
                    -extra_al_inps "-nomask"					             \
                    -focus_by_ss    \
                    -no_qc_view     \
                    -no_cmd_out

                # clean directory
                rm sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w_12dof.param.1D
                mv sub-"${subj}"_ses-clinical${ses_suffix}_T1w.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-clinical${ses_suffix}_T1w_temp.nii.gz
                rm sub-"${subj}"_ses-clinical${ses_suffix}_T1w.face.nii.gz
            fi

            # anat t2 dicom to nifti
            if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.nii.gz ]] && [[ -d "${subj_raw_clinical_dir}"/t2 ]]; then
                # convert dicom to nifti
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_T2w_temp "${subj_raw_clinical_dir}"/t2
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_T2w_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-clinical${ses_suffix}_T2w_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-clinical${ses_suffix}_T2w.nii.gz

                3dAllineate \
                    -base sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
                    -master sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz \
                    -input sub-"${subj}"_ses-clinical${ses_suffix}_T2w.nii.gz \
                    -cost nmi \
                    -source_automask \
                    -cmass \
                    -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T2w.nii.gz

                # clean directory
                mv sub-"${subj}"_ses-clinical${ses_suffix}_T2w.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-clinical${ses_suffix}_T2w_temp.nii.gz
                rm sub-"${subj}"_ses-clinical${ses_suffix}_T2w.face.nii.gz
            fi

            # anat flair dicom to nifti
            if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.nii.gz ]] && [[ -d "${subj_raw_clinical_dir}"/flair ]]; then
                # convert dicom to nifti
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR_temp "${subj_raw_clinical_dir}"/flair
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.nii.gz

                3dAllineate \
                    -base sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
                    -master sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_T1w.nii.gz \
                    -input sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.nii.gz \
                    -cost nmi \
                    -source_automask \
                    -cmass \
                    -prefix sub-"${subj}"_ses-clinical${ses_suffix}_rec-axialized_FLAIR.nii.gz

                # clean directory
                mv sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR_temp.nii.gz
                rm sub-"${subj}"_ses-clinical${ses_suffix}_FLAIR.face.nii.gz
            fi
        fi

        ## PROCESS ALTERNATE CLINICAL SCANS
        if [ -d $subj_raw_altclinical_dir ]; then

            ## PROCESS ANAT SCANS
            subj_session_anat_dir=$bids_root/sub-${subj}/ses-altclinical${ses_suffix}/anat
            subj_source_anat_dir=$sourcedata_dir/sub-${subj}/ses-altclinical${ses_suffix}/anat

            if [ ! -d $subj_session_anat_dir ]; then
                mkdir -p $subj_session_anat_dir
            fi

            if [ ! -d $subj_source_anat_dir ]; then
                mkdir -p $subj_source_anat_dir
            fi

            # anat t1 dicom to nifti
            if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.nii.gz ]] && [[ -d "${subj_raw_altclinical_dir}"/t1 ]]; then
                # convert dicom to nifti
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-altclinical${ses_suffix}_T1w_temp "${subj_raw_altclinical_dir}"/t1
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_T1w_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-altclinical${ses_suffix}_T1w_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-altclinical${ses_suffix}_T1w.nii.gz

                # axialize t1 nifti
                fat_proc_axialize_anat                                       \
                    -inset   sub-"${subj}"_ses-altclinical${ses_suffix}_T1w.nii.gz           \
                    -refset  ${scripts_file_dir}/TT_N27+tlrc                 \
                    -prefix  sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w    \
                    -mode_t1w         							             \
                    -extra_al_inps "-nomask"					             \
                    -focus_by_ss    \
                    -no_qc_view     \
                    -no_cmd_out

                # clean directory
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w_12dof.param.1D
                mv sub-"${subj}"_ses-altclinical${ses_suffix}_T1w.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_T1w_temp.nii.gz
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_T1w.face.nii.gz
            fi

            # anat t2 dicom to nifti
            if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T2w.nii.gz ]] && [[ -d "${subj_raw_altclinical_dir}"/t2 ]]; then
                # convert dicom to nifti
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-altclinical${ses_suffix}_T2w_temp "${subj_raw_altclinical_dir}"/t2
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_T2w_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T2w.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-altclinical${ses_suffix}_T2w_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-altclinical${ses_suffix}_T2w.nii.gz

                3dAllineate \
                    -base sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
                    -master sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.nii.gz \
                    -input sub-"${subj}"_ses-altclinical${ses_suffix}_T2w.nii.gz \
                    -cost nmi \
                    -source_automask \
                    -cmass \
                    -prefix sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T2w.nii.gz

                # clean directory
                mv sub-"${subj}"_ses-altclinical${ses_suffix}_T2w.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_T2w_temp.nii.gz
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_T2w.face.nii.gz
            fi

            # anat flair dicom to nifti
            if [[ ! -f "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_FLAIR.nii.gz ]] && [[ -d "${subj_raw_altclinical_dir}"/fl ]]; then
                # convert dicom to nifti
                dcm2niix_afni -o "$subj_session_anat_dir" -z y -f sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR_temp "${subj_raw_altclinical_dir}"/fl
                mv "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR_temp.json "$subj_session_anat_dir"/sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_FLAIR.json

                cd "$subj_session_anat_dir" || exit

                # deface scan
                @afni_refacer_run \
                    -input sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR_temp.nii.gz \
                    -mode_deface \
                    -no_images \
                    -prefix sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR.nii.gz

                3dAllineate \
                    -base sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.nii.gz	\
                    -master sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_T1w.nii.gz \
                    -input sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR.nii.gz \
                    -cost nmi \
                    -source_automask \
                    -cmass \
                    -prefix sub-"${subj}"_ses-altclinical${ses_suffix}_rec-axialized_FLAIR.nii.gz

                # clean directory
                mv sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR.nii.gz "$subj_source_anat_dir"
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR_temp.nii.gz
                rm sub-"${subj}"_ses-altclinical${ses_suffix}_FLAIR.face.nii.gz
            fi
        fi
    done
done