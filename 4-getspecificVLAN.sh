#!/bin/bash
#
# Takes a specific Internal VLAN and provides the outside ACL, inside ACL and required objects and object-groups.
#
# GH 5/2014

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

if [ "$1" == "" ] || [ "$2" == "" ] || [ "$3" == "" ]
then
	echo "Usage: 3-getspecificVLAN.sh <PIX_CONFIG_FILE> <Inside Interface> <Outside Interface>"
	exit 1
fi

CONFIG=$1
ININTERFACE=$2
OUTINTERFACE=$3

# get the interface details
INIFLINENOFULL=`grep $ININTERFACE $CONFIG -n`
if [ $? -eq 1 ]
then
	echo "Unable to find inside interface in configuration, did you spell it right?"
	exit 1
else
	INIFLINENO=`echo $INIFLINENOFULL | cut -d ":" -f 1`
fi

OUTIFLINENOFULL=`grep $OUTINTERFACE $CONFIG -n`
if [ $? -eq 1 ]
then
        echo "Unable to find outside interface in configuration, did you spell it right?"
        exit 1
else
	OUTIFLINENO=`echo $OUTIFLINENOFULL | cut -d ":" -f 1`
fi

IP=`sed -n "$INIFLINENO,$ p" $CONFIG | grep -o -P "ip address [0-9\.]+" | head -1 | cut -d " " -f 3`
SUBNET=`sed -n "$INIFLINENO,$ p" $CONFIG | grep -o -P "ip address [0-9\.]+ [0-9\.]+" | head -1 | cut -d " " -f 4`
INNAMEIF=`sed -n "$INIFLINENO,$ p" $CONFIG | grep -o -P "nameif [0-9a-zA-Z\-\_\.]+" | head -1 | cut -d " " -f 2`
OUTNAMEIF=`sed -n "$OUTIFLINENO,$ p" $CONFIG | grep -o -P "nameif [0-9a-zA-Z\-\_\.]+" | head -1 | cut -d " " -f 2`
NETWORK=`ipcalc -n $IP $SUBNET | cut -d "=" -f 2`
BROADCAST=`ipcalc -b $IP $SUBNET | cut -d "=" -f 2`
INACL=`grep "access-group .* in interface $INNAMEIF" $CONFIG | cut -d " " -f 2`
OUTACL=`grep "access-group .* in interface $OUTNAMEIF" $CONFIG | cut -d " " -f 2`

NOCT1=`echo $NETWORK | cut -d "." -f 1`
NOCT2=`echo $NETWORK | cut -d "." -f 2`
NOCT3=`echo $NETWORK | cut -d "." -f 3`
NOCT4=`echo $NETWORK | cut -d "." -f 4`

BOCT1=`echo $BROADCAST | cut -d "." -f 1`
BOCT2=`echo $BROADCAST | cut -d "." -f 2`
BOCT3=`echo $BROADCAST | cut -d "." -f 3`
BOCT4=`echo $BROADCAST | cut -d "." -f 4`

echo "Getting list of IPs"
IPS=""
PROGRESS=0
progress_bar
for OCT1 in $(seq $NOCT1 $BOCT1)
do
	for OCT2 in $(seq $NOCT2 $BOCT2)
	do
		for OCT3 in $(seq $NOCT3 $BOCT3)
		do
			for OCT4 in $(seq $NOCT4 $BOCT4)
			do
				IP="$OCT1.$OCT2.$OCT3.$OCT4"
				IPS="$IPS $IP"
				progress_bar
			done
		done
	done
done
PROGRESS=99
progress_bar


