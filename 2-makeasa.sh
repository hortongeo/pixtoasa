#!/bin/bash
#
# Takes the files in the filer PIX and makes an ASA configuration
#
# George Horton - 5/14

# Global
if [ "$1" == "" ]
then
	echo "usage: 2-makeasa.sh <ASAVER>"
	exit 1
fi

ASAVER=$1

# names to objects
while read LINE
do
	IP=`echo $LINE | cut -d " " -f 2`
	NAME=`echo $LINE | cut -d " " -f 3`
	DESC=`echo $LINE | cut -d " " -f 5-`

	# find where the name is used
	# 1 - check object-groups
	
done < PIX/name
