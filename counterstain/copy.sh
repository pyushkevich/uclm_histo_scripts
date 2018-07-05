#!/bin/bash

# Point to the latest Greedy and c3d 
export PATH=/Users/pauly/tk/lddmm/xc64rel:/Users/pauly/tk/convert3d/xc64rel:$PATH

MANIFEST=HNL_11_15_HR3p_tau.txt

mkdir -p slides

while read -r SVS ID BLOCK SLIDE STAIN FLIP; do

  out=slides/${ID}_${BLOCK}_tau_${SLIDE}_mrilike.nii.gz
  remote=chead:/data/picsl/pauly/tau_atlas/exp01/HNL_11_15/slides/${SVS}/${SVS}_mrilike.nii.gz
  fixed=slides/${ID}_${BLOCK}_tau_${SLIDE}_mrilike_fix.nii.gz
  tearfix=slides/${ID}_${BLOCK}_tau_${SLIDE}_mrilike_tearfix.nii.gz

  # Extract the MRI slice
  mri_slice=slides/${ID}_${BLOCK}_mri_${SLIDE}.nii.gz

  # The MRI volume for this block
  mri_vol=../work/${ID}_${BLOCK}_mri_toblock_affine.nii.gz

  # Rigid transform between MRI (fixed) and histo (moving)
  mri_hist_rigid=slides/${ID}_${BLOCK}_mri_to_hist_rigid_${SLIDE}.mat
  mri_hist_rigid_reslice=slides/${ID}_${BLOCK}_mri_to_hist_rigid_reslice_${SLIDE}.nii.gz

  # Download the slide if it does not exist
  echo $SVS $SLIDE
  if [[ ! -f $out ]]; then
    scp $remote $out
  fi

<<'SKIPME'  

  # Do we need to flip
  FLIPCMD=$(echo $FLIP | sed -e "s/1/-flip x/" -e "s/0//")

  # Make a negative and fix the spacing and also flip if necessary
  c2d $out -clip 0 1 -stretch 0 1 1 0 -spacing 0.05x0.05mm \
    $FLIPCMD -o $fixed

  # Fix tears by replacing them with median intensities
  c2d $fixed -as G -thresh 0.2 inf 1 0 -as M \
    -push G -median 11x11 -times \
    -push G -push M -replace 0 1 1 0 -times \
    -add -o $tearfix


  # Extract the MRI slice
  c3d $mri_vol -slice z $((SLIDE-1)) -o $mri_slice
  c2d $mri_slice -o $mri_slice

SKIPME

  # Affine registration between MRI and remapped histology
  greedy -d 2 \
    -a -i $mri_slice $tearfix -m NCC 11x11 -o $mri_hist_rigid \
    -n 40x40x20 -ia-image-centers -search 10000 90 5

  # Reslice the histology to MRI
  greedy -d 2 \
    -rf $mri_slice -rm $tearfix $mri_hist_rigid_reslice \
    -r $mri_hist_rigid

done < $MANIFEST

