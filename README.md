#Docker Dev Stack

## Overview
### What is this?
At it's core, this is just a BASH script that creates the files necessary to setup a local development stack (devstack) for Docker for Mac (PHP, MySQL, and Nginx, Apache coming soon).

### Can't I just run Docker for Mac?
Yes, you can. But if you're familiar with Docker, each service runs as it's own container and you have to link all the other containers your running together. This isn't hard persay, but it can be confusing to get up to speed on how everything needs to work and is extremely tedious to do manually.

### I already have MAMP/Homestead/Valet/Other, why do I need this?
Those other options are great and they may be better for your needs but for us, they didn't address the issues we were encountering so we built this! With this system, you can setup a project in seconds and change it from PHP 5.6 and MySQL 5.5 to PHP 7.1 and MySQL 5.7 and back again without any messy configuration.

If you're working on a site upgrade from EE2 to EE4 and you need to switch to PHP 7 after the upgrade, doing that on one of those other stacks may be time consuming or outright impossible without affecting all of your sites.

### What do you mean "without affecting all of your sites"?
This system creates a separate devstack for each of your projects. You want Project A on PHP 5.6 and MySQL 5.5 while Project B is on PHP 7.1 and MySQL 5.7? That's fine. You want to be able to delete Project A from your system entirely without affecting Project B? That's also fine.

### So what does this "devstack" script actually do?
When you run this script from the root folder of your project, it will prompt you to enter your project's public folder (if you have one), the PHP version you want, the MySQL version you want, and whether you want to setup a NGROK connection (exterior access for testing webhooks and such).

Once you have entered your choices, it'll create the following files:
  - `[your project]/_docker` folder
  - `[your project]/_docker/docker-compose.yml`
  - `[your project]/_docker/Dockerfile`
  - `[your project]/_docker/nginx.conf`
  - `[your project]/_docker/php-ini-overrides.ini`
  - `[your project]/docker.database.php`

### What is that `docker.database.php` file?
When you change your devstack, it changes the connection details for your database. To make it so you don't have to edit your ExpressionEngine config each time, you can just include that file in your config (or master config) at the bottom like so:
  - `include FCPATH.'docker.database.php';`

If your system folder is not in it's original position, you may need to add `../` or `../../` to get back to your project's root folder.

### What do I do if something goes wrong?
You can try reaching out to us but this is an unsupported project and we do not guarantee that you will receive a response.

### This system deleted my files/databse!
You use this setup at your own risk. We have made efforts to make it easy to use but as with any dev system, if you have critical data you cannot lose, you should have backups of it!

## Environment

- Your code MUST live in `/code` at the root of your hard drive. This is for consistency among developers. We may change this in the future but for now, that's how it is.

## Installation

- Install [Docker CE for Mac](https://www.docker.com/products/docker#/mac)
- Run Docker
- Edit `Docker Preferences > File Sharing` and add your `/code` folder
- Remove `/Users` from File Sharing
- Do **NOT** remove any other existing shared folders
- Click "Apply and Restart" button
- Install Kitematic from the Docker menu item (DO NOT download Docker Toolbox!)
- Clone this repo into `/code/docker`
- Make the script globally accessible by creating a symlink using the following terminal command
  - ln -sf /code/docker/devstack.sh /usr/local/bin/devstack

## Usage / Launching A Project
- `cd` into your `/code/[project name]` folder
- Type `devstack`
- Choose your Public Folder / PHP / MySQL / NGROK settings