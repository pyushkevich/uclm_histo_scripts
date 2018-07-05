#!/usr/bin/env python
from __future__ import print_function
import openslide
import numpy as np
import os, time, math, sys
import getopt
import SimpleITK as sitk

# Little function to round numbers up to closest divisor of d
def round_up(x, d):
    return int(math.ceil(x * 1.0 / d) * d)

# This little function computes the means of image tiles. No smoothing is performed
def tile_means(img, tile_size):
    b=np.mean(img.reshape(img.shape[0],-1,tile_size),axis=2)
    c=np.mean(b.reshape(-1,tile_size,b.shape[1]),axis=1)
    return c

# Main function
def process_svs(p):

    # Read slide
    slide=openslide.OpenSlide(p['in_img'])
    print ("Levels: %d" % slide.level_count)

    # If we just want summaries, do that
    if len(p['summary']):
        img = slide.get_thumbnail((1000,1000))
        img.save(p['summary'] + '_thumbnail.tiff')

        # Get the label
        img = slide.associated_images['label']
        img.save(p['summary'] + '_label.tiff')

    if len(p['out_img']):

        # Round up the dimensions to fit an even number of blocks
        tile_size = p['tile_size']
        wx = round_up(slide.dimensions[0], tile_size)
        wy = round_up(slide.dimensions[1], tile_size)

        # Allocate output image
        (ox,oy)=(wx/tile_size, wy/tile_size)
        oimg=np.zeros([oy,ox])

        # Set the chunk size in pixels and the chunk arrays
        chunk_tiles=40
        chunk_size=tile_size * chunk_tiles
        px = np.arange(0,round_up(slide.dimensions[0],chunk_size), chunk_size)
        py = np.arange(0,round_up(slide.dimensions[1],chunk_size), chunk_size)

        # Stain matrix stuff
        stain_mat = np.array([
            [ 0.6443186, 0.7166757, 0.26688856],
            [0.09283128, 0.9545457, 0.28324] ,
            [0.63595444, 0.001, 0.7717266]])
        stain_mat_inv = np.linalg.inv(stain_mat)

        # Loop over the chunks
        for ix in px:
            for iy in py:

                # Read the region and convert to NUMPY
                reg=np.array(slide.read_region((ix,iy), 0, (chunk_size,chunk_size)))[:,:,0:3]
                
                # Color deconvolution
                reg_hemo=1 - np.dot(-np.log((reg+1.) / 256.0), stain_mat_inv[1,])
                
                # ITK math morphology
                reg_mm=sitk.GetArrayFromImage(
                    sitk.GrayscaleDilate(
                        sitk.GetImageFromArray(reg_hemo, False), 6));
                
                # Reduce to a small image
                a=tile_means(reg_mm,tile_size)
                
                # Fill the corresponding region of the output image
                (qx,qy) = (ix/tile_size,iy/tile_size)
                (zx,zy) = (min(ox-qx,chunk_tiles), min(oy-qy,chunk_tiles))    
                oimg[qy:qy+zy,qx:qx+zx]=a[0:zy,0:zx]

                # Print progress
                sys.stdout.write('\rChunk (%03d,%03d)' % (ix,iy))
                sys.stdout.flush()
                


        # Write the result as a NIFTI file
        res = sitk.GetImageFromArray(oimg, False)
        res.SetSpacing((float(slide.properties['openslide.mpp-x']) * tile_size,
                       float(slide.properties['openslide.mpp-y']) * tile_size))
        sitk.WriteImage(res, p['out_img'])

# Usage
def usage(exit_code):
    print('process_raw_slide -i <input_svs> -o <output> [-t tile_size]')
    sys.exit(exit_code)
    
# Main
def main(argv):
    # Initial parameters
    p = {'in_img' : '', 
         'out_img' : '', 
         'summary' : '',
         'tile_size' : 100}

    # Read options
    try:
        opts, args = getopt.getopt(argv, "hi:o:t:s:")
    except getopt.GetoptError:
        usage(2)

    for opt,arg in opts:
        if opt == '-h':
            usage(0)
        elif opt == '-i':
            p['in_img'] = arg
        elif opt == '-o':
            p['out_img'] = arg
        elif opt == '-s':
            p['summary'] = arg
        elif opt == '-t':
            p['tile_size'] = int(arg)

    # Run the main code
    process_svs(p)

if __name__ == "__main__":
    main(sys.argv[1:])
