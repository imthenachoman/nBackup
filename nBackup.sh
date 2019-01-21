#!/bin/bash

# first check if the config file is there
if [[ ! -e ~/.nBackup.conf ]] ; then
    echo "ERROR: ~/.nBackup.conf does not exist!" 2>/dev/null
    echo "       Check the app installation directory for an example .nBackup.conf file." 2>/dev/null
    echo "       Copy it to ~/.nBackup.conf and update with appropriate values." 2>/dev/null
    exit 1
fi

# check if we can read the file
if [[ ! -r ~/.nBackup.conf ]] ; then
    echo "ERROR: Unable to read ~/.nBackup.conf!" 2>/dev/null
    exit 1
fi

# make sure it has the right permissions
if stat -c "%a" ~/.nBackup.conf | grep --quiet -v 600 ;
then
    echo "ERROR: ~/.nBackup.conf has invalid permissions." 2>/dev/null
    echo "       ~/.nBackup.conf should be 600" 2>/dev/null
    exit 1
fi

# make sure the file is owened by the current user
if [[ "$(stat -c "%U:%G" ~/.nBackup.conf)" != "$(whoami):$(whoami)" ]] ; then
    echo "ERROR: ~/.nBackup.conf does not have the correct file ownership." 2>/dev/null
    echo "       ~/.nBackup.conf should be $(whoami):$(whoami)" 2>/dev/null
    exit 1
fi

# source the config file
# ideally sourcing files is not very secure because someone could have
# entered dangerous code like rm -rf and sourcing the file would execute it
# but since we've already confirmed that only the current user can modify the file
# we'll assume everything is okay

source ~/.nBackup.conf

# make relevant folders if they don't exist
# and make sure they are writeable
for folder in BACKUP_DESTINATION_CURRENT BACKUP_DESTINATION_COMBINED BACKUP_DESTINATION_FOLDERS LOG_DESTINATION; do
    if ! mkdir -p "${!folder}" &>/dev/null ; then
        echo "ERROR: Unable to make $folder \"${!folder}\"" 2>/dev/null
        exit 1
    fi
    
    if [[ ! -w "${!folder}" ]] ; then
        echo "ERROR: Unable to write to $folder \"${!folder}\"" 2>/dev/null
        exit 1
    fi
done

# make sure the folders to be backed up are readable
for folder in "${BACKUP_PATHS[@]}" ; do
    if [[ ! -r "$folder" ]] ; then
        echo "ERROR: Unable to read source folder \"$folder\"" 2>/dev/null
        exit 1
    fi
done

NOW=$(date +"$ARCHIVE_DATE_FORMAT")
ARCHIVE_DATE=$(date +"$ARCHIVE_DATE_FORMAT")
LOG_OUTPUT_FORMAT="%s | %-15s | %-15s | %s\n"

function dateDiff
{
    local differenceInSeconds=$(expr $2 - $1)
    local days=$((differenceInSeconds/60/60/24))
    local hours=$((differenceInSeconds/60/60%24))
    local minutes=$((differenceInSeconds/60%60))
    local seconds=$((differenceInSeconds%60))
    
    (( $days > 0 )) && printf '%d days ' $days
    (( $hours > 0 )) && printf '%d hours ' $hours
    (( $minutes > 0 )) && printf '%d minutes ' $minutes
    (( $days > 0 || $hours > 0 || $minutes > 0 )) && printf 'and '
    printf '%d seconds\n' $seconds
}

function doIt
{
    starting_main=$(date +"%s")
    starting_section=$starting_main
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "nBackup" "starting" "starting"
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "rsync" "starting" "this could take a while depending on the number of files"
    
    # rsync the files and 
    rsync -a --delete --stats --out-format="%t | %5o | %15l | %f" "${BACKUP_PATHS[@]}" "${BACKUP_DESTINATION_CURRENT}" &> "$LOG_DESTINATION/rsync.log"
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "rsync" "finished" "$(dateDiff $starting_section $(date +"%s"))"
    
    # get rsync stats
    rsync_stats=$(tail -50 "$LOG_DESTINATION/rsync.log" | egrep -A 50 "^Number of files: ")
    
    # print stats
    echo "$rsync_stats" | while read line ; do
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "rsync" "stats" "$line"
    done
    
    # were there any errors?
    if echo "$rsync_stats" | grep -q "rsync error: " ; then
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "rsync" "ERROR" "there were errors duing rsync; check the logs for details"
    fi
    
    # get the number of files that were created or deleted
    num_files_created=$([[ $rsync_stats =~ $(echo "Number of created files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_deleted=$([[ $rsync_stats =~ $(echo "Number of deleted files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    num_files_transferred=$([[ $rsync_stats =~ $(echo "Number of regular files transferred: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
    
    # we only need to make a snapshot if files were deleted or created
    if [[ "$num_files_created" -ne 0 || "$num_files_deleted" -ne 0 || "$num_files_transferred" -ne 0 ]] ; then
        # make a date folder backup using hard links
        starting_section=$(date +"%s")
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "folder archive" "starting" "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE"
        cp -avl "${BACKUP_DESTINATION_CURRENT}" "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE" &> "$LOG_DESTINATION/folder.log"
        
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "folder archive" "finished" "$(dateDiff $starting_section $(date +"%s"))"
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "folder archiev" "stats" "linked $(find "$BACKUP_DESTINATION_FOLDERS/$ARCHIVE_DATE" -type f | wc -l) files"
        
        # make a combined view
        #  - find all files with 2 links
        #    - one link is to the file in the $BACKUP_DESTINATION/current
        #    - the other link is to the file in $BACKUP_DESTINATION/$ARCHIVE_DATE
        # - there should never be any files with only 1 hard link since the previous command
        #   is sure to have created a second link
        # - any files with more than 2 links were, hopefully, already covered during a previous iteration
        starting_section=$(date +"%s")
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "combined backup" "starting" "starting"
        cd "${BACKUP_DESTINATION_CURRENT}" && find * -type f -links 2 -print0 | while IFS= read -r -d $'\0' filePath ; do
            # get the name of the file
            fileName="$(basename "$filePath")"
            
            # get the folder it is in
            fileFolder="$(dirname "$filePath")"

            # where the file will live in the combined folder
            # need to mirror the folder structure
            destinationFolder="$BACKUP_DESTINATION_COMBINED/$fileFolder"
            if [[ ! -d "$destinationFolder" ]] ; then
                echo "'${BACKUP_DESTINATION_CURRENT}/$fileFolder' -> '$destinationFolder'" >> "$LOG_DESTINATION/combined.log"
                mkdir -p "$destinationFolder"
            fi

            # make a hard link to it
            cp -alv "${BACKUP_DESTINATION_CURRENT}/$filePath" "$destinationFolder/$fileName.$ARCHIVE_DATE" &>> "$LOG_DESTINATION/combined.log"
        done
        
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "combined backup" "finished" "$(dateDiff $starting_section $(date +"%s"))"
        
        printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "combined backup" "stats" "linked $(find "$BACKUP_DESTINATION_COMBINED" -type f -name "*.$ARCHIVE_DATE" | wc -l) files"
    fi
    
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "nBackup" "finished" "$(dateDiff $starting_main $(date +"%s"))"
    
    # print log location
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "log path" "nBackup" "$LOG_DESTINATION/nBackup.log"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "log path" "rsync" "$LOG_DESTINATION/rsync.log"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "log path" "folder archive" "$LOG_DESTINATION/folder.log"
    printf "$LOG_OUTPUT_FORMAT" "$(date +"$LOG_TIME_FORMAT")" "log path" "combined backup" "$LOG_DESTINATION/combined.log"
}

# make date folder for logs
LOG_DESTINATION="$LOG_DESTINATION/$NOW"
mkdir -p "$LOG_DESTINATION"

doIt | tee "$LOG_DESTINATION/nBackup.log"

rsync_stats=$(tail -50 "$LOG_DESTINATION/rsync.log" | egrep -A 50 "^Number of files: ")

# get the number of files that were created or deleted
num_files_created=$([[ $rsync_stats =~ $(echo "Number of created files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
num_files_deleted=$([[ $rsync_stats =~ $(echo "Number of deleted files: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
num_files_transferred=$([[ $rsync_stats =~ $(echo "Number of regular files transferred: ([0-9,]+)") ]] && echo "${BASH_REMATCH[1]}" | sed 's/,//')
errors=$(echo "$rsync_stats" | grep -q "rsync error: " && echo " - WITH ERRORS" || echo "")

cat "$LOG_DESTINATION/nBackup.log" | mail -s "$(hostname) backup report - $ARCHIVE_DATE (created: $num_files_created / deleted: $num_files_deleted / files: $num_files_transferred)$errors" "$EMAIL_ADDRESS"

