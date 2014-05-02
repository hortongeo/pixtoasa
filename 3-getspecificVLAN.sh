#!/bin/bash
#
# Takes a specific Internal VLAN and provides the outside ACL, inside ACL and required objects and object-groups.
#
# GH 5/2014

if [ "$1" == "" ] || [ "$2" == "" ]
then
	echo "Usage: 3-getspecificVLAN.sh <PIX_CONFIG_FILE> <Interface>"
	exit 1
fi

CONFIG=$1
INTERFACE=$2

IFLINENO=`grep $INTERFACE $CONFIG -n`
if [ $? -eq 1 ]
