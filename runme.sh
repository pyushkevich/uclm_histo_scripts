#!/bin/bash
set -x -e
PATH=/Users/pauly/tk/convert3d/xc64rel:/Users/pauly/tk/ants/xc64rel/bin:$PATH
PATH=/Users/pauly/tk/lddmm/xc64rel:$PATH
PATH=/Library/Frameworks/R.framework/Versions/3.3/Resources/bin/:$PATH
echo $PATH

# The ID
ID=${1?}

# Create a work directory
WORK=./work

# The slit mold
MOLD=mridata/slitmold.nii.gz
MRI=mridata/t2space_400_roi.nii.gz

# The contour image and its rotation
CONTOUR=mridata/countour_image.nii.gz
HOLDERMAT=mridata/holderrotation.mat

# The N4-corrected MRI and its mask
MRI_N4=$WORK/t2space_400_roi_n4corr.nii.gz
MRI_MASK_NATIVE=$WORK/t2space_400_roi_mask.nii.gz
MRI_MASK_MOLD=$WORK/tissue_mask.nii.gz

# High-resolution MRI
HIRES_MRI=${ID}_mri_hires.nii.gz
HIRES_MRI_AFFINE=mri_hires_to_lores_affine.mat

# The mask for the high-resolution MRI
HIRES_REGMASK=$WORK/${ID}_mri_hires_mask.nii.gz
HIRES_WARP=$WORK/${ID}_mri_warp_fx_hires_mv_lores.nii.gz
HIRES_ROOT_WARP=$WORK/${ID}_mri_rootwarp_fx_hires_mv_lores.nii.gz
HIRES_INV_WARP=$WORK/${ID}_mri_invwarp_fx_hires_mv_lores.nii.gz
RESLICE_MRI_TO_HIRES=$WORK/${ID}_mri_lores_reslice_to_hires.nii.gz

# Get the origin of the slit mold
MOLD_CENTER=$(c3d $MOLD -probe 50% | awk '{print $5,$6,$7}')

# Create work directory
mkdir -p $WORK

<<'SKIP1'

# Generate a mask from the holder rotation
c3d $MOLD $CONTOUR -shift -1 -reslice-matrix $HOLDERMAT -thresh -inf -1 1 0 -o $MRI_MASK_MOLD

# Generate a mask and perform N4
c3d $CONTOUR -thresh -inf 0 1 0 -type uchar -o $MRI_MASK_NATIVE
N4BiasFieldCorrection -d 3 -i $MRI -o $MRI_N4 -x $MRI_MASK_NATIVE



# Additional processing of the hi-resolution image

# Generate the high-resolution image mask
c3d $HIRES_MRI -cmv -thresh 5 inf 1 0 -o $HIRES_REGMASK

# Registration with high-resolution image as fixed, low-resolution as moving, lots of smoothness
greedy -d 3 -i $HIRES_MRI $MRI_N4 -it $HIRES_MRI_AFFINE,-1 \
  -o $HIRES_WARP -oroot $HIRES_ROOT_WARP -sv -s 3mm 0.2mm -m NCC 8x8x8 -n 40x40x0 -gm $HIRES_REGMASK \
  -wp 0.0001 -exp 6 \


# Apply the registration
greedy -d 3 -rf $HIRES_MRI -rm $MRI_N4 $RESLICE_MRI_TO_HIRES -r $HIRES_ROOT_WARP,64 $HIRES_MRI_AFFINE,-1 
greedy -d 3 -rf $HIRES_MRI -rc $HIRES_INV_WARP -wp 0.001 -r $HIRES_ROOT_WARP,-64

SKIP1


# Position each of the blockface slabs relative to the slit mold. This requires flipping
# in the z direction, and setting the origin of the center voxel
while read -r BLOCK_ID BLOCK_Z FLIPS ROT_INIT DX_INIT DY_INIT; do

  # Compute the proposed origin of the block
  BLOCK_FN=${ID}_${BLOCK_ID}_blockface.nii.gz
  BLOCK_FN_TOMOLD_INIT=$WORK/${ID}_${BLOCK_ID}_blockface_tomold_init.nii.gz
  BLOCK_FN_TOMOLD_INIT_INVGREEN=$WORK/${ID}_${BLOCK_ID}_blockface_tomold_init_invgreen.nii.gz
  BLOCK_ORIGIN=$(echo $MOLD_CENTER | awk -v z=$BLOCK_Z '{printf "%fx%fx%fmm",$1,$2,z}')
  FLIPCMD=$(echo $FLIPS | sed -e "s/\(.\)/-flip \1 /g")

  # MRI crudely mapped to block space
  MRI_TO_BLOCK_INIT=$WORK/${ID}_${BLOCK_ID}_mri_toblock_init.nii.gz
  MRI_TO_BLOCK_INIT_MASK=$WORK/${ID}_${BLOCK_ID}_mri_toblock_init_mask.nii.gz

  # Matrix to initialize rigid
  BLOCK_TO_MRI_RIGID_INIT=$WORK/${ID}_${BLOCK_ID}_rigid_init.mat
  BLOCK_TO_MRI_RIGID_INVGREEN=$WORK/${ID}_${BLOCK_ID}_rigid_invgreen.mat
  BLOCK_TO_MRI_AFFINE_INVGREEN=$WORK/${ID}_${BLOCK_ID}_affine_invgreen.mat

  # Affine resliced MRI matched to the blockface
  MRI_TO_BLOCK_AFFINE=$WORK/${ID}_${BLOCK_ID}_mri_toblock_affine.nii.gz
  MRI_TO_BLOCK_AFFINE_MASK=$WORK/${ID}_${BLOCK_ID}_mri_toblock_affine_mask.nii.gz

  # Hires MRI resampled to block
  HIRES_MRI_TO_BLOCK_AFFINE=$WORK/${ID}_${BLOCK_ID}_hires_mri_toblock_affine.nii.gz
  HIRES_MRI_TO_BLOCK_WARPED=$WORK/${ID}_${BLOCK_ID}_hires_mri_toblock_warped.nii.gz
  HIRES_MRI_MASK_TO_BLOCK_WARPED=$WORK/${ID}_${BLOCK_ID}_hires_mri_mask_toblock_warped.nii.gz

  # Intensity remapped histology block
  BLOCK_FN_TOMOLD_INIT_REMAPPED=$WORK/${ID}_${BLOCK_ID}_blockface_tomold_init_remapped.nii.gz

<<'SKIP2'

  # Flip and set the origin of the blockface image and also extract the negative of the 
  # green channel, which seems to have the best contrast
  /Users/pauly/tk/convert3d/xc64rel/c3d -verbose -mcs $BLOCK_FN \
    -foreach $FLIPCMD -origin-voxel-coord 50% $BLOCK_ORIGIN -endfor \
    -omc $BLOCK_FN_TOMOLD_INIT \
    -pop -stretch 0 255 255 0 -o $BLOCK_FN_TOMOLD_INIT_INVGREEN

  # Reslice the MRI into the space of the histology block and make it RGB
  c3d -verbose $BLOCK_FN_TOMOLD_INIT $MRI_N4 -reslice-matrix $HOLDERMAT -o $MRI_TO_BLOCK_INIT
  c3d -verbose $BLOCK_FN_TOMOLD_INIT $MRI_MASK_MOLD -reslice-identity -o $MRI_TO_BLOCK_INIT_MASK

  # Generate initial rotation matrix
  ROT_CTR=$(echo $BLOCK_ORIGIN | sed -e "s/x/ /g")
  c3d_affine_tool -tran $ROT_CTR -rot $ROT_INIT 0 0 1 -tran $ROT_CTR -inv -mult -mult \
    -o $BLOCK_TO_MRI_RIGID_INIT

  # Perform the rigid, then affine registration
  greedy -d 3 -a -dof 6 -i $MRI_TO_BLOCK_INIT $BLOCK_FN_TOMOLD_INIT_INVGREEN \
    -gm $MRI_TO_BLOCK_INIT_MASK -o $BLOCK_TO_MRI_RIGID_INVGREEN \
    -m NCC 4x4x4 -n 60x40x0 -ia $BLOCK_TO_MRI_RIGID_INIT

  greedy -d 3 -a -dof 12 -i $MRI_TO_BLOCK_INIT $BLOCK_FN_TOMOLD_INIT_INVGREEN \
    -gm $MRI_TO_BLOCK_INIT_MASK -o $BLOCK_TO_MRI_AFFINE_INVGREEN \
    -m NCC 4x4x4 -n 60x40x0 -ia $BLOCK_TO_MRI_RIGID_INVGREEN

  # Reslice the MRI into block space using the affine registration result
  greedy -d 3 -rf $MRI_TO_BLOCK_INIT_MASK -rm $MRI_N4 $MRI_TO_BLOCK_AFFINE \
    -ri LABEL 0.2vox -rm $MRI_MASK_NATIVE $MRI_TO_BLOCK_AFFINE_MASK \
    -r $BLOCK_TO_MRI_AFFINE_INVGREEN,-1 $HOLDERMAT
  
  # Reslice the high-resolution MRI as well. Also reslice the high-resolution MRI mask, 
  # so we can perform registration to histology later
  greedy -d 3 -rf $MRI_TO_BLOCK_INIT_MASK -rm $HIRES_MRI $HIRES_MRI_TO_BLOCK_AFFINE \
    -r $BLOCK_TO_MRI_AFFINE_INVGREEN,-1 $HOLDERMAT $HIRES_MRI_AFFINE

SKIP2
  greedy -d 3 -rf $MRI_TO_BLOCK_INIT_MASK -rm $HIRES_MRI $HIRES_MRI_TO_BLOCK_WARPED \
    -ri NN -rm $HIRES_REGMASK $HIRES_MRI_MASK_TO_BLOCK_WARPED \
    -r $BLOCK_TO_MRI_AFFINE_INVGREEN,-1 $HOLDERMAT $HIRES_MRI_AFFINE $HIRES_INV_WARP 



done < manifest.txt


