#!/bin/zsh

# get_token.zsh
# This script gets an OAuth access token from an Azure AD app registration.
# It uses ncat to listen for the auth code, and jq to parse the JSON response.
# The script opens a browser window to start the OAuth flow, and captures the auth code when the flow completes.
# The script then uses the auth code to get an access token from the token endpoint.
# The access token is printed to stdout, i.e. returned to the caller, so you can 'token=$(./get_token.zsh)'.

debug_log() {
    if [ $debug -eq 1 ]; then
        print -P "%F{green}DEBUG: $1" >&2
    fi
}
error_log() {
    print -P "%F{red}ERROR: $1" >&2
}

if [ ! -f .env ]; then
    error_log ".env file not found. Aborting."
    exit 1
else
    source .env
    debug_log "loaded environment variables from .env"
fi

if [[ "$debug" -eq 1 ]]; then
    debug_log "debug logging enabled"
fi

if [[ "$verbose" -eq 1 ]]; then
    set -x
    print -P "%F{yellow}VERBOSE LOGGING ENABLED" >&2
fi

main() {
    debug_log "checking for required commands"
    check_command_dependency "ncat"
    check_command_dependency "curl"
    check_command_dependency "jq"
    debug_log "\n"

    # auth_endpoint is the url to start the oauth flow with the tenant id and path
    # token_endpoint is the url to get the access token with the tenant id and path
    # for our purposes they're the same, except
    # it's /authorize for the auth endpoint
    # and /token for the token endpoint

    # callback_endpoint is the url to redirect to after the oauth flow is complete,
    # e.g. http://localhost:12345/callback
    # this must be registered in the app registration as a valid redirect URI

    # token_querystring is the query string to pass to the auth endpoint,
    # plus the authcode to get the access token

    auth_endpoint="$oauth_host/$tenant_id/$oauth_path"
    token_endpoint="$oauth_host/$tenant_id/$oauth_token_path"
    callback_endpoint="$callback_host:$callback_port/$callback_path"
    token_querystring="client_id=$client_id&client_secret=$client_secret&grant_type=authorization_code&redirect_uri=$callback_endpoint"
    # &scope=$scope 'might' be necessary here, not sure

    debug_log "auth endpoint: $auth_endpoint"
    debug_log "token endpoint: $token_endpoint"
    debug_log "callback endpoint: $callback_endpoint"
    debug_log "token querystring: $token_querystring"

    start_ncat_server
    open_browser
    read_authcode
    kill_server
    get_graph_token
    close_browser
    finish
}

finish() {
    debug_log "DONE"
    echo $graph_token
    exit 0
}

check_command_dependency() {
    command_name=$1
    command -v $command_name >/dev/null 2>&1 || {
        error_log "$command_name is required but not installed. Aborting."
        exit 1
    }
    debug_log "$command_name found"
}

start_ncat_server() {
    debug_log "starting ncat server on port $callback_port"
    # Check if the port is already in use
    if lsof -i :$callback_port >/dev/null; then
        error_log "Port $callback_port is already in use. Aborting."
        exit 1
    fi

    # Create a named pipe for the authcode
    mkfifo acpipe
    debug_log "set authorization endpoint, redirect URI, and scopes"

    # Start a just-in-time ncat server to capture the auth code
    debug_log "starting ncat listener on port $callback_port to capture auth code"

    ncat -lk -p $callback_port -c '
    # Read the first line of the request
    read request
    # Extract the query string from the request
    query_string=${request#*code=}
    query_string=${query_string%% *}
    # Extract the code from the query string
    authcode=${query_string%%&*}
    # Print the code to the named pipe
    echo $authcode > acpipe
    # Send a response to the client
    printf "HTTP/1.1 200 OK\r\n\r\n<html><body><h1>Success, authcode retrieved. you may close this window.</h1></body></html>\r\n"
  ' &

    # Save the PID of the ncat server so we can kill it later
    server_pid=$! # dollar exclamantion mark is the PID of the last command run in the background - neat!
    debug_log "ncat server pid: '$server_pid'"
}

open_browser() {
    # open safari - since we know it's installed -
    # (-n) in a new process
    # (-a) specify the app-name
    # (-g) don't bring the app to the foreground
    # (-j) open the app hidden
    open -ngja "Safari" "$auth_endpoint?client_id=$client_id&response_type=code&redirect_uri=$callback_endpoint&response_mode=query&scope=$scope" &
    debug_log "opening browser window to $auth_endpoint"
}

read_authcode() {
    # Wait for the auth code to be written to the named pipe
    read authcode <acpipe
}

kill_server() {
    debug_log "killing ncat server with pid $server_pid"
    kill $server_pid
}

get_graph_token() {
    debug_log "passing authcode *REDACTED* to endpoint\n$token_endpoint"
    response=$(curl -s -X POST "$token_endpoint" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$token_querystring&code=$authcode")
    
    debug_log "endpoint response:\n $response"
    
    graph_token=$(echo $response | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    if [ -z "$graph_token" ]; then
        error_log "Failed to get access token. Aborting."
        exit 1
    fi
    debug_log "got access token: *REDACTED*"
    rm acpipe # Remove the named pipe

}

close_browser() {
    if [ $auto_close_browser -eq 1 ]; then
        debug_log "closing auth code browser window"
        # The whole PID thing is super unreliable because the .app spawns sub-processes
        # we'll just kill the last opened safari process using pkill
        pgrep -nx "Safari" | xargs kill
    fi
}

main