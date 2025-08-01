#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export TZ=Asia/Jakarta
declare -a backup_targets
declare remote_name
declare remote_folder
declare target_hour
declare target_minute
declare auto_delete
declare -A last_successful_remote_filename

configure_backup() {
    while true; do
        backup_targets=()

        while true; do
            read -p "$(echo -e "${BLUE}How much data will be backed up?: ${NC}")" count
            if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
                break
            else
                echo -e "${RED}=> Invalid input. Please enter a positive number.${NC}"
            fi
        done

        for (( i=1; i<=count; i++ )); do
            while true; do
                read -p "$(echo -e "${BLUE}File-$i: ${NC}")" dir_input
                if [[ "$dir_input" == /* ]]; then
                    target_path="$dir_input"
                else
                    target_path="/root/$dir_input"
                fi
                
                if [ -d "$target_path" ]; then
                    backup_targets+=("$target_path")
                    break
                else
                    echo -e "${RED}=> Error: Directory '$target_path' not found. Please try again.${NC}"
                fi
            done
        done

        read -p "$(echo -e "${BLUE}Name of remote rclone: ${NC}")" remote_name
        read -p "$(echo -e "${BLUE}Name of folder connected to remote: ${NC}")" remote_folder

        echo -e "${BLUE}What time will the files be backed up?${NC}"
        while true; do
            read -p "$(echo -e "${BLUE}  hours (0-23): ${NC}")" target_hour
            if [[ "$target_hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
                break
            else
                echo -e "${RED}=> Invalid input. Please enter an hour between 0 and 23.${NC}"
            fi
        done
        
        while true; do
            read -p "$(echo -e "${BLUE}  minutes (0-59): ${NC}")" target_minute
            if [[ "$target_minute" =~ ^([0-9]|[1-5][0-9])$ ]]; then
                break
            else
                echo -e "${RED}=> Invalid input. Please enter minutes between 0 and 59.${NC}"
            fi
        done

        while true; do
            read -p "$(echo -e "${BLUE}Allow auto delete old backup files? (y/n) ${NC}")" confirm_delete
            if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
                auto_delete="yes"
                break
            elif [[ "$confirm_delete" =~ ^[Nn]$ ]]; then
                auto_delete="no"
                break
            else
                echo -e "${RED}=> Invalid input. Please enter y or n.${NC}"
            fi
        done

        formatted_minute=$(printf "%02d" $target_minute)
        echo -e "\n${YELLOW}--- Backup Configuration Summary ---${NC}"
        echo "Files to be backed up:"
        for item in "${backup_targets[@]}"; do
            echo "  - $item"
        done
        echo "Rclone Remote: $remote_name"
        echo "Remote Folder: $remote_folder"
        echo "Daily Backup Time: Around ${target_hour}:${formatted_minute}"
        echo "Auto-delete old backups: $auto_delete"
        echo -e "${YELLOW}------------------------------------${NC}"

        read -p "$(echo -e "${BLUE}Save data? (y/n) ${NC}")" confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        else
            echo -e "\n${YELLOW}Configuration not saved. Restarting setup...${NC}\n"
        fi
    done
}

run_backup_cycle() {
    echo -e "${YELLOW}--- Starting new backup cycle... ---${NC}"
    for target in "${backup_targets[@]}"; do
        file_basename=$(basename "$target")
        timestamp=$(date +%Y%m%d%H%M%S)
        
        new_local_zip="/root/${file_basename}_backup_${timestamp}.zip"
        new_remote_filename="${file_basename}_backup_${timestamp}.zip"
        old_remote_filename=${last_successful_remote_filename[$file_basename]}

        echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Creating local zip for '$file_basename'..."
        zip -r "$new_local_zip" "$target" > /dev/null 2>&1
        
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Uploading to remote..."
        rclone copy "$new_local_zip" "$remote_name:$remote_folder/" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${GREEN}The backup process for the '$file_basename' file was successful.${NC}"
            last_successful_remote_filename[$file_basename]=$new_remote_filename
            
            if [[ "$auto_delete" == "yes" && -n "$old_remote_filename" ]]; then
                echo -e "${YELLOW}--> Deleting old remote backup: $old_remote_filename${NC}"
                rclone delete "$remote_name:$remote_folder/$old_remote_filename" > /dev/null 2>&1
            fi
        else
            echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${RED}The backup process for the '$file_basename' file FAILED.${NC}"
        fi
        
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Deleting local zip file: $new_local_zip"
        rm "$new_local_zip"
    done
}

configure_backup

echo -e "\n${GREEN}Configuration saved. Starting the first backup process now...${NC}"

run_backup_cycle

SCHEDULING_THRESHOLD_SECONDS=1800

while true; do
    current_epoch=$(date +%s)
    target_today_epoch=$(date -d "today ${target_hour}:${target_minute}" +%s)

    if (( current_epoch > target_today_epoch )); then
        next_run_epoch=$(date -d "tomorrow ${target_hour}:${target_minute}" +%s)
    else
        next_run_epoch=$target_today_epoch
    fi

    sleep_duration=$((next_run_epoch - current_epoch))
    if (( sleep_duration < 0 )); then
        sleep_duration=0
    fi
    
    next_run_human=$(date -d "@${next_run_epoch}")

    echo -e "${YELLOW}--- Cycle complete. Next backup is scheduled for: $next_run_human ---${NC}"
    sleep "$sleep_duration"
    
    run_backup_cycle
done