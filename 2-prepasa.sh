#!/bin/bash
#
# Takes the files in the filer PIX and makes an ASA configuration
#
# George Horton - 5/14

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
if [ "$1" == "" ]
then
	echo "usage: 2-makeasa.sh <ASAVER>"
	exit 1
fi

ASAVER=$1

echo "Cleaning up existing DIRs"
rm -rf ASA
mkdir ASA

# names to objects
echo "Converting names to objects"
PROGRESS=0
progress_bar

cp PIX/object ASA/object
rm -f .tmp-multiobject
rm -f .tmp-multi

while read LINE
do

	IP=`echo $LINE | cut -d " " -f 2`
	NAME=`echo $LINE | cut -d " " -f 3`
	DESC=`echo $LINE | cut -d " " -f 5-`

	HOST=0
	SUBNETS=""

	# find where the IP is used
	# 1 object-group
	BEFORE=`grep -o -P "[a-zA-Z0-9\.\-_]+ $IP\b" PIX/object-group | cut -d " " -f 1 | sort | uniq`
	AFTER=`grep -o -P " $IP [0-9\.]+" PIX/object-group | cut -d " " -f 3 | sort | uniq | grep -f subnets`

	#remove any entries for 255.255.255.255
	HOSTSUBCNT=`echo "$AFTER" | grep "255.255.255.255" -c`
	if [ $HOSTSUBCNT -gt 0 ]
	then
		TMPAFTER=`echo $AFTER | grep -v "255.255.255.255"`
		AFTER=`echo "$TMPAFTER"`
		HOST=1
	fi

	HOSTCNT=`echo "$BEFORE" | grep "host" -c`
	if [ $HOSTCNT -gt 0 ]
	then
		HOST=1
	fi
	
	if [ "$AFTER" != "" ]
	then
		SUBNETS=`echo -e "$AFTER"`
	fi

	# 2 ACLS
	BEFORE=`grep -o -P "[a-zA-Z0-9\.\-_]+ $IP\b" PIX/ACLS/* | cut -d " " -f 1 | sort | uniq`
	AFTER=`grep -o -P " $IP [0-9\.]+" PIX/ACLS/* | cut -d " " -f 3 | sort | uniq | grep -f subnets`
	
        #remove any entries for 255.255.255.255
        HOSTSUBCNT=`echo "$AFTER" | grep "255.255.255.255" -c`
        if [ $HOSTSUBCNT -gt 0 ]
        then
                TMPAFTER=`echo $AFTER | grep -v "255.255.255.255"`
                AFTER=`echo "$TMPAFTER"`
                HOST=1
        fi

        HOSTCNT=`echo "$BEFORE" | grep "host" -c`
        if [ $HOSTCNT -gt 0 ]
        then
                HOST=1
        fi

	if [ "$AFTER" != "" ]
	then
	        TMPSUBNETS=`echo -e "$SUBNETS\n$AFTER"`
		SUBNETS=`echo "$TMPSUBNETS" | sort | uniq`
	fi

	# Generate the object code
	if [ $HOST -eq 1 ] && [ "$SUBNETS" != "" ]
	then
		echo "HOST-$NAME:host $IP" >> .tmp-multiobject
		echo -e "object network HOST-$NAME\n host $IP" >> ASA/object
		if [ "$DESC" != "" ]
		then
			echo -e " description $DESC" >> ASA/object
		fi

		for SUBNET in $SUBNETS
		do
			CIDR=`ipcalc -p $IP $SUBNET | cut -d "=" -f 2`
			echo "NET_$CIDR-$NAME:$IP $SUBNET" >> .tmp-multiobject
			echo -e "object network NET_$CIDR-$NAME\n subnet $IP $SUBNET" >> ASA/object
	                if [ "$DESC" != "" ]
	                then
	                        echo -e " description $DESC" >> ASA/object
	                fi
		done
	elif [ $HOST -eq 1 ]
	then
		echo "$NAME:host $IP" >> .tmp-multi
                echo -e "object network $NAME\n host $IP" >> ASA/object
                if [ "$DESC" != "" ]
                then
                        echo -e " description $DESC" >> ASA/object
                fi
	elif [ "$SUBNETS" != "" ]
	then
                for SUBNET in $SUBNETS
                do
			echo "$NAME:$IP $SUBNET" >> .tmp-multi
                        echo -e "object network $NAME\n subnet $IP $SUBNET" >> ASA/object
                        if [ "$DESC" != "" ]
                        then
                                echo -e " description $DESC" >> ASA/object
                        fi
                done
	fi
	progress_bar
done < PIX/name
PROGRESS=99
progress_bar

# Update the object-groups with the new objects
cp PIX/object-group ASA/object-group
echo "Updating object-groups with the new objects"
PROGRESS=0
progress_bar

# sort out the odd ones first
while read LINE
do
	REPLACE=`echo $LINE | cut -d ":" -f 1`
	FIND=`echo $LINE | cut -d ":" -f 2`

	sed -i "s/$FIND\$/object $REPLACE/" ASA/object-group
	progress_bar
done < .tmp-multiobject

while read LINE
do
        REPLACE=`echo $LINE | cut -d ":" -f 1`
        FIND=`echo $LINE | cut -d ":" -f 2`

        sed -i "s/$FIND\$/object $REPLACE/" ASA/object-group
	progress_bar
done < .tmp-multi
PROGRESS=99
progress_bar

# Update tyhe ACLS with the new objects
cp -r PIX/ACLS ASA

for ACL in `ls ASA/ACLS`
do
	echo "Updating ACL $ACL with the new objects"
	PROGRESS=0
	progress_bar
	while read LINE
	do
	        REPLACE=`echo $LINE | cut -d ":" -f 1`
	        FIND=`echo $LINE | cut -d ":" -f 2`
	
	        sed -i "s/$FIND /object $REPLACE /" ASA/ACLS/$ACL
	        progress_bar
	done < .tmp-multiobject

	while read LINE
	do
	        REPLACE=`echo $LINE | cut -d ":" -f 1`
	        FIND=`echo $LINE | cut -d ":" -f 2`
	
	        sed -i "s/$FIND /object $REPLACE /" ASA/ACLS/$ACL
	        progress_bar
	done < .tmp-multi
	PROGRESS=99
	progress_bar

done

#access groups
cp PIX/access-group ASA/access-group

# routes
cp PIX/route ASA/route

# NAT
# Lets start by going through the generic 'NAT' statements
rm -rf ASA/NAT
mkdir -p ASA/NAT

echo "Processing Dynamic NAT"

PROGRESS=0
progress_bar
while read NAT
do
        INT=`echo $NAT | cut -d " " -f 2 | sed "s/[\(\)]//g"`
        GLOBAL=`echo $NAT | cut -d " " -f 3`
        ACLCHECK=`echo $NAT | cut -d " " -f 4`
        ACL=`echo $NAT | cut -d " " -f 5`

        if [ "$ACLCHECK" == "access-list" ]
        then
                while read ACLLINE
                do
                        PROTO=`echo $ACLLINE | cut -d " " -f 5`
                        OBJGROUPCHK=`echo $ACLLINE | cut -d " " -f 6`
                        SOURCE=`echo $ACLLINE | cut -d " " -f 7`
                        if [ "$OBJGROUPCHK" == "any" ]
                        then
                                SOURCE=$OBJGROUPCHK
                        elif [ "$OBJGROUPCHK" != "object-group" ]
                        then
                                SOURCELINENO=`grep -n "$OBJGROUPCHK $SOURCE" ASA/object`
                                if [ $? -eq 0 ]
                                then
                                        SOURCELINENO=`echo $SOURCELINENO |  cut -d ":" -f 1`
                                        SOURCELINENO=$(($SOURCELINENO-1))q
                                        SOURCE=`sed "$SOURCELINENO;d" ASA/object | cut -d " " -f 3`
                                else
                                        PREFIX=`ipcalc -p $OBJGROUPCHK $SOURCE | cut -d "=" -f 2`
                                        echo -e "object network net-$OBJGROUPCHK-$PREFIX\n subnet $OBJGROUPCHK $SOURCE" >> ASA/object
                                        SOURCE="net-$OBJGROUPCHK-$PREFIX"
                                fi
                        fi
			progress_bar

                        OBJGROUPCHK=`echo $ACLLINE | cut -d " " -f 8`
                        DESTINATION=`echo $ACLLINE | cut -d " " -f 9`
                        if [ "$OBJGROUPCHK" == "any" ]
                        then
                                DESTINATION=$OBJGROUPCHK
                        elif [ "$OBJGROUPCHK" != "object-group" ]
                        then
                                DESTINATIONLINENO=`grep -n "$OBJGROUPCHK $DESTINATION" ASA/object`
                                if [ $? -eq 0 ]
                                then
                                        DESTINATIONLINENO=`echo $DESTINATIONLINENO |  cut -d ":" -f 1`
                                        DESTINATIONLINENO=$(($DESTINATIONLINENO-1))q
                                        DESTINATION=`sed "$DESTINATIONLINENO;d" ASA/object | cut -d " " -f 3`
                                else
                                        PREFIX=`ipcalc -p $OBJGROUPCHK $DESTINATION | cut -d "=" -f 2`
                                        echo -e "object network net-$OBJGROUPCHK-$PREFIX\n subnet $OBJGROUPCHK $DESTINATION" >> ASA/object
                                        DESTINATION="net-$OBJGROUPCHK-$PREFIX"
                                fi
                        fi
			progress_bar

                        if [ "$PROTO" != "ip" ]
                        then
                                PORT=`echo $ACLLINE | cut -d " " -f 10`
                                # try to find the port object first
                                PORTLINENO=`grep -n " service $PROTO destination eq $PORT" ASA/object`
                                if [ $? -eq 0 ]
                                then
                                        PORTLINENO=`echo $PORTLINENO | cut -d ":" -f 1`
                                        PORTLINENO=$(($PORTLINENO-1))q
                                        PORTOBJ=`sed "$PORTLINENO;d" ASA/object | cut -d " " -f 3`
                                else
                                        echo -e "object service $PROTO-$PORT\n service $PROTO destination eq $PORT" >> ASA/object
                                        PORTOBJ="$PROTO-$PORT"
                                fi
                        else
                                PORTOBJ=""
                        fi
			progress_bar

                        if [ $GLOBAL -eq 0 ]
                        then
                                #NAT EXEMPT
                                echo "nat ($INT,any) source static $SOURCE $SOURCE destination static $DESTINATION $DESTINATION" >> ASA/NAT/exempt
                        else
                                #Dynamic NAT
                                # Get the global ip
                                GLOBALIP=`grep " $GLOBAL " PIX/NAT/global | cut -d " " -f 4`
                                OTHERINT=`grep " $GLOBAL " PIX/NAT/global | cut -d " " -f 2 | sed "s/[\(\)]//g"`
                                # get the object name
                                IPLINENO=`grep -n " $GLOBALIP" ASA/object`
                                if [ $? -eq 0 ]
                                then
                                        IPLINENO=`echo $IPLINENO | cut -d ":" -f 1`
                                        IPLINENO=$(($IPLINENO-1))q
                                        OBJ=`sed "$IPLINENO;d" ASA/object | cut -d " " -f 3`
                                else
                                        echo -e "object network srv-$GLOBALIP\n host $GLOVALIP"
                                        OBJ="srv-$GLOBALIP"
                                fi

                                if [ "$PORTOBJ" == "" ]
                                then
                                        echo "nat ($INT,$OTHERINT) source dynamic $SOURCE $OBJ" >> ASA/NAT/dynamic
                                else
                                         echo "nat ($INT,$OTHERINT) source dynamic $SOURCE $OBJ service $PORTOBJ $PORTOBJ" >> ASA/NAT/dynamic
                                fi
                        fi
			progress_bar
                done < PIX/NAT/ACLS/$ACL
        else
                SOURCELINENO=`grep -n "$ACLCHECK $ACL" ASA/object`
                if [ $? -eq 0 ]
                then
                        SOURCELINENO=`echo $SOURCELINENO | cut -d ":" -f 1`
                        SOURCELINENO=$(($SOURCELINENO-1))q
                        SOURCE=`sed "$SOURCELINENO;d" ASA/object | cut -d " " -f 3`
                else
                        PREFIX=`ipcalc -p $ACLCHECK $ACL | cut -d "=" -f 2`
                        echo -e "object network net-$ACLCHECK-$PREFIX\n subnet $ACLCHECK $ACL" >> ASA/object
                        SOURCE="net-$ACLCHECK-$PREFIX"
                fi
		progress_bar
                if [ $GLOBAL -eq 0 ]
                then
                        #NAT Exempt

                        echo "nat ($INT,any) source dynamic $SOURCE $SOURCE" >> ASA/NAT/exempt
                else
                        #Dynamic NAT
                        GLOBALIP=`grep " $GLOBAL " PIX/NAT/global | cut -d " " -f 4`
                        OTHERINT=`grep " $GLOBAL " PIX/NAT/global | cut -d " " -f 2 | sed "s/[\(\)]//g"`
                        # get the object name
                        IPLINENO=`grep -n " $GLOBALIP" ASA/object`
                        if [ $? -eq 0 ]
                        then
                                IPLINENO=`echo $IPLINENO | cut -d ":" -f 1`
                                IPLINENO=$(($IPLINENO-1))q
                                OBJ=`sed "$IPLINENO;d" ASA/object | cut -d " " -f 3`
                        else
                                echo -e "object network srv-$GLOBALIP\n host $GLOBALIP" >> ASA/object
                                OBJ="srv-$GLOBALIP"
                        fi

                        echo "nat ($INT,$OTHERINT) source dynamic $SOURCE $OBJ" >> ASA/NAT/dynamic
                fi
		progress_bar
        fi
	progress_bar
done < PIX/NAT/nat
PROGRESS=99
progress_bar

echo "Processing Static NAT"
rm -f .tmp-nat
PROGRESS=0
progress_bar
while read STATIC
do
        INTS=`echo $STATIC | cut -d " " -f 2 | sed "s/[\(\)]//g"`
        INSIDEIF=`echo $INTS | cut -d "," -f 1`
        OUTSIDEIF=`echo $INTS | cut -d "," -f 2`
        INSIDEIP=`echo $STATIC | cut -d " " -f 4`
        OUTSIDEIP=`echo $STATIC | cut -d " " -f 3`
        NETMASK=`echo $STATIC | cut -d " " -f 6`

        if [ "$INSIDEIP" == "access-list" ]
        then
                ACL=`echo $STATIC | cut -d " " -f 5`
                while read ACLLINE
                do
                        HOSTCHK=`echo $ACLLINE | cut -d " " -f 6`
                        if [ "$HOSTCHK" == "host" ]
                        then
                                SOURCE=`echo $ACLLINE | cut -d " " -f 7`
                        else
                                SOURCE=`echo $ACLLINE | cut -d " " -f 6,7`
                        fi

			progress_bar
                        SOURCELINENO=`grep -n " $SOURCE" ASA/object`
                        if [ $? -eq 0 ]
                        then
                                SOURCELINENO=`echo $SOURCELINENO | cut -d ":" -f 1`
                                SOURCELINENO=$(($SOURCELINENO-1))q
                                SOURCEOBJ=`sed "$SOURCELINENO;d" ASA/object | cut -d " " -f 3`
                        else
                                if [ "$HOSTCHK" == "host" ]
                                then
                                        echo -e "object network srv-$SOURCE\n host $SOURCE"
                                        SOURCEOBJ="srv-$SOURCE"
                                else
                                        PREFIX=`ipcalc -p $SOURCE`
                                        echo -e "object network net-$SOURCE\n subnet $SOURCE"
                                        SOURCEOBJ="net-$SOURCE"
                                fi
                        fi

			progress_bar
                        HOSTCHK=`echo $ACLLINE | cut -d " " -f 8`
                        if [ "$HOSTCHK" == "host" ]
                        then
                                DESTINATION=`echo $ACLLINE | cut -d " " -f 9`
                        else
                                DESTINATION=`echo $ACLLINE | cut -d " " -f 8,9`
                        fi

			progress_bar
                        DESTLINENO=`grep -n " $DESTINATION" ASA/object`
                        if [ $? -eq 0 ]
                        then
                                DESTLINENO=`echo $DESTLINENO | cut -d ":" -f 1`
                                DESTLINENO=$(($DESTLINENO-1))q
                                DESTOBJ=`sed "$DESTLINENO;d" ASA/object | cut -d " " -f 3`
                        else
                                if [ "$HOSTCHK" == "host" ]
                                then
                                        echo -e "object network srv-$DESTINATION\n host $DESTINATION"
                                        DESTOBJ="srv-$DESTINATION"
                                else
                                        PREFIX=`ipcalc -p $DESTINATION`
                                        echo -e "object network net-$DESTINATION\n subnet $DESTINATION"
                                        DESTOBJ="net-$DESTINATION"
                                fi
                        fi

			progress_bar
                        OUTSIDEIPLINE=`grep -n " $OUTSIDEIP" ASA/object`
                        if [ $? -eq 0 ]
                        then
                                OUTSIDEIPLINE=`echo $OUTSIDEIPLINE | cut -d ":" -f 1`
                                OUTSIDEIPLINE=$(($OUTSIDEIPLINE-1))q
                                OUTSIDEOBJ=`sed "$OUTSIDEIPLINE;d" ASA/object | cut -d " " -f 3`
                        else
                                echo -e "object network srv-$OUTSIDEIP\n host $OUTSIDEIP" >> ASA/object
                                OUTSIDEOBJ="srv-$OUTSIDEIP"
                        fi

			progress_bar
                        echo "nat ($INSIDEIF,$OUTSIDEIF) source static $SOURCEOBJ $OUTSIDEOBJ destination static $DESTOBJ $DESTOBJ" >> ASA/NAT/static

                done < PIX/NAT/ACLS/$ACL
		progress_bar
        else
                INSIDEIPLINE=`grep -n " $INSIDEIP" ASA/object`
                if [ $? -eq 0 ]
                then
                        # get object from file
                        INSIDEIPLINE=`echo $INSIDEIPLINE | cut -d ":" -f 1`
                        INSIDEIPLINE=$(($INSIDEIPLINE-1))q
                        INSIDEOBJ=`sed "$INSIDEIPLINE;d" ASA/object | cut -d " " -f 3`
                else
                        if [ "$NETMASK" == "255.255.255.255" ]
                        then
                                echo -e "object network srv-$INSIDEIP\n host $INSIDEIP" >> ASA/object
                                INSIDEOBJ="srv-$INSIDEIP"
                        else
                                PREFIX=`ipcalc -p $INSIDEIP $NETMASK | cut -d "=" -f 2`
                                echo -e "object network net-$INSIDEIP-$PREFIX\n subnet $INSIDEIP $NETMASK" >> ASA/object
                                INSIDEOBJ="net-$INSIDEIP-$PREFIX"
                        fi
			progress_bar
                        # put object into file
                fi
		progress_bar

                OUTSIDEIPLINE=`grep -n " $OUTSIDEIP" ASA/object`
                if [ $? -eq 0 ]
                then
                        OUTSIDEIPLINE=`echo $OUTSIDEIPLINE | cut -d ":" -f 1`
                        OUTSIDEIPLINE=$(($OUTSIDEIPLINE-1))q
                        OUTSIDEOBJ=`sed "$OUTSIDEIPLINE;d" ASA/object | cut -d " " -f 3`
                else
                        if [ "$NETMASK" == "255.255.255.255" ]
                        then
                                echo -e "object network srv-$OUTSIDEIP\n host $OUTSIDEIP" >> ASA/object
                                OUTSIDEOBJ="srv-$OUTSIDEIP"
                        else
                                PREFIX=`ipcalc -p $OUTSIDEIP $NETMASK | cut -d "=" -f 2`
                                echo -e "objecvt network net-$OUTSIDEIP-$PREFIX\n subnet $OUTSIDEIP $NETMASK" >> ASA/object
                                OUTSIDEOBJ="net-$OUTSIDEIP-$PREFIX"
                        fi
                fi
		progress_bar
                echo "nat ($INSIDEIF,$OUTSIDEIF) source static $INSIDEOBJ $OUTSIDEOBJ" >> ASA/NAT/static
        fi

        OUTINT=`grep "0.0.0.0 0.0.0.0" PIX/route | cut -d " " -f 2`
        OUTACL=`grep " $OUTINT" PIX/access-group | cut -d " " -f 2`

        if [ "$OUTSIDEIF" == "$OUTINT" ]
        then
                if [ "$NETMASK" == "255.255.255.255" ]
                then
			echo "host $OUTSIDEIP|$OUTSIDEOBJ|$INSIDEOBJ" >> .tmp-nat
                else
			echo "$OUTSIDEIP $NETMASK|$OUTSIDEOBJ|$INSIDEOBJ" >> .tmp-nat
                fi
        fi
	progress_bar
done < PIX/NAT/static
PROGRESS=99
progress_bar

echo "Fixing Outside ACL with inside IPs from NAT rules"
OUTINT=`grep "0.0.0.0 0.0.0.0" PIX/route | cut -d " " -f 2`
OUTACL=`grep " $OUTINT" PIX/access-group | cut -d " " -f 2`

echo "Done!"
