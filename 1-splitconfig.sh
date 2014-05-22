#!/bin/bash
#
# Take a PIX 8.0 configuration file and split it into component parts
#
# George Horton - 05/2014
#

# Global
CONFIG=$1
if [ ! -e "$CONFIG" ]
then
	echo "Usage: 1-splitconfig.sh <PIX_CONFIG_FILE>"
	exit 1;
fi

#clean up first
rm -rf PIX
mkdir PIX

# Name
egrep '^name ' $CONFIG > PIX/name

# Objects
egrep "^object " $CONFIG > PIX/object

# object-group
rm -f PIX/object-group
START=`egrep "^object-group " $CONFIG -n | head -1 | cut -d ":" -f 1`
CONTUNIE=1

while [ $CONTUNIE -eq 1 ]
do
	LINE=`sed -n "$START"p $CONFIG`

	TMP=`echo "$LINE" | egrep "^ "`
	if [ $? -eq 0 ]
	then
		echo "$LINE" >> PIX/object-group
		let START=$START+1
	else
		TMP=`echo "$LINE" | egrep "^object-group "`
		if [ $? -eq 0 ]
		then
			echo "$LINE" >> PIX/object-group
			let START=$START+1
		else
			CONTUNIE=0
		fi
	fi
done

# ACL
mkdir PIX/ACLS
ACLS=`egrep "^access-group " $CONFIG | cut -d " " -f 2 | sort | uniq`
for ACL in $ACLS
do
	egrep "^access-list $ACL " $CONFIG > PIX/ACLS/$ACL
done
egrep "^access-group " $CONFIG > PIX/access-group

# Routes
egrep '^route ' $CONFIG > PIX/route
