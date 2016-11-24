#!/bin/bash
#
# dbs: dumb backup script
#
# Author: Christian Kuhn  <lolli@schwarzbu.ch>
#
# Init:
# $DATAPATH/.zyklus file must exist, initialize content with -1
# $DATAPATH/dirs file must contain absolute pathes to to-be-backed up dirs
# $DATAPATH/.medium file should be initalized with 3 2 1 6 5 4 0
# $DATAPATH/medium "0-6" dirs must exist!
#
# Howto
# Unpack archive in /tmp
#  dar -x datapath/mediumX/mybackup -R /tmp/
# Test archive
#  dar -t datapath/mediumX/mybackup_diffX
# List content of archive
#  dar -l datapath/mediumX/mybackup_diffX
# Extract one file from archive to /tmp
# dar -x datapath/mediumX/mybackup_diffX -g sqldump/dump.sql -R /tmp/
# Example with list of files in medium6.txt: for i in $(cat medium6.txt); do dar -wa -q -x /mirror/ARCHIVE/logs/medium6/mirror_dir.org -g $i -R /mirror/ARCHIVE/logs/medium6/; done
#
#
# Version 0.1	2003-08-07
#	- initial release
# Version 0.2	2005-06-16
#	- minor changes for mhn on m&v
#	- removed mysqldump
#	- no gzip any longer
#	- added time to dar process to track time consumption
# Version 0.3   2009-09-08
#	- adapted to current infrastructure
#	- addded before and after hook scripts
# Version 0.4	2010-01-29
#	- adapted for backup server, more zip excludes
# Version 0.5	2010-02-03
#	- Now using make to parallelize processes
# Version 0.5.1 2011-01-24
#	- Fixed outdated comment

# Initialize cycle
DAYZYKLUS=7
WEEKZYKLUS=4
MONTHZYKLUS=3

# Backup path (absolute, without trailing slash)
DATAPATH="/backup"

# Makefile path to be created
MAKEFILE="/root/bin/Makefile-dbs"

# Log-dir to be send as mail (absolute, without trailing slash)
LOGDIR="/root/backup-temp-log/dbs"

# Binaries used
CAT="/bin/cat"
AWK="/usr/bin/awk"
SED="/bin/sed"
DAR="/usr/bin/dar"
ECHO="/bin/echo"
CP="/bin/cp"
MV="/bin/mv"
RM="/bin/rm"
BZIP2="/usr/bin/bzip2"
MAKE="/usr/bin/make"

if [ $# -ne 1 ]; then
	echo
	echo "Please add some parameter if you really want to do something useful :-)"
	echo
	echo "While you are here we would like to entertain you with some happy little dar parameters"
	echo "  unpack some archive: dar -x dar-file -R /tmp/"
	echo "  list content of archive: dar -l dar-file"
	echo "  extract some file from archive: dar -x dar-file -g path/to/file"
	echo
	echo "As you probably will read this if your ass is burning: Happy hacking :-)"
	echo
	exit 1
fi

read W1 W2 W3 W4 M2 M3 M4 < $DATAPATH/.medium

read ZYKLUS < $DATAPATH/.zyklus
let "ZYKLUS = ZYKLUS + 1"
if [ $ZYKLUS -ge 84 ]; then
	let "ZYKLUS = 0"
fi
echo "Zyklus: $ZYKLUS"
echo

let "DAY = ZYKLUS % DAYZYKLUS"

# Delete old Makefile
$RM $MAKEFILE

case "$DAY" in
	0)
		let "WEEK = ZYKLUS % WEEKZYKLUS"
		case "$WEEK" in
			0)
				let "MONTH = WEEK % MONTHZYKLUS"
				case "$MONTH" in
					0)
						$ECHO "MONATSZYKLUS"
						$ECHO
						TEMP=$M4
						M4=$M3
						M3=$M2
						M2=$W4
						W4=$W3
						W3=$W2
						W2=$W1
						W1=$TEMP
						$ECHO "$W1 $W2 $W3 $W4 $M2 $M3 $M4" > $DATAPATH/.medium
					;;
					*)
					;;
				esac
			;;
			*)
				$ECHO "WOCHENZYKLUS"
				$ECHO
				TEMP=$W4
				W4=$W3
				W3=$W2
				W2=$W1
				W1=$TEMP
				$ECHO "$W1 $W2 $W3 $W4 $M2 $M3 $M4" > $DATAPATH/.medium
			;;
		esac
		$ECHO "Full backup to medium $W1"
		$ECHO $W1 > $DATAPATH/current_medium
		$RM $DATAPATH/medium$W1/*
		# Write date
		echo `date` > $DATAPATH/medium$W1/.date
		TARGETS=`$CAT $DATAPATH/dirs | $AWK '{ print $1; }'`

		# Init make all command
		MAKEALL="all:"

		for TARGET in $TARGETS; do
			FILENAME=`$ECHO $TARGET | $SED -e "s/\//_/g" -e "s/^_//"`

			# Create makefile entry
			echo "${FILENAME}: " >> $MAKEFILE
			echo "	echo \"${FILENAME}: \" >> ${LOGDIR}/${FILENAME}; cd /; ${DAR} -z -Z \"*.zip\" -Z \"*.tgz\" -Z \"*.tar.bz2\" -Z \"*.gz\" -Z \"*.gif\" -Z \"*.jpg\" -Z \"*.png\" -Z \"*.pdf\" -c ${DATAPATH}/medium${W1}/${FILENAME} -R ${TARGET} >> ${LOGDIR}/${FILENAME} 2>&1; ${DAR} -t ${DATAPATH}/medium${W1}/${FILENAME} >> ${LOGDIR}/${FILENAME} 2>&1" >> $MAKEFILE
			echo >> $MAKEFILE
			MAKEALL="${MAKEALL} ${FILENAME}"
		done

		# Finalize makefile with all command
		echo $MAKEALL >> $MAKEFILE
	;;
	*)
		$ECHO "Incremential backup to medium $W1"
		echo `date` > $DATAPATH/medium$W1/.date$DAY
		TARGETS=`$CAT $DATAPATH/dirs | $AWK '{ print $1; }'`
		$RM $DATAPATH/medium$W2/.date$DAY

		# Init make all command
		MAKEALL="all:"

		for TARGET in $TARGETS; do
			FILENAME=`$ECHO $TARGET | $SED -e "s/\//_/g" -e "s/^_//"`
			DIFFNAME=`$ECHO $FILENAME"_diff"$DAY`

			# Delete last weekly backup
			$RM $DATAPATH/medium$W2/$DIFFNAME.1.dar

			# Create makefile entry
			echo "${FILENAME}: " >> $MAKEFILE
			echo "	echo \"${FILENAME}: \" >> ${LOGDIR}/${FILENAME}; cd /; ${DAR} -z -Z \"*.zip\" -Z \"*.tgz\" -Z \"*.tar.bz2\" -Z \"*.gz\" -Z \"*.gif\" -Z \"*.jpg\" -Z \"*.png\" -Z \"*.pdf\" -c ${DATAPATH}/medium${W1}/${DIFFNAME} -R ${TARGET} -A ${DATAPATH}/medium${W1}/${FILENAME} >> ${LOGDIR}/${FILENAME} 2>&1; ${DAR} -t ${DATAPATH}/medium${W1}/${DIFFNAME} >> ${LOGDIR}/${FILENAME} 2>&1" >> $MAKEFILE
			echo >> $MAKEFILE
			MAKEALL="${MAKEALL} ${FILENAME}"
		done

		# Finalize makefile with all command
		echo $MAKEALL >> $MAKEFILE
	;;
esac

# Execute makefile with 4 processes, ignoring errors (changed to 8 processes after system upgrade)
$MAKE -j8 -i -f $MAKEFILE all


# Echo media cycle
echo
echo "Medienzyklus: "`$CAT $DATAPATH/.medium`
echo
echo

# Update current cycle
$ECHO $ZYKLUS > $DATAPATH/.zyklus