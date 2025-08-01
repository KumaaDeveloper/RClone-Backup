## General
`RClone-Backup` is a simple shell script that allows you to back up multiple files to Google Drive at a specified time.

## Features
- Can be many files
- Can set the backup time
- Can repeat backup settings
- Automatic backup and deletion of old files
- You need install rclone and gdrive
  
## How To Run The Script?

If you have already installed rclone and configured it, then you can install this script.
1. Install script on your server
```html
wget https://raw.githubusercontent.com/KumaaDeveloper/RClone-Backup/main/rclone_backup.sh
```
2. Run the autobackup script
```html
./rclone_backup.sh
```
3. If access is denied, grant permission.
```html
chmod +x ./rclone_backup.sh &&
./rclone_backup.sh
```
4. Input all data requested by the script, and once completed, your files will be continuously and automatically backed up.
