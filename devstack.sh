#!/bin/bash

varpwd=`pwd`
project=${varpwd#/code/}
php_versions=("5.6" "7.0" "7.1")
mysql_versions=("5.5" "5.6" "5.7")
ngrok_id=""
active="${varpwd}/_docker/.active"
public="${varpwd}/_docker/.public"
action=''
forcerestart='0'
no_ansi=''

php_repos=(
	'5.6::phpdockerio/php56-fpm;;latest'
	'7.0::phpdockerio/php7-fpm;;latest'
	'7.1::phpdockerio/php71-fpm;;latest'
)

php_extensions=(
	'5.6::php5-mysql php5-gd'
	'7.0::php7.0-mysql php7.0-gd php7.0-mbstring'
	'7.1::php7.1-mysql php7.1-gd php7.1-mbstring'
)

# Make sure Docker is installed for this project
if [ ! -d _docker ]; then
	mkdir -p _docker
fi

if [ "$1" = "restart" ]; then
	forcerestart='1';
fi

if [ "$2" == "--noansi" ]; then
	no_ansi='--no-ansi'
fi

# Find out if we're already running a stack and if so, shut it down
if [[ -f $active ]]
then
	running=$(<${active})
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
			docker-compose -f ${varpwd}/_docker/docker-compose.yml ${no_ansi} stop;
			echo "Stack shut down!"
			echo "---------------------------------------------"
			printf "\n"
			exit;
		fi

		if [[ $forcerestart == '0' ]]
		then
			# Ask the user what action they want to take (only if a stack is running)
			read -p "Action ([R]un, [s]top): " action
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

		docker-compose -f ${varpwd}/_docker/docker-compose.yml stop
		echo "Stack shut down"

		# Truncate our active file so we don't misreport a running stack.
		# echo '' > ${varpwd}/_docker/.active
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
	touch ${varpwd}/_docker/.public
	current_public_folder=$(<${public})

	if [[ -z $current_public_folder ]]
	then
		public_folder_option="empty for none"
	else
		public_folder_option="[${current_public_folder}], [c]lear"
	fi

	read -p "Public Folder (${public_folder_option}): " public_folder
	read -p "PHP Version ([5.6], 7.0, 7.1): " php_version
	read -p "MySQL Version ([5.5], 5.6, 5.7): " mysql_version
	read -p "NGROK ([N]o, [y]es, [e]xisting): " use_ngrok

	# If they provided a public folder, write that to our file, otherwise use what's already there (or nothing)
	if [[ $public_folder ]]
	then
		if [[ $public_folder == 'c' ]]
		then
			public_folder=""
		fi

		echo ${public_folder} > ${varpwd}/_docker/.public
	else
		public_folder=${current_public_folder}
	fi

	if [[ $public_folder ]]
	then
		public_folder_path="/code/"${project}"/"${public_folder}
	else
		public_folder_path="/code/"${project}
	fi

	if [[ $use_ngrok == 'y' ]]
	then
		osascript -e 'tell application "Terminal" to do script "ngrok http '${project}'.test:80"'
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

# Make sure our nginx proxy for .dev urls is running.
if ! docker top nginx &>/dev/null
then
	docker build -t nginx-proxy-buffers /code/docker/_source/nginx-proxy &>/dev/null
	docker run -d --name nginx -p 80:80 -v /var/run/docker.sock:/tmp/docker.sock:ro nginx-proxy-buffers &>/dev/null || docker start nginx
fi

if [[ ! -z $running && $mysql_version && $mysql_version != $running_mysql_version ]]
then
	read -p "Do you want to transfer your working database ([N]o/[y]es): " transfer_database

	# Make our comparison case insensitive so we can validate their response
	shopt -s nocasematch

	# Validate whether they entered Yes or YES or Y or y.
	if [[ $transfer_database == "yes" || $transfer_database == "y" ]]
	then
		transfer_database="y"

		# Make sure the user understands we do not guarantee db integrity
		printf "\n************************************************"
		printf "\n*  WARNING: We do not guarantee DB integrity!  *"
		printf "\n************************************************"
		printf "\nPlease make a manual backup if you deem necessary before continuing!\n\n"

		read -p "Continue ([N]o/[y]es): " transfer_understand

		# Validate whether they entered Yes or YES or Y or y.
		if [[ $transfer_understand == "yes" || $transfer_understand == "y" ]]
		then
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

	docker-compose -f ${varpwd}/_docker/docker-compose.yml stop
	echo "Stack shut down"
	echo "---------------------------------------------"
fi

# Create our active file and docker_mysql_ports file if it doesn't exist
touch ${varpwd}/_docker/.active
touch /code/docker_mysql_ports.json

# Log our current dev stack so we can shut it down later
echo ${active_string} > ${varpwd}/_docker/.active

mysql_port=$(sed -n 's/.*"\([0-9]*\)":{"project":"'${project}'"}.*/\1/p' /code/docker_mysql_ports.json)


# No mysql_port found so let's figure out which to use
if [[ ! -z $mysql_port ]]
then
	echo -e "Found existing MySQL Port: ${mysql_port}"
else
	echo "No existing MySQL Port found."
	echo "Looking for next available port."

	ports_string=$(</code/docker_mysql_ports.json)
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

	echo "Using MySQL Port: ${mysql_port}"

	# Add our new port to the ports listing.
	sed -i '' "s#}}}#},\"${mysql_port}\":{\"project\":\"${project}\"}}}#g" /code/docker_mysql_ports.json
fi

echo "---------------------------------------------"
echo "DB Connection Details:"
echo "  hostname: 127.0.0.1 (external)"
echo "  hostname: ${project}-mysql${mysql_version} (internal)"
echo "  username: root"
echo "  password: root_password"
echo "  database: ${project}"

# Create our docker-compose.yml file if it doesn't exist.
cp -f /code/docker/_source/docker-compose.yml ${varpwd}/_docker/docker-compose.yml

# Create our dockerfile
cp -f /code/docker/_source/Dockerfile ${varpwd}/_docker/Dockerfile

# Copy our nginx.conf file
cp -f /code/docker/_source/nginx.conf ${varpwd}/_docker/nginx.conf

# If the user has a custom nginx config file, use that instead of the default one.
if [[ -f ${varpwd}/_docker/nginx-custom.conf ]]
then
    nginx_conf_file="nginx-custom"
else
    nginx_conf_file="nginx"
fi

# Copy our PHP ini overrides ONLY if they don't already exist (so we don't override custom settings)
if [[ ! -f ${varpwd}/_docker/php-ini-overrides.ini ]]
then
    cp -f /code/docker/_source/php-ini-overrides.ini ${varpwd}/_docker/php-ini-overrides.ini
fi

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

# Replace the variables in our file with the stack we want to run.
sed -i '' "s#@@@PROJECT@@@#${project}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@PROJECT_PATH@@@#/code/${project}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@PHP_VERSION@@@#${php_version}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@MYSQL_VERSION@@@#${mysql_version}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@MYSQL_PORT@@@#${mysql_port}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@VIRTUAL_HOSTS@@@#${virtual_hosts}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@PHP_INI_FOLDER@@@#${php_ini_folder}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@NGINX_FILE@@@#${nginx_conf_file}#g" ${varpwd}/_docker/docker-compose.yml

# Replace the variables in our Dockerfile with the stack we want to run.
for index in "${php_repos[@]}" ; do
	repo_php="${index%%::*}"

	if [[ $repo_php == $php_version ]]
	then
		repo_string="${index##*::}"
		repo_repo="${repo_string%%;;*}"
		repo_tag="${repo_string##*;;}"

		sed -i '' "s#@@@PHP_REPO@@@#${repo_repo}#g" ${varpwd}/_docker/Dockerfile
		sed -i '' "s#@@@PHP_REPO_TAG@@@#${repo_tag}#g" ${varpwd}/_docker/Dockerfile
	fi
done

for index in "${php_extensions[@]}" ; do
	repo_php="${index%%::*}"

	if [[ $repo_php == $php_version ]]
	then
		repo_extensions="${index##*::}"

		sed -i '' "s#@@@PHP_EXTENSIONS@@@#${repo_extensions}#g" ${varpwd}/_docker/Dockerfile
	fi
done

sed -i '' "s#@@@PROJECT_PATH@@@#/code/${project}#g" ${varpwd}/_docker/Dockerfile

sed -i '' "s#@@@PROJECT@@@#${project}#g" ${varpwd}/_docker/nginx.conf
sed -i '' "s#@@@PROJECT_PUBLIC@@@#${public_folder_path}#g" ${varpwd}/_docker/nginx.conf
sed -i '' "s#@@@PHP_VERSION@@@#${php_version}#g" ${varpwd}/_docker/nginx.conf

echo "---------------------------------------------"
echo "Launching New Stack: PHP ${php_version} / MySQL ${mysql_version}"
echo "---------------------------------------------"

# Launch our new dev stack
docker-compose -f ${varpwd}/_docker/docker-compose.yml up -d #> /dev/null 2>&1

echo "Stack Launched!"
echo "http://${project}.localhost/"
echo "---------------------------------------------"
printf "\n"

# Rewrite the database connection settings
cat > ${varpwd}/_docker/docker.database.php <<- DatabaseContent
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

\$config['base_url'] = 'http://${project}.test/';
\$config['base_path'] = '/code/${project}/';
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