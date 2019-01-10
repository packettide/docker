#!/bin/bash

scriptDirectory=`dirname $(readlink ${BASH_SOURCE[0]})`

# Load our ENV vars.
cp -n $scriptDirectory/.env.example $scriptDirectory/.env
source $scriptDirectory/.env

# Backwards compatibility for ENV changes.
if [[ ! $TLD && $tld ]]; then TLD=${tld}; fi
if [[ ! $DOCKER_FOLDER ]]; then DOCKER_FOLDER='_docker'; fi
if [[ ! $SITES_FOLDER ]]; then SITES_FOLDER='/code/sites/'; fi
if [[ ${SITES_FOLDER: -1} != '/' ]]; then SITES_FOLDER="${SITES_FOLDER}/"; fi
if [[ ! $MYSQL_PORTS_FILE ]]; then MYSQL_PORTS_FILE='/code/docker_mysql_ports.json'; fi

varpwd=`pwd`
project=${varpwd#${SITES_FOLDER}}
php_versions="5.6, 7.0, 7.1, 7.2"
mysql_versions="5.5, 5.6, 5.7"
server_types="[n]ginx, [a]pache"
ngrok_id=""
active_file="${varpwd}/${DOCKER_FOLDER}/.active"
public_file="${varpwd}/${DOCKER_FOLDER}/.public"
server_file="${varpwd}/${DOCKER_FOLDER}/.server"
action=''
forcerestart='0'
no_ansi=''

bold=$(tput bold)
normal=$(tput sgr0)

# Remove the leading slash if present.
if [[ ${project:0:1} == '/' ]]; then project=${project:1}; fi

php_apache_repos=(
    '5.3::bylexus/apache-php53;;latest'
    '5.5::bylexus/apache-php55;;latest'
    '5.6::nimmis/apache-php5;;latest'
    '7.0::nimmis/apache-php7;;latest'
    '7.1::nimmis/apache-php7;;latest'
    '7.2::nimmis/apache-php7;;latest'
)

php_repos=(
	'5.6::phpdockerio/php56-fpm;;latest'
	'7.0::phpdockerio/php7-fpm;;latest'
	'7.1::phpdockerio/php71-fpm;;latest'
    '7.2::phpdockerio/php72-fpm;;latest'
)

php_extensions=(
	'5.6::php5-mysql php5-gd'
	'7.0::php7.0-mysql php7.0-gd php7.0-mbstring php7.0-xml'
	'7.1::php7.1-mysql php7.1-gd php7.1-mbstring php7.1-bcmath php7.1-xml'
    '7.2::php7.2-mysql php7.2-gd php7.2-mbstring php7.2-bcmath php7.2-xml'
)

# Make sure Docker is installed for this project
if [ ! -d ${DOCKER_FOLDER} ]; then
	mkdir -p ${DOCKER_FOLDER}
fi

if [ "$1" = "restart" ]; then
	forcerestart='1';
fi

if [ "$2" == "--noansi" ]; then
    no_ansi='--no-ansi'
fi

while getopts p:m:f option
do
    case "${option}"
    in
        p) php_version=${OPTARG};;
        m) mysql_version=${OPTARG};;
        f) force_defaults="1";;
    esac
done

# If we don't have a current server file set already, create one.
if [[ ! -f $server_file ]]
then
    touch ${varpwd}/${DOCKER_FOLDER}/.server
    echo "nginx" > ${varpwd}/${DOCKER_FOLDER}/.server
fi

# Read the server file. It should always exist at this point.
server=$(<${server_file})

# If the server file is empty, set our default server.
if [[ ! $server ]]
then
    server="nginx"
fi

# Find out if we're already running a stack and if so, shut it down
if [[ -f $active_file ]]
then
    running=$(<${active_file})
    running_php_version=`expr "${running}" : 'php\([0-9\.]*\)mysql.*'`
    running_mysql_version=`expr "${running}" : '.*mysql\([0-9]\.[0-9]*\)'`

	if [[ ! -z $running ]]
	then
		printf "\n"
		echo "---------------------------------------------"
		echo "Current Stack: PHP ${running_php_version} / MySQL ${running_mysql_version}"
		echo "---------------------------------------------"

		# If the first argument is stop, just bring the container down (i.e. "devstack stop").
		if [ "$1" = "stop" ]; then
			echo "Shutting down..."
			docker-compose -p '${project}' -f ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml ${no_ansi} stop;
			echo "Stack shut down!"
			echo "---------------------------------------------"
			printf "\n"
			exit;
		fi

		if [[ $forcerestart == '0' ]]
		then
			# Ask the user what action they want to take (only if a stack is running)
            if [[ $force_defaults != "1" ]]; then
                read -p "Action (${bold}[R]un${normal}, [s]top): " action
            fi
		fi
	fi
fi

# Argument is "stop" but we weren't even running. Just exit because it is already stopped.
if [ "$1" = "stop" ]; then
	echo "Container was not running. Success.";
	exit;
fi

# Make our comparison case insensitive so we can validate their response
shopt -s nocasematch

if [[ $action == 'stop' || $action == 's' ]]
then
	if [[ ! -z $running ]]
	then
		echo "Shutting down..."

		docker-compose -p '${project}' -f ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml stop
		echo "Stack shut down"

		# Truncate our active file so we don't misreport a running stack.
		# echo '' > ${varpwd}/${DOCKER_FOLDER}/.active
		exit
	else
		echo "FAILED: No stack currently running."
		exit
	fi
fi

if [[ $forcerestart == '0' ]]
then
	shopt -u nocasematch

	# Create our .public file if it doesn't exist
	touch ${varpwd}/${DOCKER_FOLDER}/.public
	current_public_folder=$(<${public_file})

	if [[ -z $current_public_folder ]]
	then
		public_folder_option="${bold}none${normal}"
	else
		public_folder_option="${bold}${current_public_folder}${normal}, [c]lear"
	fi

    # Highlight the current or default web server version
    if [[ $server == 'apache' ]]
    then
        server_type_options=${server_types/\[a\]pache/${bold}[a]pache${normal}}
    else
        server_type_options=${server_types/\[n\]ginx/${bold}[n]ginx${normal}}
    fi

    # Highlight the current or default PHP version
    if [[ $running_php_version ]]
    then
        php_version_options=${php_versions/$running_php_version/${bold}[$running_php_version]${normal}}
    else
        php_version_options=${php_versions/5.6/${bold}[5.6]${normal}}
    fi

    # Highlight the current or default MySQL version
    if [[ $running_mysql_version ]]
    then
        mysql_version_options=${mysql_versions/$running_mysql_version/${bold}[$running_mysql_version]${normal}}
    else
        mysql_version_options=${mysql_versions/5.5/${bold}[5.5]${normal}}
    fi

    if [[ $force_defaults != "1" ]]; then
        read -p "Public Folder (${public_folder_option}): " public_folder
        read -p "Nginx or Apache (${server_type_options}): " which_server
    	read -p "PHP Version (${php_version_options}): " php_version
    	read -p "MySQL Version (${mysql_version_options}): " mysql_version
    	read -p "NGROK (${bold}[N]o${normal}, [y]es, [e]xisting): " use_ngrok
    fi

    if [[ $which_server == 'A' || $which_server == 'a' || $which_server == 'apache' ]]; then
        server="apache"
    elif [[ $which_server == 'N' || $which_server == 'n'  || $which_server == 'nginx' ]]; then
        server="nginx"
    fi

	# If they provided a public folder, write that to our file, otherwise use what's already there (or nothing)
	if [[ $public_folder ]]
	then
		if [[ $public_folder == 'c' ]]
		then
			public_folder=""
		fi

		echo ${public_folder} > ${varpwd}/${DOCKER_FOLDER}/.public
	else
		public_folder=${current_public_folder}
	fi

	if [[ $public_folder ]]
	then
		public_folder_path="${SITES_FOLDER}"${project}"/"${public_folder}
	else
		public_folder_path="${SITES_FOLDER}"${project}
	fi

	if [[ $use_ngrok == 'y' ]]
	then
		osascript -e 'tell application "Terminal" to do script "ngrok http '${project}'.'${TLD}':80"'
	fi

	if [[ $use_ngrok == 'y' || $use_ngrok == 'e' ]]
	then
		read -p "Enter NGROK ID (ex: a8d685ca): " ngrok_id
	fi
fi

# If we just hit enter instead of entering a value for PHP and MySQL, use what's set for the current stack.
if [[ $running_php_version && ! $php_version ]]
then
	php_version=${running_php_version}
fi

if [[ $running_mysql_version && ! $mysql_version ]]
then
	mysql_version=${running_mysql_version}
fi

# Double fallback in case we're not running anything and nothing was entered.
php_version=${php_version:-5.6}
mysql_version=${mysql_version:-5.5}

# If we're running a stack, the user entered a mysql_version, and that version doesn't
# match the one we're running, ask the user if they want to transfer their db.
transfer_database="n"

# If we're using ngrok, add the ngrok subdomain into our virtual_hosts
if [[ $use_ngrok == 'y' || $use_ngrok == 'e' ]]
then
    virtual_hosts="${project}.dev,${project}.test,${project}.localhost,${ngrok_id}.ngrok.io"
else
    virtual_hosts="${project}.dev,${project}.test,${project}.localhost"
fi

if [[ $php_version == '5.6' ]]
then
    php_ini_folder="php5"
else
    php_ini_folder="php/${php_version}"
fi

# Make sure our nginx proxy for .dev urls is running.
if ! docker top nginx &>/dev/null
then
	docker build -t nginx-proxy-buffers /code/docker/_source/nginx-proxy &>/dev/null
	docker run -d --name nginx -p 80:80 -v /var/run/docker.sock:/tmp/docker.sock:ro nginx-proxy-buffers &>/dev/null || docker start nginx
fi

if [[ ! -z $running && $mysql_version && $mysql_version != $running_mysql_version ]]
then
    if [[ $force_defaults != "1" ]]; then
    	read -p "Do you want to transfer your working database ([N]o/[y]es): " transfer_database
    fi

	# Make our comparison case insensitive so we can validate their response
	shopt -s nocasematch

	# Validate whether they entered Yes or YES or Y or y.
	if [[ $transfer_database == "yes" || $transfer_database == "y" ]]; then
		transfer_database="y"

		# Make sure the user understands we do not guarantee db integrity
		printf "\n************************************************"
		printf "\n*  WARNING: We do not guarantee DB integrity!  *"
		printf "\n************************************************"
		printf "\nPlease make a manual backup if you deem necessary before continuing!\n\n"

        if [[ $force_defaults != "1" ]]; then
    		read -p "Continue ([N]o/[y]es): " transfer_understand
        fi

		# Validate whether they entered Yes or YES or Y or y.
		if [[ $transfer_understand == "yes" || $transfer_understand == "y" ]]; then
			printf "\nExporting current database (MySQL ${running_mysql_version}) to ${project}.sql...\n"

			# Export the current DB to a temp working file using the Docker exec to access mysql directly.
			docker exec ${project}-mysql${running_mysql_version} mysqldump --user="root" --password="root_password" ${project} > docker_db_backup.sql

			printf "Export Complete.\n\n"
		fi
	else
		transfer_database="n"
	fi
	shopt -u nocasematch
fi

active_string="php${php_version}mysql${mysql_version}"

echo "---------------------------------------------"

if [[ ! -z $running ]]
then
	echo "Shutting down..."

	docker-compose -p '${project}' -f ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml stop
	echo "Stack shut down"
	echo "---------------------------------------------"
fi

# Create our active file and docker_mysql_ports file if it doesn't exist
touch ${varpwd}/${DOCKER_FOLDER}/.active
touch ${varpwd}/${DOCKER_FOLDER}/.server
touch ${MYSQL_PORTS_FILE}

# Log our current dev stack so we can shut it down later
echo ${active_string} > ${varpwd}/${DOCKER_FOLDER}/.active
echo ${server} > ${varpwd}/${DOCKER_FOLDER}/.server

mysql_port=$(sed -n 's/.*"\([0-9]*\)":{"project":"'${project}'"}.*/\1/p' ${MYSQL_PORTS_FILE})

# No mysql_port found so let's figure out which to use
if [[ ! -z $mysql_port ]]
then
	echo -e "Found existing MySQL Port: ${mysql_port}"
else
	echo "No existing MySQL Port found."
	echo "Looking for next available port."

	ports_string=$(<${MYSQL_PORTS_FILE})
	IFS=,
	ary=($ports_string)

	# Try to find the next port to use. If there are none, start at the beginning!
	mysql_port=3306

	for key in "${!ary[@]}";
	do
		found_port=$(sed -n 's/.*"\([0-9]*\)":{"project":.*/\1/p' <<< ${ary[$key]})

		if (( found_port > mysql_port )); then
			mysql_port=$found_port
		fi
	done

	if [[ ! -z $found_port ]]
	then
		echo "Last port used: ${found_port}"
	else
		echo "No previous MySQL Ports found"
	fi

	mysql_port=$[mysql_port + 1]

	# Add our new port to the ports listing.
    sed -i '' "s#}}}#},\"${mysql_port}\":{\"project\":\"${project}\"}}}#g" ${MYSQL_PORTS_FILE}
fi

echo "---------------------------------------------"
echo "DB Connection Details:"
echo "  hostname: 127.0.0.1 (external)"
echo "  hostname: ${project}-mysql${mysql_version} (internal)"
echo "  username: root"
echo "  password: root_password"
echo "  database: ${project}"



# Copy our PHP ini overrides ONLY if they don't already exist (so we don't override custom settings)
if [[ ! -f ${varpwd}/${DOCKER_FOLDER}/php-ini-overrides.ini ]]
then
    cp -f /code/docker/_source/php-ini-overrides.ini ${varpwd}/${DOCKER_FOLDER}/php-ini-overrides.ini
fi

# If we're using ngrok, add the ngrok subdomain into our virtual_hosts
if [[ $use_ngrok == 'y' || $use_ngrok == 'e' ]]
then
    virtual_hosts="${project}.dev,${project}.${TLD},${project}.localhost,${ngrok_id}.ngrok.io"
else
    virtual_hosts="${project}.dev,${project}.${TLD},${project}.localhost"
fi

# Create our docker-compose.yml file if it doesn't exist.
cp -f /code/docker/_source/docker-compose-${server}.yml ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml

# Create our Dockerfile
# If the user has a custom Dockerfile, use that instead of the default one.
if [[ -f ${varpwd}/${DOCKER_FOLDER}/Dockerfile-php${php_version}-custom ]]
then
    echo "${bold}Dockerfile-php${php_version}-custom found, using${normal}"
    cp -f ${varpwd}/${DOCKER_FOLDER}/Dockerfile-php${php_version}-custom ${varpwd}/${DOCKER_FOLDER}/Dockerfile
elif [[ -f ${varpwd}/${DOCKER_FOLDER}/Dockerfile-custom ]]
then
    echo "${bold}Dockerfile-custom found, using${normal}"
    cp -f ${varpwd}/${DOCKER_FOLDER}/Dockerfile-custom ${varpwd}/${DOCKER_FOLDER}/Dockerfile
else
    cp -f /code/docker/_source/Dockerfile-${server} ${varpwd}/${DOCKER_FOLDER}/Dockerfile
fi

# Replace the variables in our file with the stack we want to run.
sed -i '' "s#@@@PROJECT@@@#${project}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@PROJECT_PATH@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@PHP_VERSION@@@#${php_version}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@MYSQL_VERSION@@@#${mysql_version}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@MYSQL_PORT@@@#${mysql_port}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@VIRTUAL_HOSTS@@@#${virtual_hosts}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@PHP_INI_FOLDER@@@#${php_ini_folder}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
sed -i '' "s#@@@PROJECT_PATH@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile

if [[ $server == 'apache' ]]
then
    # Copy our apache.conf file
    if [[ -f /code/docker/_source/apache.conf ]]
    then
        cp -f /code/docker/_source/apache.conf ${varpwd}/${DOCKER_FOLDER}/apache.conf
    fi

    # If the user has a custom apache config file, use that instead of the default one.
    if [[ -f ${varpwd}/${DOCKER_FOLDER}/apache-php${php_version}-custom.conf ]]
    then
        apache_conf_file="apache-php${php_version}-custom"
    elif [[ -f ${varpwd}/${DOCKER_FOLDER}/apache-custom.conf ]]
    then
        apache_conf_file="apache-custom"
    else
        apache_conf_file="apache"
    fi

    sed -i '' "s#@@@APACHE_CONF_FILE@@@#${apache_conf_file}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
    sed -i '' "s#@@@PROJECT_PATH_SERVER@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/apache.conf
    sed -i '' "s#@@@PROJECT_PATH_SERVER@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
    sed -i '' "s#@@@PROJECT_PATH_SERVER@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile

    # Replace the variables in our Dockerfile with the stack we want to run.
    for index in "${php_apache_repos[@]}" ; do
        repo_php="${index%%::*}"

        if [[ $repo_php == $php_version ]]
        then
            repo_string="${index##*::}"
            repo_repo="${repo_string%%;;*}"
            repo_tag="${repo_string##*;;}"

            sed -i '' "s#@@@PHP_REPO@@@#${repo_repo}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile
            sed -i '' "s#@@@PHP_REPO_TAG@@@#${repo_tag}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile
            sed -i '' "s#@@@PHP_REPO@@@#${repo_repo}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
            sed -i '' "s#@@@PHP_REPO_TAG@@@#${repo_tag}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
        fi
    done
else
    # Copy our nginx.conf file
    cp -f /code/docker/_source/nginx.conf ${varpwd}/${DOCKER_FOLDER}/nginx.conf

    # If the user has a custom nginx config file, use that instead of the default one.
    if [[ -f ${varpwd}/${DOCKER_FOLDER}/nginx-php${php_version}-custom.conf ]]
    then
        nginx_conf_file="nginx-php${php_version}-custom"
        echo "NGINX: ${bold}nginx-php${php_version}-custom.conf${normal}"
    elif [[ -f ${varpwd}/${DOCKER_FOLDER}/nginx-custom.conf ]]
    then
        nginx_conf_file="nginx-custom"
        echo "NGINX: ${bold}nginx-custom.conf${normal}"
    else
        nginx_conf_file="nginx"
        echo "NGINX: ${bold}nginx.conf${normal}"
    fi

    sed -i '' "s#@@@NGINX_FILE@@@#${nginx_conf_file}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
    sed -i '' "s#@@@PROJECT@@@#${project}#g" ${varpwd}/${DOCKER_FOLDER}/nginx.conf
    sed -i '' "s#@@@PROJECT_PUBLIC@@@#${public_folder_path}#g" ${varpwd}/${DOCKER_FOLDER}/nginx.conf
    sed -i '' "s#@@@PHP_VERSION@@@#${php_version}#g" ${varpwd}/${DOCKER_FOLDER}/nginx.conf
    sed -i '' "s#@@@TLD@@@#${TLD}#g" ${varpwd}/${DOCKER_FOLDER}/nginx.conf
    sed -i '' "s#@@@PROJECT_PATH_SERVER@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/docker-compose.yml
    sed -i '' "s#@@@PROJECT_PATH_SERVER@@@#${SITES_FOLDER}${project}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile

    # Replace the variables in our Dockerfile with the stack we want to run.
    for index in "${php_repos[@]}" ; do
        repo_php="${index%%::*}"

        if [[ $repo_php == $php_version ]]
        then
            repo_string="${index##*::}"
            repo_repo="${repo_string%%;;*}"
            repo_tag="${repo_string##*;;}"

            sed -i '' "s#@@@PHP_REPO@@@#${repo_repo}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile
            sed -i '' "s#@@@PHP_REPO_TAG@@@#${repo_tag}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile
        fi
    done
fi

for index in "${php_extensions[@]}" ; do
    repo_php="${index%%::*}"

    if [[ $repo_php == $php_version ]]
    then
        repo_extensions="${index##*::}"

        sed -i '' "s#@@@PHP_EXTENSIONS@@@#${repo_extensions}#g" ${varpwd}/${DOCKER_FOLDER}/Dockerfile
    fi
done

echo "---------------------------------------------"
echo "Launching New Stack: PHP ${php_version} / MySQL ${mysql_version}"
echo "---------------------------------------------"

# If the user has a custom docker-compose file, use that instead of the default one.
if [[ -f ${varpwd}/${DOCKER_FOLDER}/docker-compose-php${php_version}-custom.yml ]]
then
    docker_compose_file="docker-compose-php${php_version}-custom"
    echo "Compose: ${bold}docker-compose-php${php_version}-custom.yml${normal}"
elif [[ -f ${varpwd}/${DOCKER_FOLDER}/docker-compose-custom.yml ]]
then
    docker_compose_file="docker-compose-custom"
    echo "Compose: ${bold}docker-compose-custom.yml${normal}"
else
    docker_compose_file="docker-compose"
    echo "Compose: ${bold}docker-compose.yml${normal}"
fi

# Launch our new dev stack
docker-compose -p '${project}' -f ${varpwd}/${DOCKER_FOLDER}/${docker_compose_file}.yml up -d #> /dev/null 2>&1

# If we have custom commands to run in the container afterward, do so.
if [[ -f ${varpwd}/${DOCKER_FOLDER}/docker-post-launch-php${php_version}.sh ]]
then
    echo "Post-Launch PHP: ${bold}docker-post-launch-php${php_version}.sh${normal}"
    chmod +x ${varpwd}/${DOCKER_FOLDER}/docker-post-launch-php${php_version}.sh
    ${varpwd}/${DOCKER_FOLDER}/docker-post-launch-php${php_version}.sh
elif [[ -f ${varpwd}/${DOCKER_FOLDER}/docker-post-launch.sh ]]
then
    echo "Post-Launch PHP: ${bold}docker-post-launch.sh${normal}"
    chmod +x ${varpwd}/${DOCKER_FOLDER}/docker-post-launch.sh
    ${varpwd}/${DOCKER_FOLDER}/docker-post-launch.sh
    #exec_commands=$(<${varpwd}/${DOCKER_FOLDER}/docker-post-launch.sh)
    #docker_command="docker exec ${project}-${server} ${exec_commands}"
    #eval $docker_command
fi

echo "---------------------------------------------"
echo "${bold}Stack Launched!${normal}"
echo "URL: ${bold}http://${project}.${TLD}/${normal}"
echo "MySQL Port: ${bold}${mysql_port}${normal}"
echo "---------------------------------------------"
printf "\n"

# Rewrite the database connection settings
cat > ${varpwd}/${DOCKER_FOLDER}/docker.database.php <<- DatabaseContent
<?php
// EE2 Format
\$db['expressionengine']['hostname'] = '${project}-mysql${mysql_version}';
\$db['expressionengine']['username'] = 'root';
\$db['expressionengine']['password'] = 'root_password';
\$db['expressionengine']['database'] = '${project}';

// EE3 Format
\$config['database']['expressionengine']['hostname'] = '${project}-mysql${mysql_version}';
\$config['database']['expressionengine']['username'] = 'root';
\$config['database']['expressionengine']['password'] = 'root_password';
\$config['database']['expressionengine']['database'] = '${project}';

\$config['base_url'] = 'http://${project}.${TLD}/';
\$config['site_url'] = 'http://${project}.${TLD}/';
\$config['base_path'] = '${SITES_FOLDER}${project}/';

if (file_exists(\$config['base_path'].'themes')) {
    \$config['theme_folder_url'] = \$config['base_url'].'themes/';
    \$config['theme_folder_path'] = \$config['base_path'].'themes/';
}
DatabaseContent

# If we chose to transfer our DB, import the new DB now
if [[ $transfer_database == "y" ]]
then
	printf "\nWaiting for MySQL Server to start...\n"

	sleep 5

	printf "\nImporting Transferred Database...\n"

	# Run the Docker command to access mysql directly and import the file we exported.
	docker exec -i ${project}-mysql${mysql_version} mysql --user="root" --password="root_password" ${project} < docker_db_backup.sql

	printf "\nImport Complete\n\n"
fi