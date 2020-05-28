#!/bin/bash
DIRS=${1}
NAMEOFBACKUP=${2}
ERROR_STRING='Permission denied'
EXTRACT_ERROR_STRING=Errno
FUSEPATH=/mnt/goofys
BUCKET=${3}
REPOSITORY=${FUSEPATH}/borg1

PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
TAIL=50
TIMEOUT_OPER=${TIMEOUT:-23h}
KILL_TIMEOUT_SIGNAL=TERM
SLEEP4MOUNT=25
ret=0
NOW=`date +%Y-%m-%d.%a`
NAMEOFBACKUP=${NAMEOFBACKUP}-${NOW}
PROC_NAME="$(basename "$0")"
PROC_PID=`echo $$`
PROC_LOCK_FILE="/tmp/${PROC_NAME}.pid"

# Colors
Red="\033[1;31m";
Yellow="\033[0;33m";
Green="\033[0;32m";
Blue="\033[0;34m";
Purple="\033[0;35m";
Gray="\033[1;30m";
NC="\033[0m"; # No Color
Bold="\e[1m";
COLORMSG=$Yellow

# Check lock file
if [ -f ${PROC_LOCK_FILE} ] ; then
		# echo "Lock file exists"
		pidof -o %PPID -x $0 >/dev/null && echo "ERROR: Script $0 already running" && exit 123
		echo "WARRNING: Lock file exists, but no procces."
fi
echo ${PROC_PID} > ${PROC_LOCK_FILE}
TMP=$(mktemp)
echo > ./error.log # Cleanup old log

# Stdout direction
if [ "$VERBOSE" == "1" ] ; then
	v=1
else
	v=0
	exec 6>&1
	exec &>$TMP
fi

# Support functions
function checklog() {
	# Check for fail string
	if [ "$v" == 1 ] ; then
			printf "${COLORMSG}Can't parse log in VERBOSE mode${NC}\n"
		ret=5
		exit $ret
	fi
	grep "${ERROR_STRING}" ${TMP} >/dev/null
	if [ "$?" == 0 ] ; then
		ret=127
			printf "${COLORMSG}Log have error string '${ERROR_STRING}'${NC}\n" && printf "${COLORMSG}###############${NC}\n"
		EXTRACT_ERROR_STRING=${ERROR_STRING}
		forcepostscript
		exit $ret
	fi
}

function ret() {
	# Exit with errors
	ret=$1
	if [ $ret -eq 124 ]; then # Exit code of timeout
				 printf "${COLORMSG}Timeout in ${TIMEOUT_OPER}\n###############${NC}\n"
	fi
	if [ $ret -gt 0 ]; then
				printf "${COLORMSG}Exit with error ${ret}${NC}\n" && printf "${COLORMSG}###############${NC}\n"
			forcepostscript
			exit $ret
	fi
}

function checktimeout() {
	# Exit with errors
	ret=$1
	if [ $ret -eq 124 ]; then # Exit code of timeout
			printf "${COLORMSG}Timeout in ${TIMEOUT_OPER}\n###############${NC}\n"
		forcepostscript
		exit $ret
	fi
}

function cleanup() {
	if [ "$v" == "0" ] && [ $ret -gt 0 ] || [ "${SAVELOGSONSUCCES}" == 1 ] ; then
		cat ${TMP} >> ./error.log
		exec 1>&6 6>&-
			printf "${COLORMSG}--------------- Last of ${TAIL} strings ---------------${NC}\n"
		tail -${TAIL} ${TMP}
		grep "${EXTRACT_ERROR_STRING}" ${TMP} >/dev/null
		if [ "$?" == 0 ] ; then
				printf "${COLORMSG}--------------- Error string  ---------------${NC}\n"
			grep "${EXTRACT_ERROR_STRING}" ${TMP} | head -5
		fi
	fi
	# Cleanup log
	finish=`date +%s`
	rm -f ${TMP}
	rm -f ${PROC_LOCK_FILE}
		printf "${COLORMSG}Finished `date`, $((${finish}-${start})) seconds${NC}\n"
		logger "${0} finished with error $ret"
	exit $ret
}

# Work functions
function prepare() {
		printf "${COLORMSG}--------------- Prepare ---------------${NC}\n"
	goofys -f -o allow_other --endpoint https://storage.yandexcloud.net --file-mode=0666 --dir-mode=0777 ${BUCKET} ${FUSEPATH} &
	GOOFYS_PID=$!
	sleep ${SLEEP4MOUNT}
	ERROR_STRING=FATAL
	checklog
}

function testcheck() {
	# Something for a test
		printf "${COLORMSG}--------------- Check operation ---------------${NC}\n"
		timeout -s $KILL_TIMEOUT_SIGNAL -k 1 5m \
			borg list ${REPOSITORY} || ret $?
}

function forcepostscript() {
		printf "${COLORMSG}--------------- Postscript operations ---------------${NC}\n"
	kill -SIGINT ${GOOFYS_PID} &&	sleep ${SLEEP4MOUNT}
}

function maincommand() {
		printf "${COLORMSG}--------------- Main command ---------------${NC}\n"
	timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
		borg create --stats --list ${REPOSITORY}::"${NAMEOFBACKUP}" ${DIRS}  || ret $?
}

# Started
start=`date +%s`
	printf "${COLORMSG}Started `date`${NC}\n"
	logger "${0} started with ${1} ${2}"
trap cleanup EXIT

# Call functions
prepare
testcheck
maincommand
forcepostscript || ret $?

trap - EXIT
cleanup

exit 0
