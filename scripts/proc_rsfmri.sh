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

cmd_output=$(which dcm2niix)
if [ "$cmd_output" == '' ]; then
	echo -e "\033[0;35m++ Dcm2niix not found. Run \`python -m pip install dcm2niix\` in your active environment. Exiting... ++\033[0m"
	exit 1
fi

scripts_dir=${NEU_dir}/Users/price/dev/bids-proc/scripts
files_dir=${NEU_dir}/Users/price/dev/bids-proc/files
bids_root="${NEU_dir}/Data"

#======================================================================================

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS fMRI RESTING STATE SCANS
subj_session_func_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/func
subj_session_fmap_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/fmap

# check for existence of GE fMRI directory structure
if [[ -d $raw_session_dir/epi_3_mm_forward_blip ]] && [[ -d $raw_session_dir/epi_3_mm_reverse_blip ]]; then

    if [ ! -d $subj_session_func_dir ]; then
        mkdir -p $subj_session_func_dir
    fi
    if [ ! -d $subj_session_fmap_dir ]; then
        mkdir -p $subj_session_fmap_dir
    fi
    
    new_files=false

    # eyes open
    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-1_echo-1_bold.nii.gz ]; then
        cd "$raw_session_dir" || exit
        eyes_open_runs=( epi_3_mm_rest_run_? )
        run_num=0
        for run_name in "${eyes_open_runs[@]}"; do
            if [ -d "$run_name" ]; then
                ((run_num+=1))

                # run Vinai's sortme script and dicom2nii conversion
                raw_func_folder=$raw_session_dir/$run_name
                if [ -d "$raw_func_folder"/echo_0001 ]; then
                    python $scripts_dir/sortme.py "$raw_func_folder" 'dcm' 'true'
                else
                    python $scripts_dir/sortme.py "$raw_func_folder"
                fi

                for echo_num in 1 2 3; do
                    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                        new_files=true
                        mv $raw_func_folder/echo_000${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.json
                        mv $raw_func_folder/echo_000${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                    fi
                done
            fi
        done
    fi

    # eyes closed
    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-1_echo-1_bold.nii.gz ]; then
        cd "$raw_session_dir" || exit
        eyes_closed_runs=( epi_3_mm_rest_run_?_eyes_closed )
        run_num=0
        for run_name in "${eyes_closed_runs[@]}"; do
            if [ -d "$run_name" ]; then
                ((run_num+=1))

                # run Vinai's sortme script and dicom2nii conversion
                raw_func_folder=$raw_session_dir/$run_name
                if [ -d "$raw_func_folder"/echo_0001 ]; then
                    python $scripts_dir/sortme.py "$raw_func_folder" 'dcm' 'true'
                else
                    python $scripts_dir/sortme.py "$raw_func_folder"
                fi

                for echo_num in 1 2 3; do
                    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                        new_files=true
                        mv $raw_func_folder/echo_000${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.json
                        mv $raw_func_folder/echo_000${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                    fi
                done
            fi
        done
    fi

    # only update .json files, create physio files, and create fmap files if new resting state files are created
    if [[ $new_files == 'true' ]]; then
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
        for direction in "reverse" "forward"; do
            if [ ! -f "$subj_session_fmap_dir"/sub-"${subj}"_ses-research${ses_suffix}_dir-${direction}_epi.nii.gz ]; then
                # run Vinai's sortme script and dicom2nii conversion
                raw_fmap_folder=$raw_session_dir/epi_3_mm_${direction}_blip
                if [ -d "$raw_fmap_folder"/echo_0001 ]; then
                    python $scripts_dir/sortme.py "$raw_fmap_folder" 'dcm' 'true'
                else
                    python $scripts_dir/sortme.py "$raw_fmap_folder"
                fi

                mv $raw_fmap_folder/echo_0001.json "$subj_session_fmap_dir"/sub-"${subj}"_ses-research${ses_suffix}_dir-${direction}_epi.json
                mv $raw_fmap_folder/echo_0001.nii.gz "$subj_session_fmap_dir"/sub-"${subj}"_ses-research${ses_suffix}_dir-${direction}_epi.nii.gz

                # clean directory
                rm $raw_fmap_folder/echo_0002.json; rm $raw_fmap_folder/echo_0002.nii.gz
                rm $raw_fmap_folder/echo_0003.json; rm $raw_fmap_folder/echo_0003.nii.gz
            fi
        done

        # update .json file IntendedFor attributes
        cd "$subj_session_func_dir" || exit
        func_nifti_files=( *.nii.gz )

        cd "$subj_session_fmap_dir" || exit
        fmap_json_files=( *_epi.json )

        for json_file in "${fmap_json_files[@]}"; do
            jq '.IntendedFor=[]' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            for func_nifti_file in "${func_nifti_files[@]}"; do
                jq '.IntendedFor|= . + ["bids::'$func_nifti_file'"]' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            done
        done

        # physio data
        has_physio=false
        if [ -d $raw_session_dir/resources/supplementary ]; then
            physio_dir=$raw_session_dir/resources/supplementary
            has_physio=true
        elif [ -d $raw_session_dir/realtime ]; then
            physio_dir=$raw_session_dir/realtime
            has_physio=true
        fi

        if [ $has_physio == 'true' ]; then
            ecg_files=( "$physio_dir"/ECG_*.1D )
            open_run_num=0; closed_run_num=0

            for ecg_file in "${ecg_files[@]}"; do
                n_timepoints=$(wc -l < "$ecg_file" | xargs)
                ecg_file_name=${ecg_file##*/}
                resp_file=$physio_dir/Resp_${ecg_file_name#*_}

                # resting state eyes open
                if [ "$n_timepoints" == 19375 ]; then
                    ((open_run_num+=1))
                    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-${open_run_num}_physio.tsv.gz ]; then
                        paste "$ecg_file" "$resp_file" | gzip > "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-${open_run_num}_physio.tsv.gz
                        cp $files_dir/ge_physio.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-${open_run_num}_physio.json
                    fi
                fi

                # resting state eyes closed
                if [ "$n_timepoints" == 38750 ]; then
                    ((closed_run_num+=1))
                    if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-${open_run_num}_physio.tsv.gz ]; then
                        paste "$ecg_file" "$resp_file" | gzip > "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-${open_run_num}_physio.tsv.gz
                        cp $files_dir/ge_physio.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-${open_run_num}_physio.json
                    fi
                fi

                if [[ $open_run_num -gt 1 ]] || [[ $closed_run_num -gt 1 ]]; then
                    echo -e "\033[0;35m++ $open_run_num eyes open runs and $closed_run_num eyes closed runs detected. There may have been a problem in physio data conversion, so please check raw data files and compare with outputs. ++\033[0m"
                fi
            done
        fi
    fi

# check for existence of SIEMENS fMRI directory structure
elif [[ -d $raw_session_dir/epi_forward ]] && [[ -d $raw_session_dir/epi_reverse ]]; then

    if [ ! -d $subj_session_func_dir ]; then
        mkdir -p $subj_session_func_dir
    fi
    if [ ! -d $subj_session_fmap_dir ]; then
        mkdir -p $subj_session_fmap_dir
    fi

    # func dicom to NIFTI
    cd "$raw_session_dir" || exit

    new_files=false

    # eyes open
    eyes_open_runs=( rest_run? )
    run_num=0
    for run_name in "${eyes_open_runs[@]}"; do
        if [ -d "$run_name" ]; then
            ((run_num+=1))
            if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-1_bold.nii.gz ]; then
                # run dicom2nii conversion
                dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-1_bold "$run_name"
            fi

            for echo_num in 2 3; do
                if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                    # run dicom2nii conversion
                    dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold "$run_name"-e0${echo_num}
                    new_files=true
                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesopen_run-"${run_num}"_echo-${echo_num}_bold.json
                fi
            done
        fi
    done

    # eyes closed
    eyes_closed_runs=( rest_run?_eyes_closed )
    run_num=0
    for run_name in "${eyes_closed_runs[@]}"; do
        if [ -d "$run_name" ]; then
            ((run_num+=1))
            if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-1_bold.nii.gz ]; then
                # run dicom2nii conversion
                dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-1_bold "$run_name"
            fi

            for echo_num in 2 3; do
                if [ ! -f "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz ]; then
                    # run dicom2nii conversion
                    dcm2niix_afni -o "$subj_session_func_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold "$run_name"-e0${echo_num}
                    new_files=true
                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.nii.gz "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.nii.gz
                    mv "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold_e${echo_num}.json "$subj_session_func_dir"/sub-"${subj}"_ses-research${ses_suffix}_task-resteyesclosed_run-"${run_num}"_echo-${echo_num}_bold.json
                fi
            done
        fi
    done

    # only update .json files and create fmap files if new resting state files are created
    if [[ $new_files == 'true' ]]; then
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