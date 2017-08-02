#!/bin/bash
#
# FIXME - add a one-line description of what this script is supposed to test
#
# FIXME - possibly add a more verbose multi-line description here. Not
# strictly necessary but possibly helpful to future maintainers. You
# could, e.g., include a BZ ID and/or a description of the behavior
# this test script is intended to check.
#

###############################################################################
# BEGIN setup
#
# You probably don't want to touch anything here, but you may want
# to skim it to see the available helper functions
#

# Don't touch. This lets the docker() wrapper log debug statements
# to original stdout, while also preserving a context-specific stdout
exec 5>&1

# In case you need a temp dir, e.g. for bind mounts or Dockerfiles
TMPDIR=$(mktemp -d --tmpdir docker-test-sample.XXXXXXXX)
if [ -z "$DEBUG" ]; then
    trap 'cd /;/bin/rm -rf $TMPDIR' 0
fi

# Docker image on which to test. This will probably be overridden in ADEPT.
IMG=centos

die() {
    echo "$*" >&2
    exit 1
}

# Helper for the helpers: returns a full path to a stdout or stderr log file
LOG_COUNTER=0
commandlog() {
    printf "%s/log.%s.%02d" $TMPDIR "$1" $LOG_COUNTER
}

# When debugging failed tests, it is crucial to know the exact commands
# that were run. This is a trivial wrapper on the docker command. It:
#
#    * emits its full arguments to stdout, in a way that the docker-autotest
#      caller will detect and log for human readers;
#    * invokes docker with those arguments, but logs stdout and stderr
#      to temp files
#    * outputs stderr, if any, to caller's stderr
#    * outputs stdout to caller's stdout
#    * returns with docker's exit status
#
# FIXME-QE: refactor to make it reusable for kpod, buildah; not just docker
#
docker() {
    echo "DEBUG:docker $@" >&5

    LOG_COUNTER=$(expr $LOG_COUNTER + 1)

    log_stdout=$(commandlog stdout)
    log_stderr=$(commandlog stderr)

    command docker "$@" >$log_stdout 2>$log_stderr
    docker_status=$?

    cat $log_stderr >&2
    cat $log_stdout

    return $docker_status
}

# Helper function: tests for presence of given string in docker output
# stream (default: stdout), aborts with diagnostic if absent.
expect_string() {
    local expect=$1
    local stream=${2:-stdout}
    local logfile=$(commandlog $stream)

    grep "$expect" $logfile && return

    die "TEST_FAIL:Did not find expected string '$expect' in $stream '$(<$logfile)'"
}

# Helper function: opposite of the above. Tests for presence of given string
# in docker output stream (default: stdout), aborts if string is present.
die_if_string_present() {
    local string=$1
    local stream=${2:-stdout}
    local logfile=$(commandlog $stream)

    found=$(grep "$string" $logfile)
    test -z "$found" && return

    die "TEST_FAIL:Found unwanted string '$string' in $stream: '$found'"
}

# FIXME-QE: if needed, add equivalents for regex
# FIXME-QE: if needed, add non-die equivalents so further tests can proceed
# FIXME-QE: if needed, add docker_require(), return TEST_NA if version < wanted

# END   setup
###############################################################################
# BEGIN single docker command
#
# This section is for tests that can be run with a single docker command
# that terminates immediately and whose output or exit status can be
# checked. See later below for commands that require a detached docker
# command that you can interact with.

# Run a command that's expected to terminate, e.g.:
#
#   mkdir $TMPDIR/mysubd; docker -v $TMPDIR/mysubd:/xyz run $IMG ls -lZd /xyz
#   docker ps -a
#   docker --userns=host run $IMG /bin/crashme
#   storage_stuff=$(docker info | grep -A3 'Storage Driver')
#   ...

docker run --rm -v $TMPDIR/nonexistent-subdir:/mumble $IMG date || die

# Check for errors in output; also make sure our desired output is present
die_if_string_present "Error running date command"
expect_string "Today is the first day of the rest of your life"

# END   single docker command
###############################################################################
# BEGIN detached docker command
#
# Use this for starting a detached container, then interacting with it.
# For instance: sending signals, or engaging with a server.

CID=$(docker run -d $IMG bash -c 'while :;do date; sleep 2;done')

# FIXME: interact with container
count1=$(docker logs $CID | wc -l)
sleep 5
count2=$(docker logs $CID | wc -l)

if [ $count1 -eq $count2 ]; then
    die "TEST_FAIL:docker-logs output did not grow"
fi

# Clean up.
docker kill $CID
docker rm $CID

# END   detached docker command
###############################################################################

exit 0
