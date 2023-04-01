#!/usr/bin/env bash
set -euo pipefail

docker compose down
docker compose up -d

RETRIES=60
MIN_POINT_COUNT=10

# shellcheck source=/dev/null
source .env

for i in $(seq 1 1 $RETRIES)
do
    FLUX_QUERY="from(bucket:\"$INFLUXDB_BUCKET\")
        |> range(start: -1m)
        |> filter(fn: (r) => r[\"_measurement\"] == \"$INFLUXDB_MEASUREMENT\")
        |> count()"

    POINT_COUNT=$(docker compose exec influxdb \
        influx query --raw \
            --org "$INFLUXDB_ORG" \
            --token "$INFLUXDB_TOKEN" \
            "$FLUX_QUERY" | grep ',0,' | awk -F',' '{print $6}' || true)

    echo "Measurement $INFLUXDB_MEASUREMENT contains $POINT_COUNT points."

    if [[ $POINT_COUNT =~ ^[0-9]+$ && $POINT_COUNT -ge $MIN_POINT_COUNT ]];
    then
        echo "Simulator is successfully ingesting data into InfluxDB."
        break
    else
        echo "Waiting for the Simulator.. Attempt [${i}/${RETRIES}]"
        if [ "$i" = $RETRIES ];
        then
            echo "Found less than ${MIN_POINT_COUNT} points in measurement $INFLUXDB_MEASUREMENT"
            docker compose logs telegraf
            docker compose down
            exit 1
        else
            sleep 1
        fi
    fi
done

docker compose down