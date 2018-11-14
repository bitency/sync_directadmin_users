# Migrate users between DirectAdmin servers

### Requirements

- The destination server must have SSH access (port 22) to the source server.
- Script must run from the destination server as `root`. (pull method)
- The first time when you run the script `IMPORT_USERS` must be set to `true`!

### Notes

- Script uses `/home/` as the root directory for the users homedirs.
- Script uses `/usr/local/mysql/bin/` as the installed location for MySQL.
- Script does first migrate `resellers` and then `users`.
- Script does `not` migrate the `admin` user
- Script will import the users using the destination servers main ipaddress. (Not the sources ipaddress from the backup)

### Options

- `IMPORT_USERS` is `enabled` by default. This creates a DirectAdmin user backup which does not contain e-mail data, website data and mysql data. You can disable user imports by changing `IMPORT_USERS` from `true` to `false`.
- `MULTIPLE_PHP` is `enabled` by default. If your DirectAdmin server supports multiple PHP versions on both source and destination then leave it enabled.
- `IMPORT_CRONS` is `disabled` by default. This will prevent duplicate cronjobs during testing period. You can enable cronjobs by changing `IMPORT_CRONS` from `true` to `false`.
- `SYNC_HOMEDIR` is `disabled` by default. This will rsync the users home directory. You can enable homedir sync by changing `SYNC_HOMEDIR` from `false` to `true`.
- `SYNC_DATABASES` is `disabled` by default. This will export the MySQL from the source server and import on the destination server. You can enable database imports by changing `SYNC_DATABASES` from `false` to `true`.

### Sync just one, or multiple users manually

- If you want to sync just one user, then comment out `DA_USERS="${get_da_resellers} ${get_da_users}"` and add `DA_USERS="username"` directly underneath the old da_users entry. Do not place it elsewhere in the script!
- If you want to sync multiple users manually, comment out `DA_USERS="${get_da_resellers} ${get_da_users}"` and add `DA_USERS="user1 user2 user3 user4"` directly underneath the old da_users entry. Do not place it elsewhere in the script!

### Script information

```
# This script will:
# - Check if it is run by root
# - Check if source server is filled, else quit
# - Check if SSH connection can be established, else quit
# - Check if user(s) exist when entered manually
# - Export DirectAdmin resellers / users on remote server (resellers are done first!)
# - Import DirectAdmin users on local server with main ipaddress local server (resellers are done first!)
# - Option to enable or disable cronjobs
# - Sync users home directory from remote server to local server (sync only works if local directory exists)
# - Dump databases directly from remote server on local server
# If you want to migrate/sync just one user, then set `DA_USERS` manually. You can sync/migrate multiple
# users by entering them seperated by space. Example: user1 user2 user3
```
