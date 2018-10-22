#!/bin/bash
# Author: Unixxio / https://github.com/unixxio
# Date: October 18, 2018

source="" # source server
prompt_ssh_password="false" # if false then ssh key is used (passwordless)

enable_crons="false"
directadmin_backups="true"
sync_homedirs="true"
database_backups="true"

# colorcodes
green="\e[92m"
red="\e[31m"
yellow="\e[33m"
purple="\e[94m"
reset=`tput sgr0`

hostname=`hostname` # get hostname local server
local_ipaddress=`curl -s ifconfig.so | awk {'print $1'}` # acquire this servers main ipaddress

# check if user is root
myuid=`/usr/bin/id -u`
if [ "${myuid}" != 0 ]; then
    echo -e "\n[ ${red}Error${reset} ] This script must be run as root.\n"
    exit 0;
fi

# check if the source variable is not empty
if [ "${source}" = "" ]; then
    echo -e "\n[ ${red}Error${reset} ] No source server. The variable is empty.\n"
    exit
fi

# check if directadmin_backups are set to true when enable_crons is set to true
if [ ${enable_crons} == "true" ]; then
    if [ ${directadmin_backups} == "true" ]; then
    echo "" > /dev/null 2>&1
    else
    echo -e "\n[ ${red}Error${reset} ] Script requires '${green}directadmin_backups${reset}' to be set to '${green}true${reset}' when '${green}enable_crons${reset}' is set to 'true${reset}'."
    echo -e "[ ${red}Error${reset} ] Script will now abort.\n"
    exit
    fi
fi

# ask for ssh root password for source if prompt_ssh_password is set true
if [ ${prompt_ssh_password} == "true" ]; then
    # install required sshpass
    apt-get install sshpass -y > /dev/null 2>&1
    echo -e -n "\nPlease enter root password for ${yellow}${source}${reset} (password is hidden): \n"
    read -s ssh_password
fi

# check if ssh connection can be established
if [ ${prompt_ssh_password} == "true" ]; then
    if ! /usr/bin/sshpass -p ${ssh_password} ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${source} "exit" > /dev/null 2>&1
    then
        echo -e "\n[ ${red}Error${reset} ] SSH connection to ${yellow}${source}${reset} can't be established."
        echo -e "Make sure that ${green}${local_ipaddress}${reset} is allowed and ${green}PermitRootLogin${reset} is set to ${green}yes${reset} on ${yellow}${source}${reset}.\n"
        exit
    fi
else
    if ! ssh -o ConnectTimeout=5 root@${source} "exit" > /dev/null 2>&1
    then
        echo -e "\n[ ${red}Error${reset} ] SSH connection to ${yellow}${source}${reset} can't be established."
        echo -e "Make sure that ${green}${local_ipaddress}${reset} is allowed and ${green}PermitRootLogin${reset} is set to ${green}yes${reset} on ${yellow}${source}${reset}.\n"
        exit
    fi
fi

# keep the variables below untouched
if [ ${prompt_ssh_password} == "true" ]; then
    source_host=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "hostname"` # get hostname remote server
else
    source_host=`ssh root@${source} "hostname"` # get hostname remote server
fi

# get mysql password from remote and local server
local_sql_user=`grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2`
local_sql_password=`grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2`
if [ ${prompt_ssh_password} == "true" ]; then
    remote_sql_user=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`
    remote_sql_password=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`
else
    remote_sql_user=`ssh root@${source} "grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`
    remote_sql_password=`ssh root@${source} "grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2"`
fi

# get resellers and users from remote server
if [ ${prompt_ssh_password} == "true" ]; then
    get_da_resellers=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/data/admin/reseller.list | sort -n | tr '\n' ' '"`
    get_da_users=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/data/users/*/users.list | sort -n | tr '\n' ' '"`
else
    get_da_resellers=`ssh root@${source} "cat /usr/local/directadmin/data/admin/reseller.list | sort -n | tr '\n' ' '"`
    get_da_users=`ssh root@${source} "cat /usr/local/directadmin/data/users/*/users.list | sort -n | tr '\n' ' '"`
fi

# sync all users or enter manually
sync_question="\nDo you want to sync all resellers and users? "
ask_sync_question=`echo -e $sync_question`
read -r -p "${ask_sync_question} [y/N] " sync_response
case "${sync_response}" in
    [yY][eE][sS]|[yY])
        # complete list of users based on acquired users and resellers from above
        da_users="${get_da_resellers}${get_da_users}"
        ;;
    *)
        echo -e "\n[ ${yellow}Example${reset} ] ${purple}reseller1 reseller2 user1 user2${reset}"
        echo -e -n "Please enter user(s): "
        read da_users
        ;;
    *)
esac

# check if the da_users variable is NOT empty, else quit
if [ "${da_users}" = "" ]; then
    echo -e "\n[ ${red}Error${reset} ] No users entered."
    exit
fi

# validate if user exists on source server, else quit
for user in ${da_users}
do
    if [ ${prompt_ssh_password} == "true" ]; then
        /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "getent passwd ${user}" > /dev/null 2>&1
    else
        ssh root@${source} "getent passwd ${user}" > /dev/null 2>&1
    fi
    if [ ${prompt_ssh_password} == "true" ]; then
        if [ $(/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "getent passwd ${user}") ]; then
            echo "" > /dev/null 2>&1
        else
            echo -e "\n[ ${red}Error${reset} ] ${user} does not exist on ${yellow}${source_host}${reset}.\n"
            exit
        fi
    else
        if [ $(ssh root@${source} "getent passwd ${user}") ]; then
            echo "" > /dev/null 2>&1
        else
            echo -e "\n[ ${red}Error${reset} ] ${user} does not exist on ${yellow}${source_host}${reset}.\n"
            exit
        fi
    fi
done

# check if remote mysql connection can be established, else quit
if [ ${prompt_ssh_password} == "true" ]; then
    if ! /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;'" > /dev/null 2>&1
    then
        echo -e "\n[ ${red}Error${reset} ] Can't establish MySQL connection on ${green}${source}${reset}.\n"
        exit
    fi
else
    if ! ssh root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;'" > /dev/null 2>&1
    then
        echo -e "\n[ ${red}Error${reset} ] Can't establish MySQL connection on ${green}${source}${reset}.\n"
        exit
    fi
fi

# check if local mysql connection can be establised, else quit
if ! /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e 'show databases;' > /dev/null 2>&1
then
    echo -e "\n[ ${red}Error${reset} ] Can't establish MySQL on ${green}localhost${reset}.\n"
    exit
fi

# check if main ipaddress of local server can be acquired, else quit
if [ "${local_ipaddress}" = "" ]; then
    echo -e "\n[ ${red}Error${reset} ] Can't determine this servers ipaddress. Please enter ${green}local_ipaddress${reset} manually."
    exit
fi

# tell user if cronjobs are enabled or disabled
if [ "${enable_crons}" = "false" ]; then
    echo -e "\n[ ${yellow}Notification${reset} ] Cronjobs will be ${yellow}disabled${reset}. (testing mode!)"
else
    echo -e "\n[ ${red}Warning${reset} ] Cronjobs will be ${red}enabled${reset}. (only use when going live!)"
fi

# tell user if directadmin backups are enabled or disabled
if [ "${directadmin_backups}" = "true" ]; then
    echo -e "[ ${yellow}Notification${reset} ] DirectAdmin backups are ${green}enabled${reset}."
else
    echo -e "[ ${yellow}Skipping${reset} ] DirectAdmin backups are ${yellow}disabled${reset}."
fi

# tell user if file backups are enabled or disabled
if [ "${sync_homedirs}" = "true" ]; then
    echo -e "[ ${yellow}Notification${reset} ] File backups (homedir) are ${green}enabled${reset}."
else
    echo -e "[ ${yellow}Skipping${reset} ] File backups (homedir) are ${yellow}disabled${reset}."
fi

# tell user if database backups are enabled or disabled
if [ "${database_backups}" = "true" ]; then
    echo -e "[ ${yellow}Notification${reset} ] Database backups are ${green}enabled${reset}."
else
    echo -e "[ ${yellow}Skipping${reset} ] Database backups are ${yellow}disabled${reset}."
fi

# confirm sync from source to destination before continue
echo -e "\nThis will sync the following reseller(s) and/or user(s): ${purple}${da_users}${reset} from ${yellow}${source_host}${reset} -> ${green}${hostname}${reset}.\n"
echo -e "The ipaddress used to restore the reseller(s) and/or user(s) is: ${green}${local_ipaddress}${reset}"
read -p "Are you sure you want to continue (y/n)? " choice
case "${choice}" in
    y|Y ) echo "";;
    n|N ) echo "" && exit;;
    * ) echo "[ ${red}Warning${reset} ] Invalid option";;
esac

# remove old directadmin backups
rm /home/admin/admin_backups/*.tar.gz > /dev/null 2>&1
if [ ${prompt_ssh_password} == "true" ]; then
    /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "rm /home/admin/admin_backups/*.tar.gz" > /dev/null 2>&1
else
    ssh root@${source} "rm /home/admin/admin_backups/*.tar.gz" > /dev/null 2>&1
fi

# exclude data (domains dir, e-mail, databases) from backups on remote server (greatly reduce user backup size)
backup_settings="skip_domains_in_backups skip_databases_in_backups skip_imap_in_backups"
for setting in ${backup_settings}
do
    if [ ${prompt_ssh_password} == "true" ]; then
        if [[ `/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep ${setting}"` ]]; then
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "sed -i -e 's/${setting}=0/${setting}=1/g' /usr/local/directadmin/conf/directadmin.conf"
        else
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "echo '${setting}=1' >> /usr/local/directadmin/conf/directadmin.conf"
        fi
    else
        if [[ `ssh root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep ${setting}"` ]]; then
            ssh root@${source} "sed -i -e 's/${setting}=0/${setting}=1/g' /usr/local/directadmin/conf/directadmin.conf"
        else
            ssh root@${source} "echo '${setting}=1' >> /usr/local/directadmin/conf/directadmin.conf"
        fi
    fi
done

# restart directadmin on remote server
if [ ${prompt_ssh_password} == "true" ]; then
    /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "service directadmin restart" > /dev/null 2>&1
else
    ssh root@${source} "service directadmin restart" > /dev/null 2>&1
fi

# sync users and databases if set to true in variables
for user in ${da_users}
do
    # variables
    if [ ${prompt_ssh_password} == "true" ]; then
        creator=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep creator | cut -f2- -d="`
        usertype=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep usertype | cut -f2- -d="`
    else
        creator=`ssh root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep creator | cut -f2- -d="`
        usertype=`ssh root@${source} "cat /usr/local/directadmin/data/users/${user}/user.conf | grep usertype | cut -f2- -d="`
    fi
    user_backup="/home/admin/admin_backups/${usertype}.${creator}.${user}.tar.gz"

    # create directadmin backup on remote server
    if [ "${directadmin_backups}" = "true" ]; then
        echo -e "[ DirectAdmin ]\n"
        if [ ${prompt_ssh_password} == "true" ]; then
            # fix user permissions on remote server before creating a backup
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "/usr/local/directadmin/scripts/fix_da_user.sh ${user} ${usertype}"
            # create backup on remote server
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "echo 'action=backup&append%5Fto%5Fpath=nothing&database%5Fdata%5Faware=yes&email%5Fdata%5Faware=yes&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${user}&type=admin&value=multiple&when=now&where=local' >> /usr/local/directadmin/data/task.queue"
        else
            # fix user permissions on remote server before creating a backup
            ssh root@${source} "/usr/local/directadmin/scripts/fix_da_user.sh ${user} ${usertype}"
            # create backup on remote server
            ssh root@${source} "echo 'action=backup&append%5Fto%5Fpath=nothing&database%5Fdata%5Faware=yes&email%5Fdata%5Faware=yes&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${user}&type=admin&value=multiple&when=now&where=local' >> /usr/local/directadmin/data/task.queue"
        fi
    fi

    # check if directadmin backup is ready before continue
    if [ "${directadmin_backups}" = "true" ]; then
        echo -e "Exporting [ ${purple}${usertype}${reset} ] ${purple}${user}${reset} on ${yellow}${source_host}${reset}."
        if [ ${prompt_ssh_password} == "true" ]; then
            while /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} [ ! -f "${user_backup}" ];
            do
                sleep 1;
            done
        else
            while ssh root@${source} [ ! -f "${user_backup}" ];
            do
                sleep 1;
            done
        fi
    fi

    # import directadmin backup on this server with this server's main ipaddress
    if [ "${directadmin_backups}" = "true" ]; then
        echo -e "Importing [ ${purple}${usertype}${reset} ] ${purple}${user}${reset} on ${green}${hostname}${reset} with ipaddress ${green}${local_ipaddress}${reset}."
        if [ ${prompt_ssh_password} == "true" ]; then
            /usr/bin/sshpass -p ${ssh_password} /usr/bin/rsync -a root@${source}:${user_backup} /home/admin/admin_backups/
            echo "action=restore&ip%5Fchoice=select&ip=${local_ipaddress}&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${usertype}%2E${creator}%2E${user}%2Etar%2Egz&type=admin&value=multiple&when=now&where=local" >> /usr/local/directadmin/data/task.queue
        else
            /usr/bin/rsync -a root@${source}:${user_backup} /home/admin/admin_backups/
            echo "action=restore&ip%5Fchoice=select&ip=${local_ipaddress}&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${usertype}%2E${creator}%2E${user}%2Etar%2Egz&type=admin&value=multiple&when=now&where=local" >> /usr/local/directadmin/data/task.queue
        fi
    fi

    # disable cronjobs if set to true
    if [ "${enable_crons}" = "false" ]; then
        # only continue script when crontab.conf exists (then user is imported)
        while [ ! -f "/usr/local/directadmin/data/users/${user}/crontab.conf" ];
        do
            sleep 1;
        done
        # empty both crontab.conf and crontab
        cat /dev/null > /usr/local/directadmin/data/users/${user}/crontab.conf
        echo "#DO NOT EDIT THIS FILE. Change through DirectAdmin" | crontab -u ${user} -
        # prevent e-mail from reaching end users when in testing mode (for example failed let's encrypt renewals)
        while [ ! -f "/usr/local/directadmin/data/users/${user}/user.conf" ];
        do
            sleep 1;
        done
        email=`cat /usr/local/directadmin/data/users/${user}/user.conf | grep "email=" | cut -d= -f2`
        sed -i -e "s/${email}/diradmin@${hostname}/g" /usr/local/directadmin/data/users/${user}/user.conf
        service directadmin restart
    fi

    # sync user files (starts only when user's home folder exists / waiting for directadmin user import to complete)
    if [ "${sync_homedirs}" = "true" ] ; then
        echo -e "\n[ Syncing homedir ]\n"
        echo -e "Syncing ${purple}/home/${user}/${reset} from ${yellow}${source_host}${reset} -> ${green}${hostname}${reset}."
        while [ ! -d /home/${user} ];
        do
            echo -e "Home directory for ${purple}${user}${reset} does not yet exist. Waiting for DirectAdmin backup import to complete."
            sleep 1;
        done
        # extra check to make sure the user variable is not empty
        if [ "${user}" = "" ]; then
            echo -e "[ ${red}Warning${reset} ] no user(s) entered. Skip syncing homedir."
        else
            if [ ${prompt_ssh_password} == "true" ]; then
                /usr/bin/sshpass -p ${ssh_password} /usr/bin/rsync -a -p root@${source}:/home/${user}/ /home/${user}/ --delete
            else
                /usr/bin/rsync -a -p root@${source}:/home/${user}/ /home/${user}/ --delete
            fi
        fi
    fi

    # sync databases (if exists)
    if [ "${database_backups}" = "true" ] ; then
        echo -e "\n[ Databases ]\n"
        if [ ${prompt_ssh_password} == "true" ]; then
            user_database=`/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;' | grep ${user}"`
        else
            user_database=`ssh root@${source} "/usr/local/mysql/bin/mysql --user=${remote_sql_user} --password=${remote_sql_password} -e 'show databases;' | grep ${user}"`
        fi
        # only sync database if one is found
        if [[ ${user_database} ]]; then
            for database in ${user_database}
            do
                # extra check to make sure database var is not empty
                if [ "${database}" = "" ]; then
                    echo "[ ${red}Error${reset} ] Database variable can't be empty. Script will now abort."
                    exit
                else
                    echo -e "Importing database ${purple}${database}${reset} from ${yellow}${source_host}${reset} -> ${green}${hostname}${reset}."
                    /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e "drop database ${database};" > /dev/null 2>&1
                    /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -e "create database ${database};" > /dev/null 2>&1
                    if [ ${prompt_ssh_password} == "true" ]; then
                        /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} /usr/local/mysql/bin/mysqldump --user=${remote_sql_user} --password=${remote_sql_password} ${database} | /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -D ${database}
                    else
                        ssh root@${source} /usr/local/mysql/bin/mysqldump --user=${remote_sql_user} --password=${remote_sql_password} ${database} | /usr/local/mysql/bin/mysql --user=${local_sql_user} --password=${local_sql_password} -D ${database}
                    fi
                fi
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
    if [ ${prompt_ssh_password} == "true" ]; then
        if [[ `/usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep ${setting}"` ]]; then
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "sed -i -e 's/${setting}=1/${setting}=0/g' /usr/local/directadmin/conf/directadmin.conf"
        else
            /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "echo '${setting}=0' >> /usr/local/directadmin/conf/directadmin.conf"
        fi
    else
        if [[ `ssh root@${source} "cat /usr/local/directadmin/conf/directadmin.conf | grep ${setting}"` ]]; then
            ssh root@${source} "sed -i -e 's/${setting}=1/${setting}=0/g' /usr/local/directadmin/conf/directadmin.conf"
        else
            ssh root@${source} "echo '${setting}=0' >> /usr/local/directadmin/conf/directadmin.conf"
        fi
    fi
done

# restart directadmin on remote server
if [ ${prompt_ssh_password} == "true" ]; then
    /usr/bin/sshpass -p ${ssh_password} ssh -o StrictHostKeyChecking=no root@${source} "service directadmin restart" > /dev/null 2>&1
else
    ssh root@${source} "service directadmin restart" > /dev/null 2>&1
fi

# end script
exit
