#!/bin/bash
#export LANG=ko_KR.UTF-8
#export LC_ALL=ko_KR.UTF-8

while true
do
    #date_now=$(LC_ALL=ko_KR.UTF-8 date +"현재 시간: %Y. %m. %d.  %H:%M:%S KST")
    #printf "%s\n" "$date_now"

    year=$(date +%Y)
    month=$(date +%m)
    day=$(date +%d)
    hour=$(date +%H)
    minute=$(date +%M)
    second=$(date +%S)

    printf "현재 시간: %s년 %s월 %s일 %s시 %s분 %s초\n" "$year" "$month" "$day" "$hour" "$minute" "$second"
    sleep 3
done
