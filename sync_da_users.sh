#!/bin/bash
# Author: Unixxio / https://github.com/unixxio
# Date: October 17, 2018

source="" # source server
ssh_timeout="5" # timeout in seconds

disable_crons="true"
directadmin_backups="true"
file_backups="true"
database_backups="true"

# bash color notification types
error="\e[31mError\e[39m"
warning="\e[31mWarning\e[39m"
notification="\e[33mNotification\e[39m"
skipping="\e[33mWarning\e[39m"

# check if user is root
myuid=`/usr/bin/id -u`
if [ "${myuid}" != 0 ]; then
    echo -e "\n[ ${error} ] This script must be run as root.\n"
    exit 0;
fi

# check if the source variable is not empty
if [ "${source}" = "" ]; then
    echo -e "\n[ ${error} ] No source server. The variable is empty.\n"
    exit
fi

# check if ssh connection can be established
if ! ssh -o ConnectTimeout=${ssh_timeout} root@${source} "exit" > /dev/null 2>&1
then
    echo -e "\n[ ${error} ] SSH connection to \e[92m${source}\e[39m can't be established.\n"
    exit
fi

# check if directadmin_backups are set to true when disable_crons is set to true
if [ ${disable_crons} == "true" ]; then
    if [ ${directadmin_backups} == "true" ]; then
    echo "" > /dev/null 2>&1
    else
    echo -e "\n[ ${error} ] Script requires '\e[92mdirectadmin_backups\e[39m' to be set to '\e[92mtrue\e[39m' when '\e[92mdisable_crons\e[39m' is set to '\e[92mtrue\e[39m'.\n"
    fi
fi

# keep the variables below untouched
source_host=`ssh root@${source} "hostname"` # get hostname remote server
hostname=`hostname` # get hostname local server
local_ipaddress=`curl -s ifconfig.so | awk {'print $1'}` # acquire this servers main ipaddress

# get mysql password from remote and local server
local_sql_user=`grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2`
local_sql_password=`grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2`
remote_sql_user=`ssh root@${source} "grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`
remote_sql_password=`ssh root@${source} "grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`

# get resellers and users from remote server
get_da_resellers=`ssh root@${source} "cat /usr/local/directadmin/data/admin/reseller.list | sort -n | tr '\n' ' '"`
get_da_users=`ssh root@${source} "cat /usr/local/directadmin/data/users/*/users.list | sort -n | tr '\n' ' '"`

# complete list of users based on acquired users and resellers from above
da_users="${get_da_resellers}${get_da_users}"

# check if the da_users variable is NOT empty, else quit
if [ "${da_users}" = "" ]; then
    echo -e "\n[ ${error} ] No users entered."
    exit
fi

# validate if user exists on source server, else quit
for user in ${da_users}
do
    ssh root@${source} "getent passwd ${user}" > /dev/null 2>&1
    if [ $(ssh root@${source} "getent passwd ${user}") ]; then
        echo "" > /dev/null 2>&1
    else
        echo -e "\n[ ${error} ] ${user} does not exist.\n"
        exit
    fi
done

# check if remote mysql connection can be established, else quit
if ! ssh root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;'" > /dev/null 2>&1
then
    echo -e "\n[ ${error} ] Can't establish MySQL connection on \e[92m${source}\e[39m.\n"
    exit
fi

# check if local mysql connection can be establised, else quit
if ! /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e 'show databases;' > /dev/null 2>&1
then
    echo -e "\n[ ${error} ] Can't establish MySQL on \e[92mlocalhost\e[39m.\n"
    exit
fi

# check if main ipaddress of local server can be acquired, else quit
if [ "${local_ipaddress}" = "" ]; then
    echo -e "\n[ ${error} ] Can't determine this servers ipaddress. Please enter \e[92mlocal_ipaddress\e[39m manually."
    exit
fi

# tell user if cronjobs are enabled or disabled
if [ "${disable_crons}" = "true" ]; then
    echo -e "\n[ ${notification} ] Cronjobs will be \e[33mdisabled\e[39m."
else
    echo -e "\n[ ${warning} ] Cronjobs will be \e[31menabled\e[39m."
fi

# tell user if directadmin backups are enabled or disabled
if [ "${directadmin_backups}" = "true" ]; then
    echo -e "[ ${notification} ] DirectAdmin backups are \e[92menabled\e[39m."
else
    echo -e "[ ${skipping} ] DirectAdmin backups are \e[33mdisabled\e[39m."
fi

# tell user if file backups are enabled or disabled
if [ "${file_backups}" = "true" ]; then
    echo -e "[ ${notification} ] File backups (homedir) are \e[92menabled\e[39m."
else
    echo -e "[ ${skipping} ] File backups (homedir) are \e[33mdisabled\e[39m."
fi

# tell user if database backups are enabled or disabled
if [ "${database_backups}" = "true" ]; then
    echo -e "[ ${notification} ] Database backups are \e[92menabled\e[39m."
else
    echo -e "[ ${skipping} ] Database backups are \e[33mdisabled\e[39m."
fi

# confirm sync from source to destination before continue
echo -e "\nThis will sync the following resellers and/or users: \e[92m${da_users}\e[39m from \e[33m${source_host}\e[39m -> \e[92m${hostname}\e[39m.\n"
echo -e "The ipaddress used to restore the resellers and/or users is: \e[92m${local_ipaddress}\e[39m"
read -p "Are you sure you want to continue (y/n)? " choice
case "${choice}" in
    y|Y ) echo "";;
    n|N ) echo "" && exit;;
    * ) echo "[ ${warning} ] Invalid option";;
esac

# remove old directadmin backups
rm /home/admin/admin_backups/*.tar.gz > /dev/null 2>&1
ssh root@${source} "rm /home/admin/admin_backups/*.tar.gz" > /dev/null 2>&1

# exclude data (domains dir, e-mail, databases) from backups on remote server (greatly reduce user backup size)
backup_settings="skip_domains_in_backups skip_databases_in_backups skip_imap_in_backups"
for setting in ${backup_settings}
do
    if [[ `ssh root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep '${setting}'"` ]]; then
        ssh root@${source} "sed -i -e 's/${setting}=0/${setting}=1/g' /usr/local/directadmin/conf/directadmin.conf"
    else
        ssh root@${source} 'echo "${setting}=1" >> /usr/local/directadmin/conf/directadmin.conf'
    fi
done

# restart directadmin on remote server
ssh root@${source} "service directadmin restart" > /dev/null 2>&1

# sync users and databases if set to true in variables
for user in ${da_users}
do
    # variables
    creator=`ssh root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep creator | cut -f2- -d="`
    usertype=`ssh root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep usertype | cut -f2- -d="`
    user_backup="/home/admin/admin_backups/${usertype}.${creator}.${user}.tar.gz"

    # create directadmin backup on remote server
    if [ "${directadmin_backups}" = true ] ; then
        echo -e "[ DirectAdmin ]\n"
        # fix user permissions on remote server before creating a backup
        ssh root@${source} "/usr/local/directadmin/scripts/fix_da_user.sh ${user} ${usertype}"
        # create backup on remote server
        ssh root@${source} "echo 'action=backup&append%5Fto%5Fpath=nothing&database%5Fdata%5Faware=yes&email%5Fdata%5Faware=yes&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${user}&type=admin&value=multiple&when=now&where=local' >> /usr/local/directadmin/data/task.queue"
    fi

    # check if directadmin backup is ready before continue
    if [ "${directadmin_backups}" = true ] ; then
        echo -e "Exporting [ \e[94m${usertype}\e[39m ] \e[94m${user}\e[39m on \e[33m${source_host}\e[39m."
        while ssh root@${source} [ ! -f "${user_backup}" ];
        do
            sleep 1;
        done
    fi

    # import directadmin backup on this server with this server's main ipaddress
    if [ "${directadmin_backups}" = true ] ; then
        echo -e "Importing [ \e[94m${usertype}\e[39m ] \e[94m${user}\e[39m on \e[92m${hostname}\e[39m with ipaddress \e[92m${local_ipaddress}\e[39m."
        /usr/bin/rsync -a root@${source}:${user_backup} /home/admin/admin_backups/
        echo "action=restore&ip%5Fchoice=select&ip=${local_ipaddress}&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${usertype}%2E${creator}%2E${user}%2Etar%2Egz&type=admin&value=multiple&when=now&where=local" >> /usr/local/directadmin/data/task.queue
    fi

    # disable cronjobs if set to true
    if [ "${disable_crons}" = true ] ; then
        while [ ! -f "/usr/local/directadmin/data/users/${user}/crontab.conf" ];
        do
            sleep 1;
        done
    cat /dev/null > /usr/local/directadmin/data/users/${user}/crontab.conf
    echo "#DO NOT EDIT THIS FILE. Change through DirectAdmin" | crontab -u ${user} -
    fi

    # sync user files (starts only when user's home folder exists / waiting for directadmin user import to complete)
    if [ "${file_backups}" = true ] ; then
        echo -e "\n[ Syncing homedir ]\n"
        echo -e "Syncing \e[94m/home/${user}/\e[39m from \e[33m${source_host}\e[39m -> \e[92m${hostname}\e[39m."
        while [ ! -d /home/${user} ];
        do
            echo -e "Home directory for \e[94m${user}\e[39m does not yet exist. Waiting for DirectAdmin backup import to complete."
            sleep 1;
        done
        # extra check to make sure the user variable is not empty
        if [ "${user}" = "" ]; then
            echo -e "[ ${warning} ] no user(s) entered. Skip syncing homedir."
        else
            /usr/bin/rsync -a -p root@${source}:/home/${user}/ /home/${user}/ --delete
        fi
    fi

    # sync databases (if exists)
    if [ "${database_backups}" = true ] ; then
        echo -e "\n[ Databases ]\n"
        user_database=`ssh root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;' | grep ${user}"`
        if [[ ${user_database} ]]; then
            for database in ${user_database}
            do
                echo -e "Importing database \e[94m${database}\e[39m from \e[33m${source_host}\e[39m -> \e[92m${hostname}\e[39m."
                /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e "drop database ${database};" > /dev/null 2>&1
                /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e "create database ${database};" > /dev/null 2>&1
                ssh root@${source} /usr/local/mysql/bin/mysqldump --user=${remote_sql_user} --password=${remote_sql_password} ${database} | /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -D ${database}
            done
        fi
    fi

# echo empty line
echo ""
done

# restore original directadmin backup values in directadmin.conf on remote server
backup_settings="skip_domains_in_backups skip_databases_in_backups skip_imap_in_backups"
for setting in ${backup_settings}
do
    if [[ `ssh root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep '${setting}'"` ]]; then
        ssh root@${source} "sed -i -e 's/${setting}=1/${setting}=0/g' /usr/local/directadmin/conf/directadmin.conf"
    else
        ssh root@${source} 'echo "${setting}=0" >> /usr/local/directadmin/conf/directadmin.conf'
    fi
done

# restart directadmin on remote server
ssh root@${source} "service directadmin restart" > /dev/null 2>&1

# stop script
exit
