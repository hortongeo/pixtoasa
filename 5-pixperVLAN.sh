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

function getips {
	local OBJGRP="$1"
	PROGRESS=0
	progress_bar

	# get the obejct groups
	OBJGRPLINENO=`grep -n "^object-group .* $OBJGRP$" PIX/object-group`
	if [ $? -ne 0 ]
	then
		OBJGRPLINENO=`grep -n "^object-group .* $OBJGRP " PIX/object-group`
	fi
	OBJGRPLINENO=`echo $OBJGRPLINENO | cut -d ":" -f 1`
	OBJGRPLINENO=$(($OBJGRPLINENO+1))
	ENDLINENO=`sed -n "$OBJGRPLINENO,$ p" PIX/object-group | egrep -n "^object-group" | head -1 | cut -d ":" -f 1`
	OBJGRPLINENO=$(($OBJGRPLINENO-1))
	ENDLINENO=$(($ENDLINENO+$OBJGRPLINENO-1))
	if [ $ENDLINENO -le $OBJGRPLINENO  ]
	then
		ENDLINENO="$"
	fi
if [ $OBJGRPLINENO -eq 0 ]
then
	echo "$OBJGRP"
fi
	local OBJGRPDATA=`sed -n "$OBJGRPLINENO,$ENDLINENO p" PIX/object-group`

	while read LINE
	do
		TEST=`echo $LINE | egrep "^object-group"`
		if [ $? -ne 0 ]
		then
			TEST=`echo $LINE | cut -d " " -f 1`
			if [ "$TEST" == "network-object" ]
			then
				IP=`echo $LINE | cut -d " " -f 2`
				if [ "$IP" == "host" ]
				then
					IP=`echo $LINE | cut -d " " -f 3`
				fi
				IPS="$IP $IPS"
			elif [ "$TEST" == "group-object" ]
			then
				GRPOBJ=`echo $LINE | cut -d " " -f 2`
				getips "$GRPOBJ"
			fi
		fi
		progress_bar
	done <<<"$OBJGRPDATA"
	DUPCHK=`grep -c "^object-group .* $OBJGRP" PIX/per-int/object-group`
	if [ $DUPCHK -eq 0 ]
	then
		echo "$OBJGRPDATA" >> PIX/per-int/object-group
	fi
	PROGRESS=99
	progress_bar
}

if [ "$1" == "" ] || [ "$2" == "" ] || [ "$3" == "" ] || [ "$4" == "" ] || [ "$5" == "" ]
then
        echo "Usage: 3-getspecificVLAN.sh <PIX_CONFIG_FILE> <Inside Interface> <Outside Interface> <New Outside ACL name> <outside ACL start number>"
        exit 1
fi

CONFIG=$1
ININTERFACE=$2
OUTINTERFACE=$3
ACLNAME=$4
ACLSTART=$5

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

rm -rf PIX/per-int
mkdir -p PIX/per-int
touch PIX/per-int/object-group

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

echo "Getting names and objects from inside ACL"
PROGRESS=0
progress_bar

OBJECTGRPS=""
IPS=""

while read ACLLINE
do
	TST=`echo $ACLLINE | grep -c "access-list $INACL remark"`
	if [ $TST -gt 0 ] 
	then
		continue
	fi
	CNT=0
	PROTO=""
	SRC=""
	DST=""
	PORT=""
	LASTITEM=""
	for ITEM in $ACLLINE
	do
		if [ $CNT -ge 4 ]
		then
			if [ "$PROTO" == "" ]
			then
				if [ "$ITEM" == "object-group" ]
				then
					LASTITEM="$ITEM"
				else
					if [ "$LASTITEM" = "" ]
					then
						PROTO="$ITEM"
					else
						PROTO="$LASTITEM $ITEM"
						LASTITEM=""
					fi
				fi	
			elif [ "$SRC" == "" ] && [ "$ITEM" == "any" ]
			then
				SRC="$ITEM"
			elif [ "$SRC" == "" ] && [ "$LASTITEM" == "" ]
			then
				LASTITEM="$ITEM"
			elif [ "$SRC" = "" ]
			then
				SRC="$LASTITEM $ITEM"
				LASTITEM=""
			elif [ "$DST" == "" ] && [ "$ITEM" == "any" ]
                        then
                                DST="$ITEM"
			elif [ "$DST" == "" ] && [ "$LASTITEM" == "" ]
			then
				LASTITEM="$ITEM"
			elif [ "$DST" == "" ]
			then
				DST="$LASTITEM $ITEM"
                                LASTITEM=""
			elif [ "$PORT" == "" ] && [ "$LASTITEM" == "" ]
			then
				LASTITEM="$ITEM"
			elif [ "$PORT" == "" ]
			then
				PORT="$LASTITEM $ITEM"
                                LASTITEM=""
			fi	
		fi
		CNT=$(($CNT+1))
		progress_bar
	done

	TST=`echo $SRC | cut -d " " -f 1`
	if [ "$TST" == "object-group" ]
	then
		OBJGRP=`echo $SRC | cut -d " " -f 2`
		OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
	elif [ "$TST" == "host" ]
	then
		NAME=`echo $SRC | cut -d " " -f 2`
		IPS="$IPS $NAME"
	elif [ "$TST" != "any" ]
	then
		IPS="$IPS $TST"
	fi

        TST=`echo $DST | cut -d " " -f 1`
        if [ "$TST" == "object-group" ]
        then
                OBJGRP=`echo $DST | cut -d " " -f 2`
                OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
        elif [ "$TST" == "host" ]
	then
                NAME=`echo $DST | cut -d " " -f 2`
                IPS="$IPS $NAME"
        elif [ "$TST" != "any" ]
	then
                IPS="$IPS $TST"
        fi

        TST=`echo $PORT | cut -d " " -f 1`
        if [ "$TST" == "object-group" ]
        then
                OBJGRP=`echo $PORT | cut -d " " -f 2`
                OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
        elif [ "$TST" == "host" ]
	then
                NAME=`echo $PORT | cut -d " " -f 2`
                IPS="$IPS $NAME"
        elif [ "$TST" != "log" ] && [ "$TST" != "eq" ]
	then
                IPS="$IPS $TST"
        fi

done < PIX/ACLS/$INACL
PROGRESS=99
progress_bar

echo "Extract IPS from object groups"
for OBJGRP in $OBJECTGROUPS
do
	getips "$OBJGRP"
done

echo "IPs to names"
PROGRESS=0
progress_bar

for IP in $IPS
do
	grep " $IP " PIX/name >> .tmp-name
	progress_bar
done
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
                                grep " $IP " PIX/name >> .tmp-name
				IPS="$IPS $IP"
                                progress_bar
                        done
                done
        done
done
PROGRESS=99
progress_bar
cat .tmp-name | sort | uniq > PIX/per-int/name
PROGRESS=99
progress_bar

cp PIX/ACLS/$INACL PIX/per-int/$INACL

# and the outside ACL
echo "Extracting outside ACL"
OBJGRPS=""
for IP in $IPS
do
	IPLINES=`grep -n " $IP " PIX/object-group`
	while read LNO
	do
		NUM=`echo $LNO | cut -d ":" -f 1`
		if [ "$NUM" != "" ]
		then
			OBJ=`head -$NUM PIX/object-group | grep "^object-group" | tail -1 | cut -d " " -f 3`
			OBJGRPS="$OBJGRPS $OBJ"
		fi
	done <<<"$IPLINES"
done
echo "$IPS" > .tmp-ipsnobjectgroups
echo "$OBJGRPS" >> .tmp-ipsnobjectgroups
sed -i "s/ /\n/g" .tmp-ipsnobjectgroups
sed -i '/^\s*$/d' .tmp-ipsnobjectgroups
grep -f .tmp-ipsnobjectgroups PIX/ACLS/$OUTACL > PIX/per-int/outside

OBJECTGROUPS=""
IPS=""

while read ACLLINE
do
        TST=`echo $ACLLINE | grep -c "access-list $INACL remark"`
        if [ $TST -gt 0 ]
        then
                continue
        fi
        CNT=0
        PROTO=""
        SRC=""
        DST=""
        PORT=""
        LASTITEM=""
        for ITEM in $ACLLINE
        do
                if [ $CNT -ge 4 ]
                then
                        if [ "$PROTO" == "" ]
                        then
                                if [ "$ITEM" == "object-group" ]
                                then
                                        LASTITEM="$ITEM"
                                else
                                        if [ "$LASTITEM" = "" ]
                                        then
                                                PROTO="$ITEM"
                                        else
                                                PROTO="$LASTITEM $ITEM"
						LASTITEM=""
                                        fi
                                fi
                        elif [ "$SRC" == "" ] && [ "$ITEM" == "any" ]
                        then
                                SRC="$ITEM"
                        elif [ "$SRC" == "" ] && [ "$LASTITEM" == "" ]
                        then
                                LASTITEM="$ITEM"
                        elif [ "$SRC" = "" ]
                        then
                                SRC="$LASTITEM $ITEM"
                                LASTITEM=""
                        elif [ "$DST" == "" ] && [ "$ITEM" == "any" ]
                        then
                                DST="$ITEM"
                        elif [ "$DST" == "" ] && [ "$LASTITEM" == "" ]
                        then
                                LASTITEM="$ITEM"
                        elif [ "$DST" == "" ]
                        then
                                DST="$LASTITEM $ITEM"
                                LASTITEM=""
                        elif [ "$PORT" == "" ] && [ "$LASTITEM" == "" ]
                        then
                                LASTITEM="$ITEM"
                        elif [ "$PORT" == "" ]
                        then
                                PORT="$LASTITEM $ITEM"
                                LASTITEM=""
                        fi
                fi
                CNT=$(($CNT+1))
                progress_bar
        done

        TST=`echo $SRC | cut -d " " -f 1`
        if [ "$TST" == "object-group" ]
        then
                OBJGRP=`echo $SRC | cut -d " " -f 2`
                OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
        elif [ "$TST" == "host" ]
        then
                NAME=`echo $SRC | cut -d " " -f 2`
                IPS="$IPS $NAME"
        elif [ "$TST" != "any" ]
        then
                IPS="$IPS $TST"
        fi

        TST=`echo $DST | cut -d " " -f 1`
        if [ "$TST" == "object-group" ]
        then
                OBJGRP=`echo $DST | cut -d " " -f 2`
                OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
        elif [ "$TST" == "host" ]
        then
                NAME=`echo $DST | cut -d " " -f 2`
                IPS="$IPS $NAME"
        elif [ "$TST" != "any" ]
        then
                IPS="$IPS $TST"
        fi

        TST=`echo $PORT | cut -d " " -f 1`
        if [ "$TST" == "object-group" ]
        then
                OBJGRP=`echo $PORT | cut -d " " -f 2`
                OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
        elif [ "$TST" == "host" ]
        then
                NAME=`echo $PORT | cut -d " " -f 2`
                IPS="$IPS $NAME"
        elif [ "$TST" != "log" ] && [ "$TST" != "eq" ]
        then
                IPS="$IPS $TST"
        fi

	TST=`echo $PROTO | cut -d " " -f 1`
	if [ "$TST" == "object-group" ]
	then
		OBJGRP=`echo $PROTO | cut -d " " -f 2`
		OBJECTGROUPS="$OBJECTGROUPS $OBJGRP"
	fi
done < PIX/per-int/outside
PROGRESS=99
progress_bar

echo "Extract IPS from object groups"
for OBJGRP in $OBJECTGROUPS
do
        getips "$OBJGRP"
done



# renumber lines for acl
sed -i "s/access-list $OUTACL /access-list $ACLNAME /" PIX/per-int/outside

rm -rf .tmp-outside
while read LINE
do
	echo "$LINE" | sed "s/ extended / extended line $ACLSTART /" >> .tmp-outside
	ACLSTART=$(($ACLSTART+1))
done < PIX/per-int/outside

mv .tmp-outside PIX/per-int/outside

# update DM_INLINE object groups to not overlap with existing i.e. prefix with 99
sed -i "s/DM_INLINE_NETWORK_/DM_INLINE_NETWORK_99/" PIX/per-int/object-group
sed -i "s/DM_INLINE_NETWORK_/DM_INLINE_NETWORK_99/" PIX/per-int/$INACL
sed -i "s/DM_INLINE_NETWORK_/DM_INLINE_NETWORK_99/" PIX/per-int/outside
sed -i "s/DM_INLINE_SERVICE_/DM_INLINE_SERVICE_99/" PIX/per-int/object-group
sed -i "s/DM_INLINE_SERVICE_/DM_INLINE_SERVICE_99/" PIX/per-int/$INACL
sed -i "s/DM_INLINE_SERVICE_/DM_INLINE_SERVICE_99/" PIX/per-int/outside
sed -i "s/DM_INLINE_TCP_/DM_INLINE_TCP_99/" PIX/per-int/object-group
sed -i "s/DM_INLINE_TCP_/DM_INLINE_TCP_99/" PIX/per-int/$INACL
sed -i "s/DM_INLINE_TCP_/DM_INLINE_TCP_99/" PIX/per-int/outside
sed -i "s/DM_INLINE_UDP_/DM_INLINE_UDP_99/" PIX/per-int/object-group
sed -i "s/DM_INLINE_UDP_/DM_INLINE_UDP_99/" PIX/per-int/$INACL
sed -i "s/DM_INLINE_UDP_/DM_INLINE_UDP_99/" PIX/per-int/outside

