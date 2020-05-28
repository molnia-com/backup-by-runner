# Templates for scheduling script on remote. For backuping by borg and scaning by clamscan.

This script save logs only if some error. In normal situation it works silently.
There are two error handlers: by exit status and parse log for the key word.
Script print self messages colored. It useful in big and verbose log of executable applications. Only some of tail strings (default 50) you can see in gitlab logs, all log you can get in `artifacts.zip`.  

Script works on bash and by CI/CD GitLab. Runner on shell or ssh executors.
In syslog messages you can see start and stop time on runner's machine.
Script check for other instance with same name.


# How to use

* You can use script manually by crontab, but main use case by gitlab-runner. So you should [install dedicated gitlab-runner](https://docs.gitlab.com/runner/install/) on backup machine.

* Configure it for shell or ssh executor. Like:
```
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.example.com/" \
  --registration-token "PROJECT_REGISTRATION_TOKEN" \
  --executor "shell" \
  --shell "bash" \
  --description "runner1.example.com \
  --tag-list "backup,bigfiles,runner1,node1" \
  --locked="false" \
  --access-level="not_protected"
```

* Clone this repo into you own repository on gitlab.
* Tune up timeout on CI/CD settings. For example - 1d.
* Change `scheduler.sh` for you gitlab and execute for scheduling. Use crontab notation for time of backup.
`PROJECTID` is internal ID of gitlab, you can find it on the main page of you repository.
* Change `.gitlab-ci.yml` and example backup script for own.
* If you use borg, install it by [pip 'borgbackup[fuse]'](https://borgbackup.readthedocs.io/en/stable/installation.html#pip-installation)

## Environment

`VERBOSE=1`
For stdout immediately.

`SAVELOGSONSUCCES=1`
For save log to artifacts on successful execution.

### Timeout
You can set timeout of execution by set environment variable `TIMEOUT` or change default timeout.
Default value is seconds. You can set it as 'm', 'h' or 'd' at the end.

## Variables
* `ERROR_STRING` - string for the check in log for error.
* `EXTRACT_ERROR_STRING` - expression for show string if error.
* `KILL_TIMEOUT_SIGNAL` - signal for killing if timeout.
* `TAIL` - how many strings with errors on screen.
* `COLORMSG` - color of mesage (default yellow).

## Description of functions
### Main functions
* `prepare`
* `testcheck`
* `maincommand`
* `forcepostscript`

### Service functions
* `cleanup` - cleanup log file
* `checklog` - log parser for error word
* `ret` - exit handler
* `checktimeout` - check only timeout exception

All functions can be used as you want. You can add, remove or change them.
But take in mind, `forcepostscript` will execute on error and no error at the end.

Handlers can be used on function exit or inside near any command.
_Examples:_

Check exit code of the command:
```bash
function main() {
		false || ret $?
}
```

Check only timeout and ignore other errors:
```bash
function main() {
		timeout -s $KILL_TIMEOUT_SIGNAL -k 1 $TIMEOUT_OPER sleep 1000 || checktimeout $?
}
```

Check key word and ignore exit code:
```bash
function main() {
		echo fail
		ERROR_STRING=fail
		checklog
}
```

Check key word and exit code:
```bash
function main() {
		echo fail || ret $?
		ERROR_STRING=fail
		checklog
}
```

Check status of last command in function:
```bash
function main() {
    true
		false
}

main || ret $?
```

## Examples
* `citest.sh` script-template for automation.
* `clamscan.sh` - script for automation virus scanning.
* `borg2S3.sh` - script for borg backuping with S3 mount.

## borg2S3

First you need init borg repository
Something like:
`borg init -e repokey --make-parent-dirs /mnt/goofys/borg1/`

See [borg docs](https://borgbackup.readthedocs.io/en/stable/)

### Credentials

You have to put aws credentials in `~/.aws/`
And put password for borg backup in `~/.borg-passphrase`

### Borg password command

Useful variable in borg `BORG_PASSCOMMAND` - it can execute something for getting password. If you use credential storage like hashicorp vault - get it by `export BORG_PASSCOMMAND="vault kv get secret/borg/backup/password"`.
