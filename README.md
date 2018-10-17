# Migrate users between DirectAdmin servers

### Requirements

- The destination server must have SSH access (port 22) to the source server.
- The destination must have passwordless (SSH key) `root` access to the source server.
- Script must run from the destination server as `root`.

### Notes

- Script uses `/home/` as the root directory for the users homedirs.
- Script uses `/usr/local/mysql/bin/` as the installed location for MySQL.
- Script uses `service directadmin restart` to restart DirectAdmin. Change it to `/etc/init.d/directadmin restart` if you don't use systemd.
- Script does first migrate resellers and then users.
- Script does not migrate the admin user
- Script will import the users using the destination servers main ipaddress.

### Options

- If you want to sync just one user, then comment out `da_users="${get_da_resellers}${get_da_users}"` and add `da_users="username"`.
- If you want to sync multiple users manually, comment out `da_users="${get_da_resellers}${get_da_users}"` and add `da_users="user1 user2 user3 user4"`.
