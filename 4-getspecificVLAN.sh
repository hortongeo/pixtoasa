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

echo "Getting associated objects"
PROGRESS=0
progress_bar
OBJECTS=""
for IP in `echo $IPS`
do
	OBJLINEFULL=`grep $IP ASA/object -n`
	if [ $? -eq 0 ]
	then
		OBJLINE=`echo $OBJLINEFULL | cut -d ":" -f 1`
		OBJLINE=$(($OBJLINE-1))q
		OBJ=`sed "$OBJLINE;d" ASA/object | cut -d " " -f 3`
		OBJECTS="$OBJECTS $OBJ"
	fi
	progress_bar
done
PROGRESS=99
progress_bar

echo "Getting associated object-groups"
PROGRESS=0
progress_bar
OBJECTGROUPS=""
SEDCHAR="q"
for IP in `echo $IPS`
do
	IPLINE=`grep -n $IP ASA/object-group | cut -d ":" -f 1`
	for LINENUM in $IPLINE
	do
		FOUND=0
		while [ $FOUND -eq 0 ]
		do
			LINENUM=$(($LINENUM-1))
			OBJECTGROUP=`sed "$LINENUM$SEDCHAR;d" ASA/object-group | egrep "^object-group"`
			if [ $? -eq 0 ]
			then
				OBJECTGROUP=`echo $OBJECTGROUP | cut -d " " -f 3`
				OBJECTGROUPS="$OBJECTGROUPS $OBJECTGROUP"
				FOUND=1
			fi
			progress_bar
		done
	done
done
PROGRESS=99
progress_bar

for OBJ in `echo $OBJECTS`
do
        IPLINE=`grep -n $OBJ ASA/object-group | cut -d ":" -f 1`
        for LINENUM in $IPLINE
        do
                FOUND=0
                while [ $FOUND -eq 0 ]
                do
                        LINENUM=$(($LINENUM-1))
                        OBJECTGROUP=`sed "$LINENUM$SEDCHAR;d" ASA/object-group | egrep "^object-group"`
                        if [ $? -eq 0 ]
                        then
                                OBJECTGROUP=`echo $OBJECTGROUP | cut -d " " -f 3`
                                OBJECTGROUPS="$OBJECTGROUPS $OBJECTGROUP"
                                FOUND=1
                        fi
                        progress_bar
                done
        done
done
PROGRESS=99
progress_bar

# Get the outside ACL sorted
echo "creating outside ACL"
rm -rf ASA/ACLS/per-int
mkdir -p ASA/ACLS/per-int

PROGRESS=0
progress_bar
NEEDLES="$IPS $OBJECTS $OBJECTGROUPS"
NEEDLES=`echo $NEEDLES | sed 's/ /\n/g' | sort | uniq`
while read ACLLINE
do
	echo "looking at $ACLLINE"
	for NEEDLE in $NEEDLES
	do
		MATCH=`echo $ACLLINE | grep $NEEDLE`
		if [ $? -eq 0 ]
		then
			echo -e "\t$MATCH"
			echo $MATCH >> ASA/ACLS/per-int/outside
		fi
		progress_bar
	done
done < ASA/ACLS/$OUTACL
PROGRESS=99
progress_bar

# inside ACL
cp ASA/ACL/$INACL ASA/ACL/per-int/
