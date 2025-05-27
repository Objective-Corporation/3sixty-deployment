#!/bin/bash
set -euo pipefail

export MONGO_INITDB_DATABASE=${MONGO_INITDB_DATABASE:="dbtest"}
export MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME:="dbuser"}
export MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD:="dbpassword"}

mongosh <<EOJS
    use $MONGO_INITDB_DATABASE
    db = new Mongo().getDB("$MONGO_INITDB_DATABASE");
    db.createUser(
        {
            "user": "$MONGO_INITDB_ROOT_USERNAME",
            "pwd": "$MONGO_INITDB_ROOT_PASSWORD",
            "roles": ["readWrite", "dbAdmin"]
        }
    );
    db.grantRolesToUser("$MONGO_INITDB_ROOT_USERNAME", [
        {
            role: "clusterMonitor", db: "admin"
        }]
    );
EOJS
