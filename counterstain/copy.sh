#!/bin/bash
set -x -e

# Point to the latest Greedy and c3d 
export PATH=/Users/pauly/tk/lddmm/xc64rel:/Users/pauly/tk/convert3d/xc64rel:$PATH

MANIFEST=${1?}
PAT=$(cat $MANIFEST | awk '{printf "%s_%s\n",$2,$3}' | sort -u)

function slice_vars()
{
  SLIDEID=$(printf %04d $SLIDE)

  out=slides/${ID}_${BLOCK}_tau_${SLIDEID}_mrilike.nii.gz
  remote=chead:/data/picsl/pauly/tau_atlas/exp01/HNL_11_15/slides/${SVS}/${SVS}_mrilike.nii.gz
  fixed=slides/${ID}_${BLOCK}_tau_${SLIDEID}_mrilike_fix.nii.gz
  tearfix=slides/${ID}_${BLOCK}_tau_${SLIDEID}_mrilike_tearfix.nii.gz

  # The RGB thumbnail of histology - for pretty images
  thumb=../aperio/matching/tau/${SVS}.svs_thumbnail.tiff

  # Extract the MRI slice
  mri_slice=slides/${ID}_${BLOCK}_mri_${SLIDEID}.nii.gz

  # The MRI volume for this block
  mri_vol=../work/${ID}_${BLOCK}_mri_toblock_affine.nii.gz

  # High-resolution MRI slide and volume
  hires_slice=slides/${ID}_${BLOCK}_hires_${SLIDEID}.nii.gz
  hires_vol=../work/${ID}_${BLOCK}_hires_mri_toblock_warped.nii.gz

  hires_mask_slice=slides/${ID}_${BLOCK}_hires_mask_${SLIDEID}.nii.gz
  hires_mask_vol=../work/${ID}_${BLOCK}_hires_mri_mask_toblock_warped.nii.gz

  # Rigid transform between MRI (fixed) and histo (moving)
  mri_hist_rigid=slides/${ID}_${BLOCK}_mri_to_hist_rigid_${SLIDEID}.mat
  mri_hist_rigid_reslice=slides/${ID}_${BLOCK}_mri_to_hist_rigid_reslice_${SLIDEID}.nii.gz

  # Tear fixed with adjusted spacing to allow rigid registration
  tearfix_rescaled=slides/${ID}_${BLOCK}_tau_${SLIDEID}_mrilike_tearfix_rescaled.nii.gz
  thumb_rescaled=slides/${ID}_${BLOCK}_tau_${SLIDEID}_thumb_rescaled.nii.gz
  mri_hist_rigid_rescaled=slides/${ID}_${BLOCK}_mri_to_hist_rigid_rescaled_${SLIDEID}.mat
  mri_hist_rigid_rescaled_reslice=slides/${ID}_${BLOCK}_mri_to_hist_rigid_reslice_rescaled_${SLIDEID}.nii.gz

  mri_hist_rescaled_warp=slides/${ID}_${BLOCK}_mri_to_hist_warp_rescaled_${SLIDEID}.nii.gz
  mri_hist_rescaled_warp_reslice=slides/${ID}_${BLOCK}_mri_to_hist_warp_reslice_rescaled_${SLIDEID}.nii.gz
  mri_hist_rgb_rescaled_warp_reslice=slides/${ID}_${BLOCK}_mri_to_hist_rgb_warp_reslice_rescaled_${SLIDEID}.nii.gz

  # Tau stuff
  tau_density=$(ls milad/${SVS}_job_*_analysis_Area_SW20x20.nii.gz)
  tau_density_smooth=slides/${ID}_${BLOCK}_tau_density_smooth.nii.gz 
  tau_density_rescaled=slides/${ID}_${BLOCK}_tau_density_${SLIDEID}_thumb_rescaled.nii.gz
  mri_tau_density_rescaled_warp_reslice=slides/${ID}_${BLOCK}_mri_to_tau_density_warp_reslice_rescaled_${SLIDEID}.nii.gz

  # Do we need to flip
  FLIPCMD=$(echo $FLIP | sed -e "s/1/-flip x/" -e "s/0/-flip x/")

  # Final slice images mapped into space for visualization
  mri_viz=slides/${ID}_${BLOCK}_viz_mri_${SLIDEID}.nii.gz
  hires_viz=slides/${ID}_${BLOCK}_viz_hires_${SLIDEID}.nii.gz
  mri_hist_rescaled_warp_viz_reslice=slides/${ID}_${BLOCK}_viz_mri_to_hist_warp_reslice_rescaled_${SLIDEID}.nii.gz
  mri_hist_rgb_rescaled_warp_viz_reslice=slides/${ID}_${BLOCK}_viz_mri_to_hist_rgb_warp_reslice_rescaled_${SLIDEID}.nii.gz
  mri_tau_density_rescaled_warp_viz_reslice=slides/${ID}_${BLOCK}_viz_mri_to_tau_density_warp_reslice_rescaled_${SLIDEID}.nii.gz
}

<<'SKIP1'
mkdir -p slides

while read -r SVS ID BLOCK SLIDE STAIN FLIP; do

  # Read the vars
  slice_vars

  # Download the slide if it does not exist
  echo $SVS $SLIDEID
  if [[ ! -f $out ]]; then
    scp $remote $out
  fi

  # Make a negative and fix the spacing and also flip if necessary
  c2d $out -clip 0 1 -stretch 0 1 1 0 -spacing 0.05x0.05mm \
    $FLIPCMD -o $fixed

  # Fix tears by replacing them with median intensities
  c2d $fixed -as G -thresh 0.2 inf 1 0 -as M \
    -push G -median 11x11 -times \
    -push G -push M -replace 0 1 1 0 -times \
    -add -o $tearfix

  # Extract the MRI slice
  c3d $mri_vol -slice z $((SLIDE)) -o $mri_slice
  c2d $mri_slice -o $mri_slice


  # Extract the high-resolution MRI slice
  c3d $hires_vol -slice z $((SLIDE)) -o $hires_slice
  c2d $hires_slice -o $hires_slice
  c3d $hires_mask_vol -slice z $((SLIDE)) -o $hires_mask_slice
  c2d $hires_mask_slice -o $hires_mask_slice

<<'SKIP2'
  # Affine registration between MRI and remapped histology
  greedy -d 2 \
    -a -i $mri_slice $tearfix -m NCC 11x11 -o $mri_hist_rigid \
    -n 40x40x20 -ia-image-centers -search 10000 90 5

  # Reslice the histology to MRI
  greedy -d 2 \
    -rf $mri_slice -rm $tearfix $mri_hist_rigid_reslice \
    -r $mri_hist_rigid

done < $MANIFEST

SKIP1

# Figure out the common scaling factor
for fn in $(ls slides/${PAT}_mri_to_hist_rigid_*.mat); do 
  cat $fn | awk 'NR<=2 { print $1,$2,0,$3 } NR==3 { print 0,0,1,0 } END { print 0,0,0,1 }' > /tmp/temp.mat
  c3d_affine_tool /tmp/temp.mat -info-full | grep Affine
done \
  | sed -e "s/.*S = .//" -e "s/.; K =.*//" -e "s/,/ /g" \
  | awk '{printf "%f\n%f\n",$1,$2}' | sort -n > /tmp/scales.txt
MEDIAN_SCALE=$(cat /tmp/scales.txt | head -n $(echo $(( $(cat /tmp/scales.txt | wc -l) / 2))) \
  | tail -n 1 | awk '{print $1 / 100.}')

# Work out the viz matrix
viz_matrix=../viewmatrix.mat
viz_mat2d=slides/viewmatrix_2d.mat
cat $viz_matrix \
  | awk 'NR==1 {print $1,$2,$4} NR==2 {print $1,$2,$4} END {print 0,0,1}' \
  > $viz_mat2d

# Try to figure out the common scaling factor and apply it to the voxel
while read -r SVS ID BLOCK SLIDE STAIN FLIP; do

  # Slice variables
  slice_vars

<<'SKIP3'

  # Adjust the voxel size 
  new_spacing=$(c2d $tearfix -info-full | grep Spacing \
    | sed -e "s/.*:..//" -e "s/.$//" -e "s/,//g" \
    | awk -v k=1.09 '{printf "%fx%fmm\n", $1/k, $2/k}')

  c2d $tearfix -spacing $new_spacing -o $tearfix_rescaled

  # Rigid registration between MRI and remapped histology
  greedy -d 2 \
    -a -i $mri_slice $tearfix_rescaled -m NCC 11x11 -o $mri_hist_rigid_rescaled \
    -n 40x40x20 -dof 6 -ia-image-centers -search 10000 90 5

  # Reslice the histology to MRI
  greedy -d 2 \
    -rf $mri_slice -rm $tearfix_rescaled $mri_hist_rigid_rescaled_reslice \
    -r $mri_hist_rigid_rescaled

  # Registration to the low-resolution MRI, no mask
  # greedy -d 2 -sv \
  #   -i $mri_slice $tearfix_rescaled -m NCC 11x11 -o $mri_hist_rescaled_warp \
  #   -n 40x40x20 -it $mri_hist_rigid_rescaled \
  #   -s 10.0vox 1.0vox
  greedy -d 2 -sv \
    -i $hires_slice $tearfix_rescaled -m NCC 11x11 -o $mri_hist_rescaled_warp \
    -n 40x40x20 -it $mri_hist_rigid_rescaled \
    -gm $hires_mask_slice \
    -s 10.0vox 1.0vox

  greedy -d 2 \
    -rf $mri_slice -rm $tearfix_rescaled $mri_hist_rescaled_warp_reslice \
    -r $mri_hist_rescaled_warp $mri_hist_rigid_rescaled 


  # Apply the transformation to the thumb SVS image

  # The the dimensions of the processed counterstain image
  DIM=$(c2d $tearfix_rescaled -info-full | grep Dimensions \
    | sed -e "s/.*: .//" -e "s/.$//" -e "s/, /x/g")

  # Adjust the SVS thumbnail to have the same dimensions
  c2d $tearfix_rescaled -popas T -mcs $thumb \
    -foreach -flip x -resample $DIM -insert T 1 -copy-transform -endfor \
    -omc $thumb_rescaled

  greedy -d 2 \
    -rf $mri_slice -rm $thumb_rescaled $mri_hist_rgb_rescaled_warp_reslice \
    -r $mri_hist_rescaled_warp $mri_hist_rigid_rescaled 


  # Apply the transformation to the tau density maps

  # The the dimensions of the processed counterstain image
  DIM=$(c2d $tearfix_rescaled -info-full | grep Dimensions \
    | sed -e "s/.*: .//" -e "s/.$//" -e "s/, /x/g")

  # Adjust the SVS thumbnail to have the same dimensions
  c2d $tau_density -int 0 -resample 5x5% -smooth-fast 3vox -o $tau_density_smooth
  c3d $tearfix_rescaled \
    $tau_density_smooth -swapdim PLI \
    -flip x -resample ${DIM}x1 -copy-transform \
    -o $tau_density_rescaled

  c2d $tau_density_rescaled -o $tau_density_rescaled

  greedy -d 2 \
    -rf $mri_slice -rm $tau_density_rescaled $mri_tau_density_rescaled_warp_reslice \
    -r $mri_hist_rescaled_warp $mri_hist_rigid_rescaled 

SKIP3

  # Reconstruct slices into viz space (this is getting uggly)
  greedy -d 2 \
    -rf $mri_slice -rm $mri_slice $mri_viz -r $viz_mat2d

  exit


done < $MANIFEST


# Create 3D images
mkdir -p recon
for what in mri hires mri_to_hist_warp_reslice_rescaled mri_to_tau_density_warp_reslice_rescaled; do
  c3d slides/${PAT}_${what}_????.nii.gz -tile z -o recon/${PAT}_${what}.nii.gz
done

for what in mri_to_hist_rgb_warp_reslice_rescaled; do

  c3d -mcs slides/${PAT}_${what}_????.nii.gz \
    -foreach-comp 3 -tile z -endfor -omc recon/${PAT}_${what}.nii.gz

done


