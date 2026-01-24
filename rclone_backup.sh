#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export TZ=Asia/Jakarta

declare -a backup_targets
declare -a backup_labels
declare remote_name
declare remote_folder
declare schedule_type
declare target_hour
declare target_minute
declare interval_hours
declare auto_delete
declare -A last_successful_remote_filename

die() { echo -e "${RED}$1${NC}"; exit 1; }

command -v rclone >/dev/null 2>&1 || die "rclone not found. Install rclone first."
command -v zip >/dev/null 2>&1 || die "zip not found. Install with: apt install -y zip"

normalize_remote_folder() {
  if [[ -z "$remote_folder" ]]; then
    remote_folder=""
    return
  fi
  remote_folder="${remote_folder#/}"
  remote_folder="${remote_folder%/}"
}

remote_path() {
  if [[ -z "$remote_folder" ]]; then
    printf "%s:" "$remote_name"
  else
    printf "%s:%s" "$remote_name" "$remote_folder"
  fi
}

resolve_path() {
  local input="$1"

  if [[ -z "$input" ]]; then
    printf "%s" "/root/"
    return 0
  fi

  if [[ "$input" == /* ]]; then
    printf "%s" "$input"
    return 0
  fi

  if [[ "$input" == *"/"* && -e "/$input" ]]; then
    printf "%s" "/$input"
    return 0
  fi

  if [[ -e "$PWD/$input" ]]; then
    printf "%s" "$PWD/$input"
    return 0
  fi

  if [[ -e "/root/$input" ]]; then
    printf "%s" "/root/$input"
    return 0
  fi

  if [[ "$input" == *"/"* ]]; then
    printf "%s" "/$input"
    return 0
  fi

  printf "%s" "/root/$input"
  return 0
}

configure_backup() {
  while true; do
    backup_targets=()
    backup_labels=()

    while true; do
      read -p "$(echo -e "${BLUE}How much data will be backed up?: ${NC}")" count
      if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then break; fi
      echo -e "${RED}=> Invalid input. Please enter a positive number.${NC}"
    done

    for (( i=1; i<=count; i++ )); do
      while true; do
        read -r -p "$(echo -e "${BLUE}Target-$i (path or name): ${NC}")" input
        target_path="$(resolve_path "$input")"
        if [[ -e "$target_path" ]]; then
          backup_targets+=("$target_path")
          backup_labels+=("$(basename "$target_path")")
          break
        else
          echo -e "${RED}=> Not found: '$target_path'. Use absolute path (starts with /) or ensure it exists.${NC}"
        fi
      done
    done

    while true; do
      read -r -p "$(echo -e "${BLUE}Rclone remote name: ${NC}")" remote_name
      [[ -n "$remote_name" ]] && break
      echo -e "${RED}=> Remote name cannot be empty.${NC}"
    done

    read -r -p "$(echo -e "${BLUE}Remote folder path (leave empty for root): ${NC}")" remote_folder
    normalize_remote_folder

    while true; do
      echo -e "${BLUE}Backup schedule:${NC}"
      echo -e "  1) Every day"
      echo -e "  2) Every hour"
      read -r -p "$(echo -e "${BLUE}Choose (1/2): ${NC}")" sched_choice
      if [[ "$sched_choice" == "1" ]]; then schedule_type="daily"; break; fi
      if [[ "$sched_choice" == "2" ]]; then schedule_type="hourly"; break; fi
      echo -e "${RED}=> Invalid choice. Please enter 1 or 2.${NC}"
    done

    if [[ "$schedule_type" == "daily" ]]; then
      echo -e "${BLUE}What time will the files be backed up (daily)?${NC}"
      while true; do
        read -r -p "$(echo -e "${BLUE}  hours (0-23): ${NC}")" target_hour
        [[ "$target_hour" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] && break
        echo -e "${RED}=> Invalid input. Please enter an hour between 0 and 23.${NC}"
      done
      while true; do
        read -r -p "$(echo -e "${BLUE}  minutes (0-59): ${NC}")" target_minute
        [[ "$target_minute" =~ ^([0-9]|[1-5][0-9])$ ]] && break
        echo -e "${RED}=> Invalid input. Please enter minutes between 0 and 59.${NC}"
      done
    else
      while true; do
        read -r -p "$(echo -e "${BLUE}How many hours per backup cycle? (1-10): ${NC}")" interval_hours
        if [[ "$interval_hours" =~ ^[0-9]+$ ]] && (( interval_hours >= 1 && interval_hours <= 10 )); then break; fi
        echo -e "${RED}=> Invalid input. Please enter a number between 1 and 10.${NC}"
      done
    fi

    while true; do
      read -r -p "$(echo -e "${BLUE}Allow auto delete old backup files? (y/n): ${NC}")" confirm_delete
      if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then auto_delete="yes"; break; fi
      if [[ "$confirm_delete" =~ ^[Nn]$ ]]; then auto_delete="no"; break; fi
      echo -e "${RED}=> Invalid input. Please enter y or n.${NC}"
    done

    echo -e "\n${YELLOW}--- Backup Configuration Summary ---${NC}"
    echo "Targets:"
    for idx in "${!backup_targets[@]}"; do
      echo "  - ${backup_targets[$idx]}"
    done
    echo "Rclone Remote: $remote_name"
    echo "Remote Folder: ${remote_folder:-/}"
    if [[ "$schedule_type" == "daily" ]]; then
      printf "Schedule: Every day at %02d:%02d\n" "$target_hour" "$target_minute"
    else
      echo "Schedule: Every ${interval_hours} hour(s)"
    fi
    echo "Auto-delete old backups: $auto_delete"
    echo -e "${YELLOW}------------------------------------${NC}"

    read -r -p "$(echo -e "${BLUE}Save data? (y/n): ${NC}")" confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && break
    echo -e "\n${YELLOW}Configuration not saved. Restarting setup...${NC}\n"
  done
}

make_zip_name() {
  local label="$1"
  if [[ "$schedule_type" == "daily" ]]; then
    printf "day-%s_backup_%s.zip" "$label" "$(date +%Y-%m-%d)"
  else
    printf "hour-%s_backup_%s.zip" "$label" "$(date +%Y-%m-%d-%H%M)"
  fi
}

zip_target() {
  local target="$1"
  local zip_path="$2"

  rm -f "$zip_path" >/dev/null 2>&1

  if [[ -d "$target" ]]; then
    local parent base
    parent="$(dirname "$target")"
    base="$(basename "$target")"
    ( cd "$parent" && zip -r -q "$zip_path" "$base" )
    return $?
  fi

  if [[ -f "$target" ]]; then
    local parent base
    parent="$(dirname "$target")"
    base="$(basename "$target")"
    ( cd "$parent" && zip -q "$zip_path" "$base" )
    return $?
  fi

  return 1
}

upload_with_retries() {
  local local_file="$1"
  local remote_dest="$2"
  local tries=3
  local n=1
  while (( n <= tries )); do
    rclone copyto "$local_file" "$remote_dest" >/dev/null 2>&1
    [[ $? -eq 0 ]] && return 0
    sleep $((n * 3))
    ((n++))
  done
  return 1
}

delete_old_backups_for_label() {
  local label="$1"
  local keep_filename="$2"
  local rpath="$3"

  local prefix
  if [[ "$schedule_type" == "daily" ]]; then
    prefix="day-${label}_backup_"
  else
    prefix="hour-${label}_backup_"
  fi

  local files
  files="$(rclone lsf "$rpath" --files-only --max-depth 1 2>/dev/null | tr -d '\r')"
  [[ -z "$files" ]] && return 0

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" == "$keep_filename" ]] && continue
    [[ "$f" == ${prefix}*.zip ]] || continue
    echo -e "${YELLOW}--> Deleting old remote backup: $f${NC}"
    rclone deletefile "${rpath}/${f}" >/dev/null 2>&1
  done <<< "$files"

  return 0
}

run_backup_cycle() {
  echo -e "${YELLOW}--- Starting new backup cycle... ---${NC}"

  local rpath
  rpath="$(remote_path)"

  for idx in "${!backup_targets[@]}"; do
    local target="${backup_targets[$idx]}"
    local label="${backup_labels[$idx]}"

    if [[ ! -e "$target" ]]; then
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${RED}SKIP: Target not found: $target${NC}"
      continue
    fi

    local zip_filename
    zip_filename="$(make_zip_name "$label")"

    local local_zip="/root/${zip_filename}"
    local remote_file="${rpath}/${zip_filename}"

    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Zipping '$label' from: $target"
    if ! zip_target "$target" "$local_zip"; then
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${RED}ZIP FAILED for '$label'.${NC}"
      rm -f "$local_zip" >/dev/null 2>&1
      continue
    fi

    if [[ ! -s "$local_zip" ]]; then
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${RED}ZIP EMPTY for '$label'.${NC}"
      rm -f "$local_zip" >/dev/null 2>&1
      continue
    fi

    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - Uploading to: ${remote_file}"
    if upload_with_retries "$local_zip" "$remote_file"; then
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${GREEN}Backup SUCCESS for '$label'.${NC}"
      last_successful_remote_filename[$label]="$zip_filename"

      if [[ "$auto_delete" == "yes" ]]; then
        delete_old_backups_for_label "$label" "$zip_filename" "$rpath"
      fi
    else
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${RED}Backup FAILED for '$label'.${NC}"
    fi

    rm -f "$local_zip" >/dev/null 2>&1
  done
}

sleep_until_next_daily_run() {
  local now_epoch target_epoch next_epoch sleep_seconds
  now_epoch=$(date +%s)
  target_epoch=$(date -d "today ${target_hour}:${target_minute}" +%s 2>/dev/null)
  if (( now_epoch >= target_epoch )); then
    next_epoch=$(date -d "tomorrow ${target_hour}:${target_minute}" +%s)
  else
    next_epoch=$target_epoch
  fi
  sleep_seconds=$((next_epoch - now_epoch))
  (( sleep_seconds < 0 )) && sleep_seconds=0
  echo -e "${YELLOW}--- Cycle complete. Next backup is scheduled for: $(date -d "@${next_epoch}") ---${NC}"
  sleep "$sleep_seconds"
}

sleep_until_next_hourly_run() {
  local sleep_seconds=$((interval_hours * 3600))
  echo -e "${YELLOW}--- Cycle complete. Next backup is scheduled in: ${interval_hours} hour(s) ---${NC}"
  sleep "$sleep_seconds"
}

configure_backup

echo -e "\n${GREEN}Configuration saved. Starting the first backup process now...${NC}"
run_backup_cycle

while true; do
  if [[ "$schedule_type" == "daily" ]]; then
    sleep_until_next_daily_run
  else
    sleep_until_next_hourly_run
  fi
  run_backup_cycle
done
