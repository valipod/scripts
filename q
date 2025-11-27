#!/bin/bash

#this waits for any PIDs to finish
anywait(){

    for pid in "$@"; do
        while kill -0 "$pid" 2&>1 >/dev/null; do
            sleep 0.5
        done
    done
}


PIDFILE=~/.q.pid

#open PIDFILE and aquire lock
exec 9>>$PIDFILE
flock -w2 9 || { echo "ERROR: flock() failed." >&2; exit 1; }

#read previous instances PID from PIDFILE and write own PID to PIDFILE
OLDPID=$(<$PIDFILE)
echo $$>$PIDFILE

#release lock
flock -u 9

#wait for OLDPID
anywait $OLDPID

#do stuff
"$@"


#afterwards: cleanup (if pidfile still contains own PID, truncate it)
flock -w2 9 || { echo "ERROR: flock() failed." >&2; exit 1; }
if [ $(<$PIDFILE) == $$ ]; then
truncate -s0 $PIDFILE
fi
flock -u 9
