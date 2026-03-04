#!/bin/sh

PROJECTS="FlorentinaTilea watchtower HBBR HBBS Tautulli"

for PROJECT in $PROJECTS; do
    # List all containers that start with PROJECT_
    containers=$(docker ps -a --filter "name=${PROJECT}" --format "{{.Names}}")

    # Skip if no containers found (project not deployed)
    [ -z "$containers" ] && continue

    for c in $containers; do
        state=$(docker inspect -f '{{.State.Running}}' "$c")

        if [ "$state" != "true" ]; then
            synodsmnotify @administrators "Container stopped" \
                "Container $c from project $PROJECT is not running."
#        else
#            # Debug path
#            echo "DEBUG: $c from $PROJECT is running"
        fi
    done
done
