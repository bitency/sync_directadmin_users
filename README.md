# Migrate users between DirectAdmin servers

### Requirements

- The destination server must have SSH access (port 22) to the source server.
- The destination must have passwordless (SSH key) `root` access to the source server.
- Script must run from the destination server as `root`. (pull method)

### Notes

- Script uses `/home/` as the root directory for the users homedirs.
- Script uses `/usr/local/mysql/bin/` as the installed location for MySQL.
- Script uses `service directadmin restart` to restart DirectAdmin. Change it to `/etc/init.d/directadmin restart` if you don't use systemd.
- Script does first migrate resellers and then users.
- Script does not migrate the admin user
- Script will import the users using the destination servers main ipaddress.

### Options

- Cronjobs are `disabled` by default. This will prevent duplicate cronjobs during testing period. You can enable cronjobs by changing `disable_crons` from `true` to `false`.
- DirectAdmin user backups are `enabled` by default. This backup does not contain e-mail data, website data and mysql data. You can disable DirectAdmin backups by changing `directadmin_backups` from `true` to `false`.
- File backups are `enabled` by default. This will rsync the users home directory. You can disable file sync by changing `file_backups` from `true` to `false`.
- Database backups are `enabled` by default. This will export the MySQL from the source server and import on the destination server. You can disable database backups by changing `database_backups` from `true` to `false`.

### Sync just one, or multiple users manually

- If you want to sync just one user, then comment out `da_users="${get_da_resellers}${get_da_users}"` and add `da_users="username"` directly underneath the old da_users entry. Do not place it elsewhere in the script!
- If you want to sync multiple users manually, comment out `da_users="${get_da_resellers}${get_da_users}"` and add `da_users="user1 user2 user3 user4"` directly underneath the old da_users entry. Do not place it elsewhere in the script!
