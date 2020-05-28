#!/bin/bash
GITLABADDRESS=gitlab.example.com
PROJECTID=3
TOKEN=xxxxxxxxx
BRANCH=master
TIMEZONE=Europe/Moscow
API_VERSION=v4
DESCRIPTION="Weekly backup"
ACTIVE=true
CRON="0 1 * * 7"

curl --request POST --header "PRIVATE-TOKEN: $TOKEN" \
 --form description="$DESCRIPTION" --form ref="$BRANCH" \
 --form cron="$CRON" --form cron_timezone="$TIMEZONE" \
 --form active="$ACTIVE" "https://$GITLABADDRESS/api/$API_VERSION/projects/$PROJECTID/pipeline_schedules"
