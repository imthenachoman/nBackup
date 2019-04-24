#!/bin/bash

# nBackup
# ----------------------------------------------------------------------------
# nBackup is a simple bash script for making versioned, dependency-less
# backups of your data where versions are browsable as current backups,
# snapshot-in-time folders, and running file versions.
#
# url     : https://github.com/imthenachoman/nBackup
# author  : Anchal Nigam
# e-mail  : imthenachoman@gmail.com
#
# Copyright (c) 2019 Anchal Nigam (imthenachoman@gmail.com)
# Licensed under the MIT license: http://opensource.org/licenses/MIT
# ----------------------------------------------------------------------------

###############################################################################
# FUNCTIONS
###############################################################################

function readConfigFile
{
    # first check if the config file is there
    if [[ ! -e ~/.nBackup.conf ]] ; then
        echo "ERROR: \"~/.nBackup.conf\" does not exist!" 1>&2
        echo "       Check the app installation directory for an example nBackup.conf file." 1>&2
        echo "       For example: cp \"$( cd "$(dirname "$0")" ; pwd -P )/nBackup.conf\" ~/.nBackup.conf" 1>&2
        exit 1
    fi

    # check if we can read the file
    if [[ ! -r ~/.nBackup.conf ]] ; then
        echo "ERROR: Unable to read \"~/.nBackup.conf\"!" 1>&2
        exit 1
    fi

    # make sure it has the right permissions
    if stat -c "%a" ~/.nBackup.conf | grep --quiet -v 600 ;
    then
        echo "ERROR: \"~/.nBackup.conf\" has invalid file permissions!" 1>&2
        echo "       File permissions for \"~/.nBackup.conf\" should be 600." 1>&2
        echo "       For example: chmod 600 ~/.nBackup.conf" 1>&2
        exit 1
    fi

    # make sure the file is owened by the current user
    if [[ "$(stat -c "%U:%G" ~/.nBackup.conf)" != "$(whoami):$(whoami)" ]] ; then
        echo "ERROR: \"~/.nBackup.conf\" does not have the correct file ownership!" 1>&2
        echo "       \"~/.nBackup.conf\" should be \"$(whoami):$(whoami)\"." 1>&2
        exit 1
    fi
    
    # source the config file
    # ideally sourcing files is not very secure because someone could have
    # entered dangerous code like rm -rf and sourcing the file would execute it
    # but since we've already confirmed that only the current user can modify the file
    # we'll assume everything is okay
    source ~/.nBackup.conf
    
    # make relevant folders if they don't exist
    # and make sure they are writable
    for folder in BACKUP_DESTINATION_CURRENT BACKUP_DESTINATION_COMBINED BACKUP_DESTINATION_FOLDERS LOG_DESTINATION; do
        if ! mkdir -p "${!folder}" &>/dev/null ; then
            echo "ERROR: Unable to make $folder \"${!folder}\"!" 1>&2
            exit 1
        fi
        
        if [[ ! -w "${!folder}" ]] ; then
            echo "ERROR: Unable to write to $folder \"${!folder}\"!" 1>&2
            exit 1
        fi
    done

    # make sure the include and exclude files are readable
    for file in BACKUP_INCLUDES_FILE BACKUP_EXCLUDES_FILE; do
        if [[ ! -r "${!file}" ]] ; then
            echo "ERROR: Unable to read $file \"${!file}\"!" 1>&2
            echo "       Check the app installation directory for an example file." 1>&2
            exit 1
        fi
    done

    # make sure binary options have valid values
    for option in DELETE_OLD_FOLDER_BACKUPS DELETE_OLD_COMBINED_BACKUPS; do
        if [[ "${!option}" != "1" && "${!option}" != "0" ]] ; then
            echo "ERROR: Invalid option \"${!option}\" for ${option}!" 1>&2
            echo "       Valid options are: \"1\" or \"0\"." 1>&2
            exit 1
        fi
    done

    # make sure count options are valid integers
    for option in KEEP_OLD_FOLDER_BACKUPS_COUNT KEEP_OLD_COMBINED_BACKUPS_COUNT; do
        if ! [[ "${!option}" =~ ^[0-9]+$ ]] ; then
            echo "ERROR: Invalid integer \"${!option}\" for ${option}!" 1>&2
            echo "       Please enter a valid integer." 1>&2
            exit 1
        fi
    done

    # make sure age options are valid
    for option in KEEP_OLD_FOLDER_BACKUPS_AGE KEEP_OLD_COMBINED_BACKUPS_AGE; do
        if ! [[ "${!option}" =~ ^[0-9]+\ (second|minute|hour|day|week|month|year)s? ]] ; then
            echo "ERROR: Invalid age \"${!option}\" for ${option}!" 1>&2
            echo "       Valid ages are: # second/minute/hour/day/week/month/year(s)." 1>&2        
            exit 1
        fi
        
        # to do
        # check if age actually works as a valid option for date -d ...
    done

    # make sure criteria options are valid
    for option in KEEP_OLD_FOLDER_BACKUPS_CRITERIA KEEP_OLD_COMBINED_BACKUPS_CRITERIA; do
        if [[ "${!option}" != "and" && "${!option}" != "or" ]] ; then
            echo "ERROR: Invalid criteria \"${!option}\" for ${option}!" 1>&2
            echo "       Valid options are: \"and\" or \"or\"." 1>&2        
            exit 1
        fi
    done
}

# pretty date/time difference of two dates/times represented as seconds
# dateDiff startDateTimeInSeconds startDateTimeNanoSconds endDateTimeInSeconds
# $1 = start date/time seconds since epoch
# $2 = start date/time nanoseconds
# $3 = end date/time seconds since epoch
# $4 = end date/time nanoseconds
function dateDiff
{
    local differenceInSeconds=$(expr $3 - $1)
    local days=$((differenceInSeconds/60/60/24))
    local hours=$((differenceInSeconds/60/60%24))
    local minutes=$((differenceInSeconds/60%60))
    local seconds=$((differenceInSeconds%60))
    local nanoseconds=$(echo $(expr $4 - $2) | tr -d -)
    
    printf "%2d days, %2d hours, %2d minutes, %2d seconds, %d nanoseconds" $days $hours $minutes $seconds $nanoseconds
}

# filter a list of files/folders that should be deleted; read from stdin
# $1 = criteria: and/or
# $2 = keepcount
# $3 = minage
function filterFilesToDelete
{
    # counter to keep track of the # of rows read
    count=1
    # reverse sort the data
    # exclude the top one since its the latest backup
    # then process each line
    sort -r - | tail -n +2 | while read line ; do
        # find the archive date
        archive_date=${line##*[./]}
        
        # for 'and' we want to:
        #   check if the row is greater than the keep count
        #   and
        #   check if the archive date is less than the min age
        if [[ "$1" = "and" && "$count" -gt "$2" && "$archive_date" < "$3" ]] ; then
            echo "$line"
        
        # for 'or' we want to:
        #   check if the row is greater than the keep count
        #   or
        #   check if the archive date is less than the min age
        elif [[ $1 = "or" && ( "$count" -gt "$2" || "$archive_date" < "$3" ) ]] ; then
            echo "$line"
        fi
        
        count=$[count + 1]
    done
}

function doCurrentBackup
{
    local sectionName="1. backup current"
    local sectionLog="1_backup_current"
    local start_time=$(date +"%s %N")
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "destination => $BACKUP_DESTINATION_CURRENT"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "this could take a while depending on the number of files"
    
    # rsync the files
    rsync --archive --delete --recursive -xx --relative --stats --out-format="%t | %5o | %15l | %f" --files-from="$BACKUP_INCLUDES_FILE" --exclude-from="$BACKUP_EXCLUDES_FILE" / "$BACKUP_DESTINATION_CURRENT" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log" 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    
    # get rsync stats
    rsync_stats=$(tail -50 "$LOG_DESTINATION_NOW/${sectionLog}.out.log" | egrep -A 50 "^Number of files: ")
    
    # get the number of files that were created or deleted
    num_files_created=$([[ $rsync_stats =~ $(echo "Number of created files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_deleted=$([[ $rsync_stats =~ $(echo "Number of deleted files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_transferred=$([[ $rsync_stats =~ $(echo "Number of regular files transferred: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    
    # was anything actually synced
    if [[ "$num_files_created" -ne 0 || "$num_files_deleted" -ne 0 || "$num_files_transferred" -ne 0 ]] ; then
        # print stats
        echo "$rsync_stats" | while read line ; do
            if [[ "$line" != "" ]] ; then
                printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "1. backup current" "stats" "$line"
            fi
        done
        return 0
    else
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "no changes; nothing backed up"
        return 1
    fi
}

function doFolderBackup
{
    local sectionName="2. backup folder"
    local sectionLog="2_backup_folder"
    local start_time=$(date +"%s %N")
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "destination => $BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE"
    
    cp -alv "${BACKUP_DESTINATION_CURRENT}" "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log" 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "linked $(find "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE" -type f | wc -l) files"
}

function doCombinedBackup
{
    local sectionName="3. backup combined"
    local sectionLog="3_backup_combined"
    local start_time=$(date +"%s %N")

    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "destination => $BACKUP_DESTINATION_COMBINED"
    
    # make a combined viewd
    #  - find all files with 2 links
    #    - one link is to the file in the $BACKUP_DESTINATION/current
    #    - the other link is to the file in $BACKUP_DESTINATION/$ARCHIVE_DATE
    # - there should never be any files with only 1 hard link since the previous command
    #   is sure to have created a second link
    # - any files with more than 2 links were, hopefully, already covered during a previous iteration
    cd "${BACKUP_DESTINATION_CURRENT}" && find * -type f -links 2 -print0 | while IFS= read -r -d $'\0' filePath ; do
        # get the name of the file
        fileName="$(basename "$filePath")"
        
        # get the folder it is in
        fileFolder="$(dirname "$filePath")"

        # where the file will live in the combined folder
        # need to mirror the folder structure
        destinationFolder="$BACKUP_DESTINATION_COMBINED/$fileFolder"
        if [[ ! -d "$destinationFolder" ]] ; then
            mkdir -pv "$destinationFolder" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log" 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
        fi

        # make a hard link to it
        cp -alv "${BACKUP_DESTINATION_CURRENT}/$filePath" "$destinationFolder/$fileName.$ARCHIVE_DATE" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log" 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
    done
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "linked $(find "$BACKUP_DESTINATION_COMBINED" -type f -name "*.$ARCHIVE_DATE" | wc -l) files"
}

function deleteOldFolderBackups
{
    local sectionName="4. delete folders"
    local sectionLog="4_delete_folders"
    local start_time=$(date +"%s %N")
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "keep count => $KEEP_OLD_FOLDER_BACKUPS_COUNT"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "minimum age => $KEEP_OLD_FOLDER_BACKUPS_AGE => $(date -d "-$KEEP_OLD_FOLDER_BACKUPS_AGE" +"$ARCHIVE_DATE_FORMAT")"
    
    # find all direct sub-folders in BACKUP_DESTINATION_FOLDERS
    # exclude BACKUP_DESTINATION_CURRENT, BACKUP_DESTINATION_COMBINED, and LOG_DESTINATION
    # filter based on config criteria
    find "$BACKUP_DESTINATION_FOLDERS" -mindepth 1 -maxdepth 1 \( -path "$BACKUP_DESTINATION_CURRENT" -o -path "$BACKUP_DESTINATION_COMBINED" -o -path "$LOG_DESTINATION" \) -prune -o -type d | filterFilesToDelete "$KEEP_OLD_FOLDER_BACKUPS_CRITERIA" "$KEEP_OLD_FOLDER_BACKUPS_COUNT" "$(date -d "-$KEEP_OLD_FOLDER_BACKUPS_AGE" +"$ARCHIVE_DATE_FORMAT")" | while read folder ; do
        # delete the folder
        rm -rf "$folder" 1>>/dev/null 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
        
        # log output if it was deleted
        if [[ ! -d "$folder" ]] ; then
            echo "removed: $folder" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log"
        fi
    done
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    
    if [[ -e "$LOG_DESTINATION_NOW/${sectionLog}.out.log" ]] ; then
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "deleted $(cat "$LOG_DESTINATION_NOW/${sectionLog}.out.log" | wc -l) old backup folders"
    else
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "deleted 0 old backup folders"
    fi
}

function deleteOldCombinedBackups
{
    local sectionName="5. delete combined"
    local sectionLog="5_delete_combined"
    local start_time=$(date +"%s %N")
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "keep count => $KEEP_OLD_COMBINED_BACKUPS_COUNT"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "info" "minimum age => $KEEP_OLD_COMBINED_BACKUPS_AGE => $(date -d "-$KEEP_OLD_COMBINED_BACKUPS_AGE" +"$ARCHIVE_DATE_FORMAT")"
    
    # find all folders in BACKUP_DESTINATION_COMBINED
    find "$BACKUP_DESTINATION_COMBINED" -type d | while read folder ; do
        # for each folder
        # find direct files
        # remove the file's extension (archive date/time stamp)
        # sort and unique the list
        # and go through each unique base file
        cd "$folder" && find . -maxdepth 1 -type f -exec bash -c 'printf "%s\n" "${@%.*}"' _ {} + | sort -u | while read file ; do
            # find all the backups for the base file
            # filter based on config criteria
            ls "$file".* | filterFilesToDelete "$KEEP_OLD_COMBINED_BACKUPS_CRITERIA" "$KEEP_OLD_COMBINED_BACKUPS_COUNT" "$(date -d "-$KEEP_OLD_COMBINED_BACKUPS_AGE" +"$ARCHIVE_DATE_FORMAT")" | while read line ; do
                # delete the file
                rm -rfv "$line" 1>>"$LOG_DESTINATION_NOW/${sectionLog}.out.log" 2>>"$LOG_DESTINATION_NOW/${sectionLog}.err.log"
            done
        done    
    done
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    
    
    if [[ -e "$LOG_DESTINATION_NOW/${sectionLog}.out.log" ]] ; then
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "deleted $(cat "$LOG_DESTINATION_NOW/${sectionLog}.out.log" | wc -l) old backup files"
    else
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "stats" "deleted 0 old backup files"
    fi
}

function doIt
{
    local sectionName="0. nBackup"
    local start_time=$(date +"%s %N")
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "starting" "$(date)"
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "log path" "$LOG_DESTINATION_NOW"
    
    cat ~/.nBackup.conf | egrep -v '^#|^$' | while read line ; do
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "configuration" "$line"
    done
    
    # do the backup
    if doCurrentBackup ; then
        # and if something was backed up then make folder and combined views
        doFolderBackup
        doCombinedBackup
    fi
    
    # delete old backups?
    [[ "$DELETE_OLD_FOLDER_BACKUPS" = "1" ]] && deleteOldFolderBackups
    [[ "$DELETE_OLD_COMBINED_BACKUPS" = "1" ]] && deleteOldCombinedBackups
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "finished" "$(date)"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "duration" "$(dateDiff $start_time $(date +"%s %N"))"
    
    # print all the log files
    ls "$LOG_DESTINATION_NOW/"*.log | while read line ; do
        # if the file file is not empty then print it
        if [[ -s "$line" ]] ; then
            printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "log file" "$line => $(cat "$line" | wc -l) lines"
        
        # else delete it
        else
            rm -rf "$line"
        fi
    done
    
    # alert if there were there any error files
    if ls "$LOG_DESTINATION_NOW"/*.err.log 1>/dev/null 2>&1 ; then
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "$sectionName" "!!! ERROR !!!" "there were errors. check the log files for details"
    fi
}

function sendEmail
{
    # get rsync stats
    rsync_stats=$(tail -50 "$LOG_DESTINATION_NOW/1_backup_current.out.log" | egrep -A 50 "^Number of files: ")

    # get the number of files that were created or deleted
    num_files_created=$([[ $rsync_stats =~ $(echo "Number of created files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_deleted=$([[ $rsync_stats =~ $(echo "Number of deleted files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_transferred=$([[ $rsync_stats =~ $(echo "Number of regular files transferred: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    errors=$(ls "$LOG_DESTINATION_NOW"/*.err.log 1>/dev/null 2>&1 && echo "ERRORS - " || echo "")
    
    cat "$LOG_DESTINATION_NOW/0_nBackup.log" | mail -s "${errors}$(hostname) backup report - $ARCHIVE_DATE (created: $num_files_created / deleted: $num_files_deleted / files transferred: $num_files_transferred)" "$EMAIL_ADDRESS"
}

###############################################################################
# MAIN
###############################################################################

readConfigFile

NOW=$(date +"$ARCHIVE_DATE_FORMAT")
ARCHIVE_DATE=$(date +"$ARCHIVE_DATE_FORMAT")
LOG_OUTPUT_FORMAT="%s | %-20s | %-15s | %s\n"
LOG_DESTINATION_NOW="$LOG_DESTINATION/$NOW"

if [[ -d "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE" || -d "$LOG_DESTINATION_NOW" || -e "$LOG_DESTINATION_NOW/0_nBackup.log" ]] ; then
        echo "ERROR: A backup for ARCHIVE_DATE=$ARCHIVE_DATE already exists!" 1>&2
        exit 1
fi

# make date folder for logs
mkdir -p "$LOG_DESTINATION_NOW"

# start it and log everything
doIt | tee "$LOG_DESTINATION_NOW/0_nBackup.log"

sendEmail