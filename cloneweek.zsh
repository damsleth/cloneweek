#!/bin/zsh

# cloneweek.zsh
# This script clones events from the previous week to the current week in a Microsoft 365 calendar.
# It uses the Microsoft Graph API to retrieve events from the previous week and create new events for the current week.
# The script requires an access token from the get_token.zsh script to authenticate with the Microsoft Graph API.
# The script takes optional parameters to specify the week numbers to clone events from and to.
#

# source variables from .env, or set the ones below
source .env
#---------
# client_id=""
# client_secret=""
# tenant_id=""
# oauth_host="https://login.microsoftonline.com"
# oauth_path="oauth2/v2.0/authorize"
# oauth_token_path="oauth2/v2.0/token"
# scope="https://graph.microsoft.com/Calendars.ReadWrite"
# callback_host="http://localhost"
# callback_port=3000
# callback_path="/callback"
# debug=0
# dryrun=0
# auto_close_browser=1
# verbose=0
#--------

log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  if [[ "$log_timestamp" -eq 1 ]]; then
    echo "$timestamp [$level] $message" >&2
  else
    echo "$message" >&2
  fi
}

debug_log() {
  if [ $debug -eq 1 ]; then
    log "DEBUG" "$1"
  fi
}

error_log() {
  log "ERROR" "$1"
}

info_log() {
  log "INFO" "$1"
}

if [[ "$debug" -eq 1 ]]; then
  debug_log "Debug logging enabled"
fi

if [[ "$verbose" -eq 1 ]]; then
  set -x
  debug_log "Shell debug mode (verbose logging) enabled"
fi

if [[ "$dryrun" -eq 1 ]]; then
  info_log "DRYRUN ONLY - fetching token, but not cloning files"
fi

# Initialize variables
fromweek=""
toweek=""

# Get the access token or exit if it's not available
ACCESS_TOKEN=$(./get_token.zsh)
if [[ -z "$ACCESS_TOKEN" ]]; then
  error_log "Access token not found. Exiting."
  exit 1
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -f | --from)
    fromweek="$2"
    shift
    ;;
  -t | --to)
    toweek="$2"
    shift
    ;;
  *)
    error_log "Unknown parameter: $1"
    exit 1
    ;;
  esac
  shift
done

# Function to calculate start and end dates of a given ISO week number
calculate_week_dates() {
  week_num=$1

  # Calculate the date of the first day (Monday) of the given ISO week number
  # This uses the 'date' command with ISO week date format
  start_date=$(date -j -f "%Y %V %u" "$(date +%G) ${week_num} 1" "+%Y-%m-%dT00:00:00")
  if [[ $? -ne 0 ]]; then
    error_log "Failed to calculate start date for week $week_num"
    exit 1
  fi

  # Calculate the end date (Sunday of the same week) by adding 6 days to the start date
  end_date=$(date -j -f "%Y-%m-%dT%H:%M:%S" -v+6d "${start_date}" "+%Y-%m-%dT23:59:59")
  if [[ $? -ne 0 ]]; then
    error_log "Failed to calculate end date for week $week_num"
    exit 1
  fi

  echo "$start_date $end_date"
}

# Set default values if not provided
current_week=$(date +%V)
previous_week=$((current_week - 1))

if [[ -z "$fromweek" ]]; then
  fromweek=$previous_week
fi

if [[ -z "$toweek" ]]; then
  toweek=$current_week
fi

# Calculate dates for "fromweek" and "toweek"
read START_DATE_PREV_WEEK END_DATE_PREV_WEEK <<<$(calculate_week_dates $fromweek)
read START_DATE_CUR_WEEK END_DATE_CUR_WEEK <<<$(calculate_week_dates $toweek)

# Print the calculated dates
info_log "CLONING EVENTS\nfrom week $fromweek ($START_DATE_PREV_WEEK to $END_DATE_PREV_WEEK)\nto week $toweek ($START_DATE_CUR_WEEK to $END_DATE_CUR_WEEK)"

# Retrieve events from the "fromweek"
EVENTS=$(curl -s -X GET "https://graph.microsoft.com/v1.0/me/calendar/calendarView?startDateTime=${START_DATE_PREV_WEEK}&endDateTime=${END_DATE_PREV_WEEK}&select=categories,id,start,end,subject&top=999" -H "Authorization: Bearer $ACCESS_TOKEN" | jq '.value')
if [[ $? -ne 0 ]]; then
  error_log "Failed to retrieve events from Microsoft Graph API"
  exit 1
fi

# Check if EVENTS is not null and is an array with elements
if [[ $(echo "${EVENTS}" | jq -e '. | if type=="array" then (length > 0) else false end') == "true" ]]; then
  NUM_EVENTS=$(echo "${EVENTS}" | jq 'length')
  info_log "Found $NUM_EVENTS events to process."
  if [[ "$dryrun" -eq 1 ]]; then
    info_log "DRYRUN ONLY: listing events from week $fromweek, not cloning to week $toweek"
  else
    info_log "Cloning events from week $fromweek to week $toweek"
  fi

  # Loop through events and create new ones for the "toweek"
  for row in $(echo "${EVENTS}" | jq -r '.[] | @base64'); do
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }
    SUBJECT=$(_jq '.subject')
    BODY="CLONED"
    START_DATE_TIME=$(_jq '.start.dateTime')
    END_DATE_TIME=$(_jq '.end.dateTime')
    TIME_ZONE=$(_jq '.start.timeZone')
    NEW_START_DATE_TIME=$(echo $START_DATE_TIME | sed "s/${START_DATE_PREV_WEEK}/${START_DATE_CUR_WEEK}/")
    NEW_END_DATE_TIME=$(echo $END_DATE_TIME | sed "s/${START_DATE_PREV_WEEK}/${START_DATE_CUR_WEEK}/")
    CATEGORIES=$(_jq '.categories')
    # Check if the event has the category "IGNORE"
    if echo $CATEGORIES | jq -e '.[] | select(. == "IGNORE")' >/dev/null; then
      debug_log "--"
      debug_log "IGNORE: $SUBJECT"
      continue
    fi

    # if $dryrun is not 1, echo "dry run" instead of creating events
    if [[ "$dryrun" -eq 1 ]]; then
      debug_log "--"
      debug_log "$SUBJECT"
      debug_log "Start: $START_DATE_TIME"
      debug_log "End: $END_DATE_TIME"
      debug_log "New start date: $NEW_START_DATE_TIME"
      debug_log "New end date: $NEW_END_DATE_TIME"
      debug_log "Categories: $CATEGORIES"
      continue
    fi
    # Create new event for the "toweek"
    curl -s -X POST https://graph.microsoft.com/v1.0/me/events \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
      \"subject\": \"$SUBJECT\",
      \"body\": {
        \"contentType\": \"HTML\",
        \"content\": \"$BODY\"
      },
      \"start\": {
        \"dateTime\": \"$NEW_START_DATE_TIME\",
        \"timeZone\": \"$TIME_ZONE\"
      },
      \"end\": {
        \"dateTime\": \"$NEW_END_DATE_TIME\",
        \"timeZone\": \"$TIME_ZONE\"
      },
      \"categories\": $CATEGORIES
    }"
    if [[ $? -ne 0 ]]; then
      error_log "Failed to create event for $SUBJECT"
    fi
  done
else
  info_log "No events to process."
fi
