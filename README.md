# 3sixty-deployment
This projects got scripts to run 3sixty locally. The script downloads the necessary containers from the registry
and spin up 3sixty in your machine.

## Prerequisites
Please ensure you got Docker in you machine. It is tested in Docker 26.1.

## How to run 3sixty
Clone the project in your machine. You should already know the version of 3sixty.
For example, the version is 4.5.0. Then, Move to `scripts` directory and run below commands to spin up 3sixty.

````
$env:VERSION="4.5.0"
docker-compose up -d
````
If you got different version, please update the version accordingly. It should run 3sixty in your machine.

Please visit https://localhost:8443/3sixty-admin/login for 3sixty admin. And visit https://localhost:8444/3sixty-discovery/login
for 3sixty discovery.

An elastic search container is also run as part of this. If you do not need this, just change the docker-compose
script accordingly.

