#!/bin/sh

# Generate the rod textures from the template below.
# Requires sxpm from the xpmtools to convert from XPM2 to XPM3 format
# and ImageMagick's convert to convert from XPM2 to PNG format

while read mat colors ; do
	[ $mat = -- ] && basename="dowsing_rod" || basename="dowsing_${mat}_rod"

	set -- $colors

	ncolors=$((5+$#))

	if [ $# = 0 ] ; then
		c1=s
		c2=s
		c3=s
		colorlines=
	elif [ $# = 1 ] ; then
		c1=A
		c2=A
		c3=A
		colorlines="
A c $1"
	elif [ $# = 3 ] ; then
		c1=r
		c2=g
		c3=b
		colorlines="
r c $1
g c $2
b c $3"
	else
		echo "unsupported number of colors $#" >&2
		exit 1
	fi

	echo "$basename"
	sxpm -nod - -o - <<XPM | convert - ${basename}.png
! XPM2
16 16 $ncolors 1
s c #3A2410
u c #432D14
X c #51391C
o c #6C4913
. c none${colorlines}
................
................
............Xs..
...........X${c1}s..
..........X${c2}u...
.........X${c3}u....
........Xos.....
.......Xos......
..XXXXXos.......
..ooooos........
......os........
......os........
......os........
......os........
................
................
XPM
done <<MAP
--
abstract #FF0000 #00FF00 #0000FF
copper #F6A75F
tin #C1C1C1
bronze #FB974D
steel #FFFFFF
gold #FFFF76
mese #A6A600
MAP
