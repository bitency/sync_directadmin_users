#!/bin/bash
# DirectAdmin user migration script
# Author: Unixxio / https://github.com/unixxio
# Date: November 14, 2018

BEGIN_SCRIPT_TIME="$(date +"%s")"

# source ipaddress
SOURCE=""

# options
IMPORT_USERS="true"
MULTIPLE_PHP="false"
IMPORT_CRONS="false"
SYNC_HOMEDIR="false"
SYNC_DATABASES="false"

# optional: fix permissions on source server before exporting/importing user
FIX_PERMISSIONS="false"

# set bash colors
GREEN="\e[92m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="$(tput sgr0)"

# acquire local server hostname and ipaddress
LOCAL_HOSTNAME="$(hostname)"
LOCAL_IPADDRESS="$(curl -s ifconfig.so | awk '{print $1}')"

# determine OS distribution (needed later to install required packages)
DISTRIBUTION="$(cat /etc/os-release | grep -w 'NAME=' | cut -d= -f2 | tr -d '"' | awk {'print $1'})"

# check if script is executed as root
MYUID="$(/usr/bin/id -u)"
if [[ "${MYUID}" != 0 ]]; then
    echo -e "\n[ ${RED}Error${RESET} ] This script must be run as root.\n"
    exit 0;
fi

# check if the source variable is not empty
if [[ "${SOURCE}" = "" ]]; then
    echo -e "\n[ ${RED}Error${RESET} ] No source server. The variable is empty.\n"
    exit
fi

# check if IMPORT_USERS is set to true when IMPORT_CRONS is set to true
if [[ "${IMPORT_CRONS}" == "true" ]]; then
    if [[ "${IMPORT_USERS}" == "true" ]]; then
    echo "" > /dev/null 2>&1
    else
    echo -e "\n[ ${RED}Error${RESET} ] Script requires '${YELLOW}IMPORT_USERS${RESET}' to be '${YELLOW}true${RESET}' when '${YELLOW}IMPORT_CRONS${RESET}' is '${YELLOW}true${RESET}'."
    echo -e "[ ${RED}Error${RESET} ] Script will now abort.\n"
    exit
    fi
fi

# clear directadmin tickets
> /usr/local/directadmin/data/admin/tickets.list

# start script message
clear && echo -e "\n[ ${YELLOW}Running script checks and installing required packages. Please wait...${RESET} ]"

# install required packages based on OS distribution
if [[ "${DISTRIBUTION}" == "Debian" ]]; then
    apt-get install sshpass -y > /dev/null 2>&1
fi
if [[ "${DISTRIBUTION}" == "Ubuntu" ]]; then
    apt-get install sshpass -y > /dev/null 2>&1
fi
if [[ "${DISTRIBUTION}" == "CentOS" ]]; then
    yum install sshpass -y > /dev/null 2>&1
fi

# check if ssh connection (password or passwordless with ssh key) can be established
ssh -o BatchMode=yes -o ConnectTimeout=5 root@"${SOURCE}" 'exit' > /dev/null 2>&1
if [[ $? -eq 0 ]]
then
    echo > /dev/null 2>&1 # do nothing
else
    echo -e -n "\nPlease enter root password for ${YELLOW}${SOURCE}${RESET} (password is hidden): \n"
    read -r -s SSH_PASS
    /usr/bin/sshpass -p "${SSH_PASS}" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"${SOURCE}" 'exit' > /dev/null 2>&1
    if [[ $? -eq 0 ]]
    then
        SSH_PASSWORD="true"
    else
        echo -e "\n[ ${RED}Error${RESET} ] SSH connection to ${YELLOW}${SOURCE}${RESET} can't be established."
        echo -e "Make sure that ${YELLOW}${LOCAL_IPADDRESS}${RESET} is allowed and/or ${YELLOW}PermitRootLogin${RESET} is set to ${YELLOW}yes${RESET} on ${YELLOW}${SOURCE}${RESET}.\n"
        exit
    fi
fi

# acquire hostname of remote server
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    SOURCE_HOSTNAME="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "hostname")"
else
    SOURCE_HOSTNAME="$(ssh root@"${SOURCE}" "hostname")"
fi

# acquire mysql user and password from local server
LOCAL_SQL_USER="$(grep "^user=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2)"
LOCAL_SQL_PASSWORD="$(grep "^passwd=" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2)"

# acquire mysql user and password from remote server
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    REMOTE_SQL_USER="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "grep \"^user=\" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2")"
    REMOTE_SQL_PASSWORD="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "grep \"^passwd=\" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2")"
else
    REMOTE_SQL_USER="$(ssh root@"${SOURCE}" "grep \"^user=\" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2")"
    REMOTE_SQL_PASSWORD="$(ssh root@"${SOURCE}" "grep \"^passwd=\" /usr/local/directadmin/conf/mysql.conf | cut -d= -f2")"
fi

# acquire resellers and users from remote server
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    GET_DA_RESELLERS="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "cat /usr/local/directadmin/data/admin/reseller.list | sort -n | tr '\n' ' '| sed 's/\s$//'")"
    GET_DA_USERS="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "cat /usr/local/directadmin/data/users/*/users.list | sort -n | tr '\n' ' ' | sed 's/\s$//'")"
else
    GET_DA_RESELLERS="$(ssh root@"${SOURCE}" "cat /usr/local/directadmin/data/admin/reseller.list | sort -n | tr '\n' ' ' | sed 's/\s$//'")"
    GET_DA_USERS="$(ssh root@"${SOURCE}" "cat /usr/local/directadmin/data/users/*/users.list | sort -n | tr '\n' ' ' | sed 's/\s$//'")"
fi

# sync all resellers and users or enter manually
clear && echo -e "\n${YELLOW}It's safe to answer this question. It will not start anything yet!${RESET}"
QUESTION="Do you want to sync all resellers and users?"
QUESTION_ANSWER="$(echo -e "${QUESTION}")"
read -r -p "${QUESTION_ANSWER} (y/n) " QUESTION_RESPONSE
case "${QUESTION_RESPONSE}" in
    [yY][eE][sS]|[yY])
        # complete list of users based on acquired users and resellers from above
        DA_USERS="${GET_DA_RESELLERS} ${GET_DA_USERS}"
        ;;
    [nN][oO]|[Nn])
        # acquire list of users from user input
        echo -e "\nExample: ${YELLOW}reseller1 reseller2 user1 user2${RESET}"
        echo -e -n "Please enter user(s): "
        read DA_USERS
        ;;
    *)
        # invalid option
        echo -e "\n[ ${RED}Warning${RESET} ] Invalid option\n"
        exit
        ;;
esac

# check if the da_users is not empty
if [[ -z "${DA_USERS}" ]]; then
    echo -e "\n[ ${RED}Error${RESET} ] No users entered."
    exit
fi

# validate if user exists on source server
for USER in ${DA_USERS}
do
    if [[ "${SSH_PASSWORD}" == "true" ]]; then
        /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "getent passwd ${USER}" > /dev/null 2>&1
    else
        ssh root@"${SOURCE}" "getent passwd ${USER}" > /dev/null 2>&1
    fi
    if [[ "${SSH_PASSWORD}" == "true" ]]; then
        if [[ "$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "getent passwd ${USER}")" ]]; then
            echo "" > /dev/null 2>&1
        else
            echo -e "\n[ ${RED}Error${RESET} ] ${USER} does not exist on ${YELLOW}${SOURCE_HOSTNAME}${RESET}.\n"
            exit
        fi
    else
        if [[ "$(ssh root@"${SOURCE}" "getent passwd ${USER}")" ]]; then
            echo "" > /dev/null 2>&1
        else
            echo -e "\n[ ${RED}Error${RESET} ] ${USER} does not exist on ${YELLOW}${SOURCE_HOSTNAME}${RESET}.\n"
            exit
        fi
    fi
done

# count number of users in da_users
TOTALUSERS="$(printf '%s\n' ${DA_USERS}:q | wc -w)"

# check if remote mysql connection can be established
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    if ! /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "/usr/local/mysql/bin/mysql --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} -e 'show databases;'" > /dev/null 2>&1
    then
        echo -e "\n[ ${RED}Error${RESET} ] Can't establish MySQL connection on ${YELLOW}${SOURCE}${RESET}.\n"
        exit
    fi
else
    if ! ssh root@"${SOURCE}" "/usr/local/mysql/bin/mysql --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} -e 'show databases;'" > /dev/null 2>&1
    then
        echo -e "\n[ ${RED}Error${RESET} ] Can't establish MySQL connection on ${YELLOW}${SOURCE}${RESET}.\n"
        exit
    fi
fi

# check if local mysql connection can be establised
if ! /usr/local/mysql/bin/mysql --user=${LOCAL_SQL_USER} --password=${LOCAL_SQL_PASSWORD} -e 'show databases;' > /dev/null 2>&1
then
    echo -e "\n[ ${RED}Error${RESET} ] Can't establish MySQL on ${YELLOW}localhost${RESET}.\n"
    exit
fi

# check if main ipaddress of local server can be acquired
if [[ -z "${LOCAL_IPADDRESS}" ]]; then
    echo -e "\n[ ${RED}Error${RESET} ] Can't determine this servers ipaddress. Please enter ${YELLOW}LOCAL_IPADDRESS${RESET} manually or make sure this server has an active internet connection."
    exit
fi

# tell user if directadmin backups are enabled or disabled
if [[ "${IMPORT_USERS}" == "true" ]]; then
    echo -e "\n[ ${GREEN}true${RESET}  ] Import users"
else
    echo -e "\n[ ${YELLOW}false${RESET} ] Import users"
fi

# tell user if support for multiple php versions is enabled or disabled
if [[ "${MULTIPLE_PHP}" == "true" ]]; then
    echo -e "[ ${GREEN}true${RESET}  ] Multiple PHP versions"
else
    echo -e "[ ${YELLOW}false${RESET} ] Multiple PHP versions"
fi

# tell user if cronjobs are enabled or disabled
if [[ "${IMPORT_CRONS}" == "false" ]]; then
    echo -e "[ ${YELLOW}false${RESET} ] Import cronjobs"
else
    echo -e "[ ${GREEN}true${RESET}  ] Import cronjobs"
fi

# tell user if sync homedir is enabled or disabled
if [[ "${SYNC_HOMEDIR}" == "true" ]]; then
    echo -e "[ ${GREEN}true${RESET}  ] Sync homedir"
else
    echo -e "[ ${YELLOW}false${RESET} ] Sync homedir"
fi

# tell user if database backups are enabled or disabled
if [[ "${SYNC_DATABASES}" == "true" ]]; then
    echo -e "[ ${GREEN}true${RESET}  ] Sync databases"
else
    echo -e "[ ${YELLOW}false${RESET} ] Sync databases"
fi

# remove old directadmin backups
rm /home/admin/admin_backups/*.tar.gz > /dev/null 2>&1
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "rm /home/admin/admin_backups/*.tar.gz" > /dev/null 2>&1
else
    ssh root@"${SOURCE}" "rm /home/admin/admin_backups/*.tar.gz" > /dev/null 2>&1
fi

# confirm sync from source to destination before continue
echo -e "\nNumber of reseller(s) and/or user(s) found: ${YELLOW}${TOTALUSERS}${RESET}"
echo -e "This will sync the following reseller(s) and/or user(s): ${YELLOW}${DA_USERS}${RESET}"
echo -e "\nSync from [ ${YELLOW}${SOURCE_HOSTNAME}${RESET} ] -> [ ${YELLOW}${LOCAL_HOSTNAME}${RESET} ]"
echo -e "The ipaddress used to restore the reseller(s) and/or user(s) is: [ ${YELLOW}${LOCAL_IPADDRESS}${RESET} ]"
read -r -p "Are you sure you want to continue (y/n)? " ANSWER
case "${ANSWER}" in
    y|Y ) echo "";;
    n|N ) echo "" && exit;;
    * ) echo -e "[ ${RED}Warning${RESET} ] Invalid option" && exit;;
esac

# sync users and databases if set to true in variables
clear && echo ""
USERCOUNT="0";
for USER in ${DA_USERS}
do
    # start timer for user sync
    BEGIN_USERSYNC_TIME="$(date +"%s")"
    # variables
    if [[ "${SSH_PASSWORD}" == "true" ]]; then
        CREATOR="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "cat /usr/local/directadmin/data/users/${USER}/user.conf | grep creator | cut -f2- -d=")"
        USERTYPE="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "cat /usr/local/directadmin/data/users/${USER}/user.conf | grep usertype | cut -f2- -d=")"
    else
        CREATOR="$(ssh root@"${SOURCE}" "cat /usr/local/directadmin/data/users/${USER}/user.conf | grep creator | cut -f2- -d=")"
        USERTYPE="$(ssh root@"${SOURCE}" "cat /usr/local/directadmin/data/users/${USER}/user.conf | grep usertype | cut -f2- -d=")"
    fi
    BACKUP_PATH="/home/admin/admin_backups/${USERTYPE}.${CREATOR}.${USER}.tar.gz"

    # create directadmin backup on remote server
    BACKUP_EXPORT_COMMAND="action=backup&append%5Fto%5Fpath=nothing&database%5Fdata%5Faware=yes&email%5Fdata%5Faware=yes&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&option%30=autoresponder&option%31=database&option%32=email&option%33=emailsettings&option%34=forwarder&option%35=ftp&option%36=ftpsettings&option%37=list&option%38=subdomain&option%39=vacation&owner=admin&select%30=${USER}&type=admin&value=multiple&what=select&when=now&where=local"
    if [[ "${IMPORT_USERS}" == "true" ]]; then
        if [[ "${SSH_PASSWORD}" == "true" ]]; then
            # fix user permissions on remote server before creating a backup
            if [[ "${FIX_PERMISSIONS}" == "true" ]]; then
                /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "/usr/local/directadmin/scripts/fix_da_user.sh ${USER} ${USERTYPE}"
            fi
            # create backup on remote server
            /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "echo '${BACKUP_EXPORT_COMMAND}' >> /usr/local/directadmin/data/task.queue"
        else
            # fix user permissions on remote server before creating a backup
            if [[ "${FIX_PERMISSIONS}" == "true" ]]; then
                ssh root@"${SOURCE}" "/usr/local/directadmin/scripts/fix_da_user.sh ${USER} ${USERTYPE}"
            fi
            # create backup on remote server
            ssh root@"${SOURCE}" "echo '${BACKUP_EXPORT_COMMAND}' >> /usr/local/directadmin/data/task.queue"
        fi
    fi

    # check if directadmin backup (tar.gz) exists before continue
    if [[ "${IMPORT_USERS}" == "true" ]]; then
        echo -e "[ ${YELLOW}DirectAdmin${RESET} ] export [ ${YELLOW}${USERTYPE}${RESET} ] [ ${YELLOW}${USER}${RESET} ] [ ${YELLOW}${SOURCE_HOSTNAME}${RESET} ]"
        if [[ "${SSH_PASSWORD}" == "true" ]]; then
            while /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" [ ! -f "${BACKUP_PATH}" ];
            do
                sleep 1;
            done
        else
            while ssh root@"${SOURCE}" [ ! -f "${BACKUP_PATH}" ];
            do
                sleep 1;
            done
        fi
    fi

    # import directadmin backup on this server with this server's main ipaddress
    BACKUP_IMPORT_COMMAND="action=restore&ip%5Fchoice=file&local%5Fpath=%2Fhome%2Fadmin%2Fadmin%5Fbackups&owner=admin&select%30=${USERTYPE}%2E${CREATOR}%2E${USER}%2Etar%2Egz&type=admin&value=multiple&when=now&where=local"
    if [[ "${IMPORT_USERS}" == "true" ]]; then
        if [[ "${IMPORT_CRONS}" == "false" ]]; then
            echo -e "[ ${YELLOW}DirectAdmin${RESET} ] import [ ${YELLOW}${USERTYPE}${RESET} ] [ ${YELLOW}${USER}${RESET} ] [ ${YELLOW}${LOCAL_HOSTNAME}${RESET} ]"
        else
            echo -e "[ ${YELLOW}DirectAdmin${RESET} ] import [ ${YELLOW}${USERTYPE}${RESET} ] [ ${YELLOW}${USER}${RESET} ] [ ${YELLOW}${LOCAL_HOSTNAME}${RESET} ]\n"
        fi
        if [[ "${SSH_PASSWORD}" == "true" ]]; then
            /usr/bin/sshpass -p "${SSH_PASS}" /usr/bin/rsync -a root@"${SOURCE}":${BACKUP_PATH} /home/admin/admin_backups/
        else
            /usr/bin/rsync -a root@"${SOURCE}":${BACKUP_PATH} /home/admin/admin_backups/
        fi
        # disable cronjobs if set to false
        if [[ "${IMPORT_CRONS}" == "false" ]]; then
            # unzip backup
            cd /home/admin/admin_backups/
            tar -xvf ${USERTYPE}.${CREATOR}.${USER}.tar.gz > /dev/null 2>&1
            rm ${USERTYPE}.${CREATOR}.${USER}.tar.gz
            # clear crontab.conf
            echo "" > backup/crontab.conf
            # prevent e-mail from reaching end user
            CUSTOMER_EMAIL="$(cat backup/user.conf | grep "email=" | cut -d= -f2)"
            sed -i -e "s/${CUSTOMER_EMAIL}/diradmin@${LOCAL_HOSTNAME}/g" backup/user.conf
            # set ip address to local ip address
            CURRENT_IP="$(cat backup/user.conf | grep "ip=" | cut -d= -f2)"
            sed -i -e "s/${CURRENT_IP}/${LOCAL_IPADDRESS}/g" backup/user.conf
            echo "${LOCAL_IPADDRESS}" > backup/ip.list
            # create new tar.gz file before running import
            tar -czvf ${USERTYPE}.${CREATOR}.${USER}.tar.gz backup > /dev/null 2>&1
            rm -rf backup && cd
        fi
        # unzip backup
        cd /home/admin/admin_backups/
        tar -xvf ${USERTYPE}.${CREATOR}.${USER}.tar.gz > /dev/null 2>&1
        rm ${USERTYPE}.${CREATOR}.${USER}.tar.gz
        # set ip address to local ip address
        CURRENT_IP="$(cat backup/user.conf | grep "ip=" | cut -d= -f2)"
        sed -i -e "s/${CURRENT_IP}/${LOCAL_IPADDRESS}/g" backup/user.conf
        echo "${LOCAL_IPADDRESS}" > backup/ip.list
        # create new tar.gz file before running import
        tar -czvf ${USERTYPE}.${CREATOR}.${USER}.tar.gz backup > /dev/null 2>&1
        rm -rf backup && cd
        # import backup
        echo "${BACKUP_IMPORT_COMMAND}" >> /usr/local/directadmin/data/task.queue
    fi

    # sync user files (only when user's home and domains directory exists)
    if [[ "${SYNC_HOMEDIR}" == "true" ]]; then
        echo -e "\n[ ${YELLOW}Homedir${RESET} ] sync [ ${YELLOW}/home/${USER}/${RESET} ]\n"
        while [[ ! -d /home/"${USER}"/domains ]];
        do
            echo -e "Home directory for ${YELLOW}${USER}${RESET} does not yet exist. Waiting for DirectAdmin backup import to complete."
            sleep 1;
        done
        # extra check to make sure the user variable is not empty
        if [[ -z "${USER}" ]]; then
            echo -e "[ ${RED}Warning${RESET} ] no user(s) entered. Skip syncing homedir."
        else
            if [[ "${SSH_PASSWORD}" == "true" ]]; then
                /usr/bin/sshpass -p "${SSH_PASS}" /usr/bin/rsync -a -p root@"${SOURCE}":/home/${USER}/ /home/${USER}/ --delete
            else
                /usr/bin/rsync -a -p root@"${SOURCE}":/home/${USER}/ /home/${USER}/ --delete
            fi
        fi
    fi

    # sync databases
    if [[ "${SYNC_DATABASES}" == "true" ]]; then
        if [[ "${SSH_PASSWORD}" == "true" ]]; then
            USER_DATABASE="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "/usr/local/mysql/bin/mysql --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} -e 'show databases;' | grep ${USER}" 2>&1 | grep -v 'Using a password on the command line interface can be insecure')"
        else
            USER_DATABASE="$(ssh root@"${SOURCE}" "/usr/local/mysql/bin/mysql --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} -e 'show databases;' | grep ${USER}" 2>&1 | grep -v 'Using a password on the command line interface can be insecure')"
        fi
        # only sync database if one is found
        if [[ "${USER_DATABASE}" ]]; then
            for DATABASE in ${USER_DATABASE}
            do
                # extra check to make sure database var is not empty
                if [[ -z "${DATABASE}" ]]; then
                    echo -e "\n[ ${RED}Error${RESET} ] Database variable can't be empty. Script will now abort.\n"
                    exit
                else
                    echo -e "[ ${YELLOW}Database${RESET} ] import [ ${YELLOW}${DATABASE}${RESET} ]"
                    /usr/local/mysql/bin/mysql --user=${LOCAL_SQL_USER} --password=${LOCAL_SQL_PASSWORD} -e "drop database ${DATABASE};" > /dev/null 2>&1
                    /usr/local/mysql/bin/mysql --user=${LOCAL_SQL_USER} --password=${LOCAL_SQL_PASSWORD} -e "create database ${DATABASE};" > /dev/null 2>&1
                    if [[ "${SSH_PASSWORD}" == "true" ]]; then
                        /usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" /usr/local/mysql/bin/mysqldump --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} --skip-triggers --opt --lock-tables=false --force ${DATABASE} 2>&1 | grep -v "Using a password on the command line interface can be insecure" | /usr/local/mysql/bin/mysql --user=${LOCAL_SQL_USER} --password=${LOCAL_SQL_PASSWORD} -D ${DATABASE} 2>&1 | grep -v "Using a password on the command line interface can be insecure"
                    else
                        ssh root@"${SOURCE}" /usr/local/mysql/bin/mysqldump --user=${REMOTE_SQL_USER} --password=${REMOTE_SQL_PASSWORD} --skip-triggers --opt --lock-tables=false --force ${DATABASE} 2>&1 | grep -v "Using a password on the command line interface can be insecure" | /usr/local/mysql/bin/mysql --user=${LOCAL_SQL_USER} --password=${LOCAL_SQL_PASSWORD} -D ${DATABASE} 2>&1 | grep -v "Using a password on the command line interface can be insecure"
                    fi
                fi
            done
        fi
    fi

    # set php version to same as source
    if [[ "${MULTIPLE_PHP}" == "true" ]]; then
        for DOMAIN in $(cat /usr/local/directadmin/data/users/${USER}/domains.list)
        do
            PHP1_LOCAL=`grep -r 'php1_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2`
            PHP2_LOCAL=`grep -r 'php2_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2`
            if [[ "${SSH_PASSWORD}" == "true" ]]; then
                PHP1_REMOTE="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "grep -r 'php1_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2")"
                PHP2_REMOTE="$(/usr/bin/sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no root@"${SOURCE}" "grep -r 'php2_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2")"
            else
                PHP1_REMOTE="$(ssh root@"${SOURCE}" "grep -r 'php1_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2")"
                PHP2_REMOTE="$(ssh root@"${SOURCE}" "grep -r 'php2_select=' /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf | cut -d= -f2")"
            fi
                if [[ "${PHP1_LOCAL}" ]]; then
                    sed -i -e "s/php1_select=${PHP1_LOCAL}/php1_select=${PHP1_REMOTE}/g" /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf
                    sed -i -e "s/php2_select=${PHP2_LOCAL}/php2_select=${PHP2_REMOTE}/g" /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf
                else
                    echo "php1_select=${PHP1_REMOTE}" >> /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf
                    echo "php2_select=${PHP2_REMOTE}" >> /usr/local/directadmin/data/users/${USER}/domains/${DOMAIN}.conf
                fi
        done
    fi

    # sync completed
    END_USERSYNC_TIME="$(date +"%s")"
    DIFFTIMEUSERSYNC="$(($END_USERSYNC_TIME-$BEGIN_USERSYNC_TIME))"
    let "USERCOUNT += 1";
    echo -e "\n[ ${GREEN}${USERCOUNT}${RESET} - ${GREEN}${TOTALUSERS}${RESET} ] [ ${GREEN}${USER}${RESET} ] [ ${GREEN}Complete${RESET} ] [ ${GREEN}$(($DIFFTIMEUSERSYNC / 60)) minute(s) and $(($DIFFTIMEUSERSYNC % 60)) second(s)${RESET} ]\n"
done

# rewrite confs (needed to fix users selected php version)
if [[ "${MULTIPLE_PHP}" == "true" ]]; then
    cd /usr/local/directadmin/custombuild && ./build rewrite_confs > /dev/null 2>&1
fi

# sync /etc/virtual/whitelist_* files
if [[ "${SSH_PASSWORD}" == "true" ]]; then
    /usr/bin/sshpass -p "${SSH_PASS}" /usr/bin/rsync -a root@"${SOURCE}":/etc/virtual/whitelist_* /etc/virtual/
else
    /usr/bin/rsync -a root@"${SOURCE}":/etc/virtual/whitelist_* /etc/virtual/
fi

# end script
END_SCRIPT_TIME="$(date +"%s")"
DIFFTIME="$(($END_SCRIPT_TIME-$BEGIN_SCRIPT_TIME))"
echo -e "[ ${RED}Script took $(($DIFFTIME / 60)) minutes and $(($DIFFTIME % 60)) seconds to complete${RESET} ]\n"
exit
