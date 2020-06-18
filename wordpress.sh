#!/bin/bash
DIRS=${1}
BACKUPNAME=${2}
ERROR_STRING='Permission denied'
EXTRACT_ERROR_STRING=Errno
FUSEPATH=/mnt/goofys
BUCKET=${3}
PROJECT=${4}
REPOSITORY=${FUSEPATH}/${PROJECT}
MYSQL_DB_NAME=${5}
MYSQL_BACKUP_TEMP_PATH=/var/spool/mysqlbackup

export BORG_FILES_CACHE_TTL=${BORG_FILES_CACHE_TTL:-31}
# export BORG_PASSCOMMAND="cat /root/.borg-passphrase"

PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
# HOME=/root
INIT_REPO_IF_NOT_EXIST=${INIT_REPO_IF_NOT_EXIST:-0}
KEEP_DAILY=${KEEP_DAILY:-7}
KEEP_WEEKLY=${KEEP_WEEKLY:-4}
KEEP_MONTHLY=${KEEP_MONTHLY:-6}
TAIL=50
TIMEOUT_OPER=${TIMEOUT:-5h}
KILL_TIMEOUT_SIGNAL=TERM
SLEEP4MOUNT=25
ret=0
NOW=`date +%Y-%m-%d.%a`
NAMEOFBACKUP=${BACKUPNAME}-${NOW}
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

# Usage
if [ $# -lt 4 ] || [ $# -gt 5 ] ; then
	echo "This script must have 4 or 5 parameters"
	echo "$0 directory_of_backup name_of_backup bucket project [mysql_db]"
	echo "Project is usually \`hostname\`"
	exit 124
fi

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
if [ -v VERBOSE  ] ; then
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
			printf "WARRNING: Can't parse log in VERBOSE mode\n"
		ret=5
		return $ret
		# exit $ret
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
	checklog # Check for errors in log of goofys
	ps p ${GOOFYS_PID} >/dev/null || ret $? # check for the procces
	findmnt ${FUSEPATH} >/dev/null || ret 120 # Did the path mount?
}

function testcheck() {
	# Something for a test
		printf "${COLORMSG}--------------- Check operation ---------------${NC}\n"
		timeout -s $KILL_TIMEOUT_SIGNAL -k 1 5m \
			borg list ${REPOSITORY} || ret $?
}

function borginit() {
	# Something for a test
	if [ "$INIT_REPO_IF_NOT_EXIST" == "1" ] ; then
		printf "${COLORMSG}--------------- Create borg repo ---------------${NC}\n"
		if [ -v BORG_PASSCOMMAND ] || [ -v BORG_PASSPHRASE ] || [ -v BORG_PASSPHRASE_FD ] ; then
			timeout -s $KILL_TIMEOUT_SIGNAL -k 1 1m \
				borg init -e repokey --make-parent-dirs ${REPOSITORY} || echo "WARRNING: Possible repo already initialised."
		else
			printf "${COLORMSG}Password env is not set\n###############${NC}\n"
			ret 121
		fi
	fi
}

function forcepostscript() {
		printf "${COLORMSG}--------------- Postscript operations ---------------${NC}\n"
	[ "$MYSQL_DB_NAME" != "" ] && rm -rf ${MYSQL_BACKUP_TEMP_PATH}
	kill -SIGINT ${GOOFYS_PID} &&	sleep ${SLEEP4MOUNT}
}

function dbbackup() {
	if [ "$MYSQL_DB_NAME" != "" ] ; then
			printf "${COLORMSG}--------------- Mysql backup operations ---------------${NC}\n"
		mkdir -p ${MYSQL_BACKUP_TEMP_PATH}
		mysqldump -Q -u root ${MYSQL_DB_NAME}  > ${MYSQL_BACKUP_TEMP_PATH}/${MYSQL_DB_NAME}.${NOW}.sql || ret $?
		timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
			borg create -C zstd --stats --list ${REPOSITORY}::"sql.${NAMEOFBACKUP}" ${MYSQL_BACKUP_TEMP_PATH} || ret $?
		rm -rf ${MYSQL_BACKUP_TEMP_PATH}
	fi
}

function maincommand() {
		printf "${COLORMSG}--------------- Main command ---------------${NC}\n"
	timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
		borg create -C auto,zstd --stats --list ${REPOSITORY}::"${NAMEOFBACKUP}" ${DIRS}  || ret $?
}

function prunebackup() {
		printf "${COLORMSG}--------------- Prune backup ---------------${NC}\n"
	if [ "$MYSQL_DB_NAME" != "" ] ; then
		timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
			borg prune --list --stats --keep-daily ${KEEP_DAILY} --keep-weekly ${KEEP_WEEKLY} --keep-monthly ${KEEP_MONTHLY} \
			-P sql.${BACKUPNAME} ${REPOSITORY} || ret $?
	fi
	timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER \
		borg prune --list --stats --keep-daily ${KEEP_DAILY} --keep-weekly ${KEEP_WEEKLY} --keep-monthly ${KEEP_MONTHLY} \
		-P ${BACKUPNAME} ${REPOSITORY} || ret $?
}

# Started
start=`date +%s`
	printf "${COLORMSG}Started `date`${NC}\n"
	logger "${0} started with ${1} ${2}"
trap cleanup EXIT

# Call functions
prepare
borginit
testcheck
dbbackup
maincommand
prunebackup
forcepostscript || ret $?

trap - EXIT
cleanup

exit 0
