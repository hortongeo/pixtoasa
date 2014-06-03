#!/bin/bash
#
# Take a PIX 8.0 configuration file and split it into component parts
#
# George Horton - 05/2014
#

# Functions
function progress_bar {
        case $PROGRESS in
        0)
                echo -en "\e[0K\r-"
                ;;
        10)
                echo -en "\e[0K\r\\"
                ;;
        20)
                echo -en "\e[0K\r|"
                ;;
        30)
                echo -en "\e[0K\r/"
                ;;
        99)
                echo -en "\e[0K\r "
                echo -en "\e[0K\r"
                ;;
        esac
        let PROGRESS=$PROGRESS+1

        if [ $PROGRESS -gt 39 ]
        then
                PROGRESS=0
        fi
}

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
echo "Extracting the names"
egrep '^name ' $CONFIG > PIX/name

# Objects
echo "Extracting the objects"
egrep "^object " $CONFIG > PIX/object

# object-group
echo "Extracting the object-groups"
rm -f PIX/object-group
START=`egrep "^object-group " $CONFIG -n | head -1 | cut -d ":" -f 1`
CONTUNIE=1

PROGRESS=0
progress_bar
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
	progress_bar
done
PROGRESS=99
progress_bar

# ACL
echo "Extracting the ACLS"
mkdir PIX/ACLS
ACLS=`egrep "^access-group " $CONFIG | cut -d " " -f 2 | sort | uniq`

PROGRESS=0
progress_bar
for ACL in $ACLS
do
	egrep "^access-list $ACL " $CONFIG > PIX/ACLS/$ACL
	progress_bar
done
egrep "^access-group " $CONFIG > PIX/access-group
PROGRESS=99
progress_bar


# Routes
echo "Extracting the routes"
egrep '^route ' $CONFIG > PIX/route


# NAT
echo "Extracting the NAT statements"
rm -rf PIX/NAT
mkdir PIX/NAT
mkdir PIX/NAT/ACLS

egrep '^global ' $CONFIG > PIX/NAT/global
egrep '^nat ' $CONFIG > PIX/NAT/nat
egrep '^static ' $CONFIG > PIX/NAT/static

PROGRESS=0
progress_bar
for NAT in `grep "access-list" PIX/NAT/nat | cut -d " " -f 5`
do
	egrep "^access-list $NAT" $CONFIG > PIX/NAT/ACLS/$NAT
	progress_bar
done
PROGRESS=99
progress_bar

PROGRESS=0
progress_bar
for NAT in `grep "access-list" PIX/NAT/static | cut -d " " -f 6`
do
        egrep "^access-list $NAT" $CONFIG > PIX/NAT/ACLS/$NAT
        progress_bar
done
PROGRESS=99
progress_bar

echo "Done!"
