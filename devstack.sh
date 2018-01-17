#!/bin/bash

varpwd=`pwd`
php_versions=("5.6" "7.0" "7.1")
mysql_versions=("5.5" "5.6" "5.7")
ngrok_id=""
active="${varpwd}/_docker/.active"
project_file="${varpwd}/_docker/docker.project"
project=$(<${project_file})
action=''
forcerestart='0'

# Make sure Docker is installed for this project
if [ ! -d _docker ]; then
	echo "Missing _docker folder"
	exit
fi

if [ "$1" = "restart" ]; then
	forcerestart='1';
fi

# Find out if we're already running a stack and if so, shut it down
if [[ -f $active ]]
then
	running=$(<${active})
	running_php_version=`expr "${running}" : 'php\([0-9\.]*\)mysql.*'`
	running_mysql_version=`expr "${running}" : '.*mysql\([0-9\.]*\).yml'`

	if [[ ! -z $running ]]
	then

		# If the first argument is stop, just bring the container down (i.e. "devstack stop").
		if [ "$1" = "stop" ]; then
			docker-compose -f ${varpwd}/_docker/${running} stop;
			#echo '' > ${varpwd}/_docker/.active;
			exit;
		fi

		if [[ $forcerestart == '0' ]]
		then
			# Ask the user what action they want to take (only if a stack is running)
			printf "\nCurrent Stack: php${running_php_version} mysql${running_mysql_version}\n"
			read -p "Action ([Run], Stop): " action
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

		docker-compose -f ${varpwd}/_docker/${running} stop
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

	read -p "Enter PHP Version ([5.6], 7.0, 7.1): " php_version
	read -p "Enter MySQL Version ([5.5], 5.6, 5.7): " mysql_version
	read -p "Use NGROK ([N]o/[y]es/[e]xisting): " use_ngrok

	if [[ $use_ngrok == 'y' ]]
	then
		osascript -e 'tell application "Terminal" to do script "ngrok http '${project}'.dev:80"'
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
	docker run -d --name nginx -p 80:80 -v /var/run/docker.sock:/tmp/docker.sock:ro jwilder/nginx-proxy &>/dev/null || docker start nginx
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

# composefile="php${php_version}mysql${mysql_version}.yml"
active_string="php${php_version}mysql${mysql_version}.yml"

if [[ ! -z $running ]]
then
	echo "Currently Running Stack: ${running}"
	echo "Shutting down..."

	docker-compose -f ${varpwd}/_docker/docker-compose.yml stop
	echo "Stack shut down"
fi

# Create our active file if it doesn't exist
touch ${varpwd}/_docker/.active

# Log our current dev stack so we can shut it down later
echo ${active_string} > ${varpwd}/_docker/.active

mysql_port=$(sed -n 's/.*"\([0-9]*\)":{"project":"'${project}'"}.*/\1/p' /code/docker_mysql_ports.json)


# No mysql_port found so let's figure out which to use
if [[ ! -z $mysql_port ]]
then
	echo "Found existing MySQL Port: "${mysql_port}
else
	echo "No existing MySQL Port found. Looking for next available port."

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
		echo "Last port used: "${found_port}
	else
		echo "No previous MySQL Ports found"
	fi

	mysql_port=$[mysql_port + 1]

	echo "Using MySQL Port: "${mysql_port}

	# Add our new port to the ports listing.
	sed -i '' "s#}}}#},\"${mysql_port}\":{\"project\":\"${project}\"}}}#g" /code/docker_mysql_ports.json
fi

# Create our docker-compose.yml file if it doesn't exist.
cp -f /code/tools/docker/_source/docker-compose.yml ${varpwd}/_docker/docker-compose.yml

# If we're using ngrok, add the ngrok subdomain into our virtual_hosts
if [[ $use_ngrok == 'y' || $use_ngrok == 'e' ]]
then
	virtual_hosts="${project}.dev,${project}.test,${project}.localhost,${ngrok_id}.ngrok.io"
else
	virtual_hosts="${project}.dev,${project}.test,${project}.localhost"
fi

# Replace the variables in our file with the stack we want to run.
sed -i '' "s#@@@PROJECT@@@#${project}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@PROJECT_PATH@@@#/code/${project}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@PHP_VERSION@@@#${php_version}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@MYSQL_VERSION@@@#${mysql_version}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@MYSQL_PORT@@@#${mysql_port}#g" ${varpwd}/_docker/docker-compose.yml
sed -i '' "s#@@@VIRTUAL_HOSTS@@@#${virtual_hosts}#g" ${varpwd}/_docker/docker-compose.yml

echo "Launching New Stack: PHP ${php_version} / MySQL ${mysql_version}"

# Launch our new dev stack
docker-compose -f ${varpwd}/_docker/docker-compose.yml up -d

# Rewrite the database connection settings
cat > ${varpwd}/docker.database.php <<- DatabaseContent
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