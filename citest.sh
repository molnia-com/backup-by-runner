#!/bin/bash
DIRS=${1}
OPTIONS=${2}
ERROR_STRING=error
EXTRACT_ERROR_STRING=Errno
PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
TAIL=50
TIMEOUT_OPER=${TIMEOUT:-10m}
KILL_TIMEOUT_SIGNAL=TERM
ret=0
NOW=`date +%Y-%m-%d.%a`
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
		cleanup
	fi
	grep "${ERROR_STRING}" ${TMP} >/dev/null
	if [ "$?" == 0 ] ; then
		ret=127
			printf "${COLORMSG}Log have error string '${ERROR_STRING}'${NC}\n" && printf "${COLORMSG}###############${NC}\n"
			printf "${COLORMSG}--------------- grep strings ---------------${NC}\n"
		grep -5 "${ERROR_STRING}" ${TMP}
		forcepostscript
		cleanup
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
			cleanup
	fi
}

function checktimeout() {
	# Exit with errors
	ret=$1
	if [ $ret -eq 124 ]; then # Exit code of timeout
			printf "${COLORMSG}Timeout in ${TIMEOUT_OPER}\n###############${NC}\n"
		forcepostscript
		cleanup
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
	ls -al $OPTIONS ${DIRS:-/}
	# ERROR_STRING=fail
	# checklog
}

function testcheck() {
	# Something for a test
		printf "${COLORMSG}--------------- Check operation ---------------${NC}\n"
	true || ret $?
}

function forcepostscript() {
		printf "${COLORMSG}--------------- Postscript operations ---------------${NC}\n"
	# umount || ret $?
}

function maincommand() {
		printf "${COLORMSG}--------------- Main command ---------------${NC}\n"
	timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
		sleep 2
}

# Started
start=`date +%s`
	printf "${COLORMSG}Started `date`${NC}\n"
	logger "${0} started with ${1} ${2}"
trap cleanup EXIT

# Call functions
prepare || checktimeout $?
testcheck
maincommand || ret $?
forcepostscript || ret $?

trap - EXIT
cleanup

exit 0
