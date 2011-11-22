#!/bin/sh
#  merge_config.sh - Takes a list of config fragment values, and merges
#  them one by one. Provides warnings on overridden values, and specified
#  values that did not make it to the resulting .config file (due to missed
#  dependencies or config symbol removal).
#
#  Portions reused from kconf_check and generate_cfg:
#  http://git.yoctoproject.org/cgit/cgit.cgi/yocto-kernel-tools/tree/tools/kconf_check
#  http://git.yoctoproject.org/cgit/cgit.cgi/yocto-kernel-tools/tree/tools/generate_cfg
#
#  Copyright (c) 2009-2010 Wind River Systems, Inc.
#  Copyright 2011 Linaro
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.


usage() {
	echo "Usage: $0 [OPTIONS] [CONFIG [...]]"
	echo "  -h    display this help text"
	echo "  -m    only merge the fragments, do not execute the make command"
	echo "  -n    use allnoconfig instead of alldefconfig"
	echo "  -d    debug. Don't cleanup temporary files"
}

MAKE_FLAG=true
ALLTARGET=alldefconfig

# There are two variables that impact where the .config will be dropped, 
# O= and KBUILD_OUTPUT=. So we'll respect those variables and use them as
# an output directory as well. These two variables are not propagating
# automatically to the kernel build, so always explicitly setting O=
# and passing it to the kernel build ensures that it is respected.
if [ -n "$KBUILD_OUTPUT" ]; then
	O=$KBUILD_OUTPUT
fi
if [ -z "$O" ]; then
	O=.
fi

while true; do
	case $1 in
	"-n")
		ALLTARGET=allnoconfig
		shift
		continue
		;;
	"-m")
		MAKE_FLAG=false
		shift
		continue
		;;
	"-d")
		DEBUG=true
		shift
		continue
		;;
	"-h")
		usage
		exit
		;;
	*)
		break
		;;
	esac
done

clean_up() {
       rm -f $TMP_FILE
       exit
}
if [ -z "$DEBUG" ]; then
	trap clean_up SIGHUP SIGINT SIGTERM
fi


MERGE_LIST=$*
SED_CONFIG_EXP="s/^\(# \)\{0,1\}\(CONFIG_[a-zA-Z0-9_]*\)[= ].*/\2/p"
TMP_FILE=$(mktemp $O/.tmp.config.XXXXXXXXXX)

# Merge files, printing warnings on overrided values
for MERGE_FILE in $MERGE_LIST ; do
	echo "Merging $MERGE_FILE"
	CFG_LIST=$(sed -n "$SED_CONFIG_EXP" $MERGE_FILE)

	for CFG in $CFG_LIST ; do
		grep -q -w $CFG $TMP_FILE
		if [ $? -eq 0 ] ; then
			PREV_VAL=$(grep -w $CFG $TMP_FILE)
			NEW_VAL=$(grep -w $CFG $MERGE_FILE)
			if [ "x$PREV_VAL" != "x$NEW_VAL" ] ; then
			echo Value of $CFG is redefined by fragment $MERGE_FILE:
			echo Previous  value: $PREV_VAL
			echo New value:       $NEW_VAL
			echo
			fi
			sed -i "/$CFG[ =]/d" $TMP_FILE
		fi
	done
	cat $MERGE_FILE >> $TMP_FILE
done

if [ "$MAKE_FLAG" = "false" ]; then
	cp $TMP_FILE $O/.config
	echo "#"
	echo "# merged configuration written to $O/.config (needs make)"
	echo "#"
	if [ -z "$DEBUG" ]; then
		clean_up
	fi
	exit
fi

# Use the merged file as the starting point for:
# alldefconfig: Fills in any missing symbols with Kconfig default
# allnoconfig: Fills in any missing symbols with # CONFIG_* is not set
make KCONFIG_ALLCONFIG=$TMP_FILE O=$O $ALLTARGET


# Check all specified config values took (might have missed-dependency issues)
for CFG in $(sed -n "$SED_CONFIG_EXP" $TMP_FILE); do

	REQUESTED_VAL=$(sed -n "$SED_CONFIG_EXP" $TMP_FILE | grep -w -e "$CFG")
	ACTUAL_VAL=$(sed -n "$SED_CONFIG_EXP" $O/.config | grep -w -e "$CFG")
	if [ "x$REQUESTED_VAL" != "x$ACTUAL_VAL" ] ; then
		echo "Value requested for $CFG not in final .config"
		echo "Requested value:  $REQUESTED_VAL"
		echo "Actual value:     $ACTUAL_VAL"
		echo ""
	fi
done

if [ -z "$DEBUG" ]; then
	clean_up
fi