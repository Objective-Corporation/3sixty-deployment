# 3sixty-deployment
This projects got scripts to run 3sixty locally. The script downloads the necessary containers from the registry
and spin up 3sixty in your machine.

## Prerequisites
Please ensure that you got Docker in you machine. It is tested in Docker 26.1. Also, your github user needs permission
to download the container. Please contact 3sixty team to get necessary permission.

## How to run 3sixty
Clone the project to your machine. You should already be aware of the 3sixty version to use. 
If not, please reach out to the 3sixty team for confirmation. Assuming the version is 4.5.0, 
navigate to the `scripts` directory and run the following commands to spin up 3sixty.

````
$env:VERSION="4.5.0"
docker-compose up -d
````
If you got different version, please update the version accordingly.

Please visit https://localhost:8443/3sixty-admin/login for 3sixty admin. And visit https://localhost:8444/3sixty-discovery/login
for 3sixty discovery.

An elastic search container is also run as part of this. If you do not need this, just change the docker-compose
script accordingly.

