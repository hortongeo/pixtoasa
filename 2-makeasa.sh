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

rm -rf ASA
mkdir ASA

# Names are still useful, copy these over
cp PIX/name ASA/name

# names to objects
cp PIX/object ASA/object
rm -f .tmp-multiobject

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
	AFTER=`grep -o -P " $IP [0-9\.]+" PIX/object-group | cut -d " " -f 3 | sort | uniq`

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
	AFTER=`grep -o -P " $IP [0-9\.]+" PIX/ACLS/* | cut -d " " -f 3 | sort | uniq`
	
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
                echo -e "object network $NAME\n host $IP" >> ASA/object
                if [ "$DESC" != "" ]
                then
                        echo -e " description $DESC" >> ASA/object
                fi
	elif [ "$SUBNETS" != "" ]
	then
                for SUBNET in $SUBNETS
                do
                        echo -e "object network $NAME\n subnet $IP $SUBNET" >> ASA/object
                        if [ "$DESC" != "" ]
                        then
                                echo -e " description $DESC" >> ASA/object
                        fi
                done
	fi
	
done < PIX/name
