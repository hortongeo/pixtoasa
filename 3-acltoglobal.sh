#!/bin/bash
#
# Takes the split ASA ACLs and combines into one 'global' acl
#
# GH 5/14
#
# This is a pain, so to make life easier some assumptions are going to be imployed
#  (*) any will refer to any subnets which are routed from the orrigionating interface
#  (*) any will be any when the interface has a default route
#  (*) Outside (defined by the default route) will be at the top
#  (*) Other interfaces will be processed in order

# create the new Global ACL
touch ASA/ACLS/global

OUTSIDE=`egrep "0.0.0.0 0.0.0.0" ASA/route | cut -d " " -f 2`

