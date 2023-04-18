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

scripts_dir=${NEU_dir}/Users/price/dev/bids-proc
bids_root="${NEU_dir}/Data"

#======================================================================================

if [[ $folder_type = "Post-op" ]]; then
    ses_suffix='postop'
else
    ses_suffix=''
fi

## PROCESS ASL SCANS

subj_session_perf_dir=$bids_root/sub-${subj}/ses-research${ses_suffix}/perf

# check for existence of GE ASL directory structure
if [[ -d $raw_session_dir/3d_asl3.0mm ]] || [[ -d $raw_session_dir/3d_asl3.5mm ]]; then

    if [ ! -d $subj_session_perf_dir ]; then
        mkdir -p $subj_session_perf_dir
    fi

    # iterate through different slice thicknesses
    for asl_folder in 3d_asl3.0mm 3d_asl3.5mm; do
        # asl dicom to NIFTI
        if [[ ! -f "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_asl.nii.gz ]] && [[ -d $raw_session_dir/$asl_folder ]]; then
            # run dicom2nii conversion on deltam and m0 dataset
            dcm2niix_afni -o "$subj_session_perf_dir" -z y -f asl_temp "${raw_session_dir}"/$asl_folder
            
            # reshape 4D NIFTI to avoid bids-validation error
            python reshape_ge_asl.py \
                --in_file "$subj_session_perf_dir"/asl_temp_reala.nii.gz    \
                --out_file "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_asl.nii.gz

            # clean directory
            mv "$subj_session_perf_dir"/asl_temp_real.nii.gz "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_m0scan.nii.gz
            mv "$subj_session_perf_dir"/asl_temp_real.json "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_m0scan.json
            rm -f "$subj_session_perf_dir"/asl_temp_reala.nii.gz
            mv "$subj_session_perf_dir"/asl_temp_reala.json "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_asl.json
            cp $scripts_dir/ge_aslcontext.tsv "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_aslcontext.tsv

            # modify .json files
            json_file="$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_asl.json
            jq '.ArterialSpinLabelingType="PCASL"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.M0Type="Separate"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.BackgroundSuppression=true' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.RepetitionTimePreparation=4.7' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.VascularCrushing=false' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.PulseSequenceDetails="GE product 3DASL sequence"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"

            slicemm=${asl_folder:6:3}
            jq '.AcquisitionVoxelSize=['$slicemm','$slicemm','$slicemm']' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"

            json_file="$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_m0scan.json
            jq '.RepetitionTimePreparation=4.7' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
            jq '.AcquisitionVoxelSize=['$slicemm','$slicemm','$slicemm']' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"
        fi
    done

# # check for existence of SIEMENS DTI directory structure
# elif [ -d $raw_session_dir/nih_diff_2mm_45vol ]; then

#     all_files=$(find "$raw_session_dir"/nih_diff_2mm_45vol -iname "*.dcm" | wc -l | xargs)
#     if [ "$all_files" != 7200 ]; then
#         exit
#     fi

#     if [ ! -d $subj_session_perf_dir ]; then
#         mkdir -p $subj_session_perf_dir
#     fi

#     scanner=Siemens

#     for direction in "up" "down"; do
#         if [ ! -f "$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi.nii.gz ]; then
#             # move files to temporary folder
#             mkdir "$subj_session_perf_dir"/temp

#             if [ $direction == 'up' ]; then
#                 for i in "${raw_session_dir}"/nih_diff_2mm_45vol/*-?????.dcm; do ln -s "$i" "$subj_session_perf_dir"/temp; done
#                 cp "${raw_session_dir}"/nih_diff_2mm_45vol/README-Series.txt "$subj_session_perf_dir"/temp
#             else
#                 for i in "${raw_session_dir}"/nih_diff_2mm_45vol/*-?????_v*2.dcm; do ln -s "$i" "$subj_session_perf_dir"/temp; done
#                 cp "${raw_session_dir}"/nih_diff_2mm_45vol/README-Series_v*2.txt "$subj_session_perf_dir"/temp
#             fi

#             # convert dicom to nifti
#             dcm2niix_afni -o "$subj_session_perf_dir" -z y -f sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-${direction}_dwi "$subj_session_perf_dir"/temp
        
#             # clean directory
#             rm -rf "$subj_session_perf_dir"/temp
#             rm -f $subj_session_perf_dir/*.bv??
#         fi
#     done

#     # manually override phase encoding direction in siemens blip up .json sidecar
#     json_file="$subj_session_perf_dir"/sub-"${subj}"_ses-research${ses_suffix}_acq-${scanner}_dir-up_dwi.json
#     jq '.PhaseEncodingDirection="j"' "$json_file" > "${json_file}".tmp && mv "${json_file}".tmp "$json_file"

fi