#!/bin/sh

op=~/public_html/mirror/opensuse/
export BETA=1
(cd $op ; make ) # update
#ssh vm12a "sshfs delta4: ~/temp/delta/" 


#for iso in `(cd $op ; scripts/latestiso i586 NET )` ; do
for iso in `(cd $op ; scripts/latestiso i686 GNOME-LiveCD )` ; do
#for iso in `(cd $op ; scripts/latestiso i686 KDE-LiveCD )` ; do
#for iso in `(cd $op ; scripts/latestiso x86_64 KDE-LiveCD )` ; do
#for iso in `(cd $op ; scripts/latestiso x86_64 NET )` ; do
export SUSEISO=$op$iso

export SCREENSHOTINTERVAL=0.5

echo testing $SUSEISO
# cleanup
rm -rf qemuscreenshot/*.ppm
#alarm 300
./start.pl

name=$(perl -e '$_=shift;s{.*iso/}{};s/-Media.iso//;print' $SUSEISO)
echo tools/ppmtompg qemuscreenshot video/$name
tools/ppmtompg qemuscreenshot video/$name
cp -al video/* ~/public_html/mirror/opensuse/video/

done

#ssh vm12a "fusermount -u ~/temp/delta"

