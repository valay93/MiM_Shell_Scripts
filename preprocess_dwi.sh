# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

argument_counter=0
step_counter=0
for this_argument in "$@"
do
	if	[[ $argument_counter == 0 ]]; then
    	subject=$this_argument
	else
		preprocessing_steps="$this_argument"
	fi
	
	# Set the path for our custom matlab functions and scripts
	Code_dir=/ufrc/rachaelseidler/tfettrow/Crunch_Code
	
	export MATLABPATH=${Code_dir}/Matlab_Scripts/helper
	
	Subject_dir=/ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/MiM_Data/${subject}
	cd "${Subject_dir}"


   	#if [[ ${preprocessing_steps[*]} =~ "rician_filter" ]]; then
   		# MainDWIDenoising # # 
   		# # arguments  to automate ?? X X
   	#fi

   	if [[ ${preprocessing_steps[*]} =~ "fieldmap_dti" ]]; then
   		Fieldmap_dir=/ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/03_Fieldmaps
		cd ${Fieldmap_dir}/Fieldmap_dti
		rm my_fieldmap.nii
  		rm acqParams.txt
		# Equation for how to find total read out time? ===== #Total readout time (FSL) = (MatrixSizePhase - 1) * EffectiveEchoSpacing ====  (128 - 1) * 0.27999 ==== .0355 seconds
		
		for this_json_file in *.json*; do
								
			total_readout=$(grep "TotalReadoutTime" ${this_json_file} | tr -dc '0.00-9.00')
			encoding_direction=$(grep "PhaseEncodingDirection" ${this_json_file} | cut -d: -f 2 | head -1 | tr -d '"' |  tr -d ',')
			
			this_file_name=$(echo $this_json_file | cut -d. -f 1)
			ml fsl
			this_file_header_info=$(fslhd $this_file_name.nii)
			this_file_number_of_volumes=$(echo $this_file_header_info | grep -o dim4.* | tr -s ' ' | cut -d ' ' -f 2)
			#echo $this_file_number_of_volumes
			for (( this_volume=1; this_volume<=$this_file_number_of_volumes; this_volume++ )); do
				if [[ $encoding_direction =~ j- ]]; then
					echo 0 -1 0 ${total_readout} >> acqParams.txt
				else
					echo 0 1 0 ${total_readout} >> acqParams.txt
				fi
			done
		done

		NVOL=`fslnvols ep2ddiff5B0DT_denoised_68slices`
		for ((i=1; i<=${NVOL}; i+=1)); do indx="$indx 1"; done; echo $indx > index.txt
	
		ml fsl
		fslmerge -t AP_PA_merged ep2ddiff5B0DistMapAP.nii ep2ddiff5B0DistMapPA.nii
		
		# need to remove a slice for even #
		fslsplit AP_PA_merged.nii slice -z
		gunzip *nii.gz*
		rm slice0000.nii
		fslmerge -z AP_PA_merged_68slices slice0*
		rm slice00*.nii
		#
		topup --imain=AP_PA_merged_68slices.nii --datain=acqParams.txt --fout=my_fieldmap --config=b02b0.cnf --iout=se_epi_unwarped --out=topup_results

		fslmaths my_fieldmap -mul 6.28 my_fieldmap_rads
		fslmaths se_epi_unwarped -Tmean my_fieldmap_mask
		bet2 my_fieldmap_mask my_fieldmap_mask_brain
		gunzip *nii.gz*
   	fi
   	if [[ ${preprocessing_steps[*]} =~ "eddy_correction" ]]; then
   		cd /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/03_Fieldmaps/Fieldmap_dti
       
   		cp my_fieldmap_mask_brain.nii /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/08_DWI
		cp my_fieldmap.nii /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/08_DWI
		cp acqParams.txt /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/08_DWI
        cd /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/08_DWI
		
		ml fsl

   		# need to remove  a slice from DWI data
   		fslsplit ep2ddiff5B0DT_denoised slice -z
		# Remove slice 0000 (remove the most inferior slice). Check what this slice looks like before you delete it!
		rm slice0000.nii.gz
		# Merge remaining slices
		fslmerge -z ep2ddiff5B0DT_denoised_68slices slice0*
		## We're done with the remaining inidividual slices so delete them
		rm slice00*.nii.gz
		gunzip *nii.gz*

		NVOL=`fslnvols ep2ddiff5B0DT_denoised_68slices`
		for ((i=1; i<=${NVOL}; i+=1)); do indx="$indx 1"; done; echo $indx > index.txt

		fslmaths ep2ddiff5B0DT_denoised_68slices -Tmean Mean_ep2ddiff5B0DT_denoised_68slices

		flirt -in my_fieldmap_mask_brain.nii -ref Mean_ep2ddiff5B0DT_denoised_68slices.nii -out my_fieldmap_mask_brain_pixAdjust.nii
	
		eddy_openmp --imain=ep2ddiff5B0DT_denoised_68slices --mask=my_fieldmap_mask_brain_pixAdjust --acqp=acqParams.txt --index=index.txt --bvecs=ep2ddiff5B0DT.bvec --bvals=ep2ddiff5B0DT.bval --out=eddy_corrected_data

	fi
	if [[ ${preprocessing_steps[*]} =~ "skull_strip" ]]; then
		cd /ufrc/rachaelseidler/share/FromExternal/Research_Projects_UF/CRUNCH/Pilot_Study_Data/${SUB}/Processed/MRI_files/08_DWI
		ml fsl
		bet2 eddy_corrected_data.nii eddy_corrected_Skullstripped.nii
	fi
done
