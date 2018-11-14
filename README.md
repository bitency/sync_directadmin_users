# Migrate users between DirectAdmin servers

### Requirements

- The destination server must have SSH access (port 22) to the source server.
- Script must run from the destination server as `root`. (pull method)
- The first time when you run the script `IMPORT_USERS` must be set to `true`!

### Notes

- Script uses `/home/` as the root directory for the users homedirs.
- Script uses `/usr/local/mysql/bin/` as the installed location for MySQL.
- Script does first migrate `resellers` and then `users`.
- Script does **not** migrate the `admin` user
- Script will import the users using the destination servers main ipaddress. (Not the sources ipaddress from the backup)

### Options

- `IMPORT_USERS` is **enabled** by default. This creates a DirectAdmin user backup which does not contain e-mail data, website data and mysql data. You can disable user imports by changing `IMPORT_USERS` from `true` to `false`. (Must be `true` on first run!)
- `MULTIPLE_PHP` is **disabled** by default. If your DirectAdmin server supports multiple PHP versions on both source and destination then set it to `true`.
- `IMPORT_CRONS` is **disabled** by default. This will prevent duplicate cronjobs during testing period. You can enable cronjobs by setting it to `true`.
- `SYNC_HOMEDIR` is **disabled** by default. This will rsync the users home directory. You can enable homedir sync by setting it to `true`.
- `SYNC_DATABASES` is **disabled** by default. This will export the MySQL from the source server and import on the destination server. You can enable database imports by setting it to `true`.

### Script information

```
# This script will:
# - Check if it is run by root
# - Check if `SOURCE` variable is filled, else quit
# - Check if SSH connection can be established, else quit
# - Check if user(s) exist when entered manually
# - Check if local and remote MySQL connection can be established
# - Export DirectAdmin resellers / users on remote server (resellers are done first!)
# - Import DirectAdmin users on local server with main ipaddress local server (resellers are done first!)
# - Import cronjobs if needed
# - Sync users home directory from remote server to local server (sync only works if local directory exists)
# - Sync users home diretory uses `--delete`!
# - Import databases directly from remote server on local server
# - Option to import all reseller(s)/user(s) or manually entered reseller(s)/user(s)
```
