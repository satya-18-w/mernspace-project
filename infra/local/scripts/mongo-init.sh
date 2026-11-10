#!/bin/sh
set -e

mongosh --host mongo --quiet /scripts/mongo-init.js

until mongosh --host mongo --quiet --eval 'db.hello().isWritablePrimary' | grep -q true; do
    sleep 2
done

echo "MongoDB replica set is ready."
