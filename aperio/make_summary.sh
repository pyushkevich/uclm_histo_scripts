#!/bin/bash
mkdir -p summary
for fn in $(ls /Volumes/Histology/UCLM2018/PC18-407/*.svs); do

  if [[ ! -f summary/$(basename $fn)_thumbnail.tiff ]]; then

    echo $fn summary/$(basename $fn)

    ./process_raw_slide.py -i $fn -s summary/$(basename $fn)

  fi



done


