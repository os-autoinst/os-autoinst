#! /bin/bash

# TODO: Fix paths

# Get the max size of the PNG set
WIDTH=0
HEIGHT=0
for i in qemuscreenshot/*.png; do
    size=`identify $i | cut -d' ' -f3`
    width=`echo $size | cut -d'x' -f1`
    height=`echo $size | cut -d'x' -f2`
    if [ "$width" -gt "$WIDTH" ]; then
	WIDTH=$width
    fi
    if [ "$height" -gt "$HEIGHT" ]; then
	HEIGHT=$height
    fi
done

# Resize and rename the PNG 
C=0
mkdir movie
for i in qemuscreenshot/*.png; do
    convert $i -gravity center -background black -extent ${WIDTH}x${HEIGHT} movie/file-`printf %010d $C`.png
    C=$((C+1))
done

# Create the movie
./png2theora movie/file-%010d.png -o video.ogv
