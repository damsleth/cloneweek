#!/bin/zsh

# cloneweek.zsh
# This script clones events from the previous week to the current week in a Microsoft 365 calendar.
# It uses the Microsoft Graph API to retrieve events from the previous week and create new events for the current week.
# The script requires an access token from the get_token.zsh script to authenticate with the Microsoft Graph API.
# The script takes optional parameters to specify the week numbers to clone events from and to.

# Initialize command line args
fromweek=""
toweek=""
categories=""
dryrun=0
debug=0
verbose=0

# source variables from .env
source .env

# counters
CLONED_EVENTS=0
IGNORED_EVENTS=0
SKIPPED_EVENTS=0
NUM_EVENTS=0

log() {
  local level=$1
  local message=$2
  if [ $prefix_log -eq 1 ]; then
    echo "[$level] $message" >&2
  else
    echo "$message" >&2
  fi
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
  -f | --from | --from-week)
    fromweek="$2"
    shift
    ;;
  -t | --to | --to-week)
    toweek="$2"
    shift
    ;;
  -c | --categories | --category)
    categories="$2"
    shift
    ;;
  -d | --dryrun | --dry-run | --test)
    dryrun=1
    ;;
  -l | --debug | --log)
    debug=1
    ;;
  -v | --verbose)
    verbose=1
    ;;
  *)
    log "ERROR" "Unknown parameter: $1"
    exit 1
    ;;
  esac
  shift
done

debug_log() {
  if [ $debug -eq 1 ]; then
    log "DEBUG" "$1"
  fi
}

error_log() {
  log "ERROR" "$1"
}

info_log() {
  log "INFO " "$1"
}

if [[ "$debug" -eq 1 ]]; then
  debug_log "Debug logging enabled"
fi

if [[ "$verbose" -eq 1 ]]; then
  set -x
  debug_log "Shell debug mode (verbose logging) enabled"
fi

if [[ "$dryrun" -eq 1 ]]; then
  info_log "Dryrun only, no events will be created"
fi

# Source default categories from .env
default_categories="${default_categories:-}"

# Get the auth_token from .env if it exists
if [ -z "$auth_token" ]; then
  debug_log "Getting access token from get_token.zsh"
  ACCESS_TOKEN=$(./get_token.zsh)
else
  debug_log "Access token found in .env"
  ACCESS_TOKEN=$auth_token
fi
if [[ -z "$ACCESS_TOKEN" ]]; then
  error_log "Access token not found. Exiting."
  exit 1
fi

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

# Function to check if an event matches any of the specified categories
matches_categories() {
  local event_categories=$1
  local filter_categories=$2

  IFS=',' read -r -A filter_array <<<"$filter_categories"
  for filter_category in "${filter_array[@]}"; do
    if echo "$event_categories" | grep -q "$filter_category"; then
      return 0
    fi
  done
  return 1
}

# Function to combine default categories with specified categories
combine_categories() {
  local default_categories=$1
  local categories=$2
  local combined_categories=""

  if [[ -n "$default_categories" ]]; then
    combined_categories="$default_categories"
  fi
  if [[ -n "$categories" ]]; then
    if [[ -n "$combined_categories" ]]; then
      combined_categories="$combined_categories,$categories"
    else
      combined_categories="$categories"
    fi
  fi

  echo "$combined_categories"
}

# Function to check if an event should be skipped based on categories
should_skip_event() {
  local event_categories=$1
  local combined_categories=$2
  local ignore_categories=$3

  # Check if the event matches the combined categories
  if [[ -n "$combined_categories" ]] && ! matches_categories "$event_categories" "$combined_categories"; then
    SKIPPED_EVENTS=$((SKIPPED_EVENTS + 1))
    if [[ "$log_ignored_events" -eq 1 ]] && [[ "$log_events" -eq 1 ]]; then
      # info_log "--"
      info_log "SKIP: '$SUBJECT' (NO_MATCH)"
    fi
    return 0
  fi

  # Check if the event matches any of the ignore categories
  if [[ -n "$ignore_categories" ]] && matches_categories "$event_categories" "$ignore_categories"; then
    IGNORED_EVENTS=$((IGNORED_EVENTS + 1))
    if [[ "$log_ignored_events" -eq 1 ]] && [[ "$log_events" -eq 1 ]]; then
      # info_log "--"
      info_log "IGNORE: '$SUBJECT' (IGNORE_MATCH)"
    fi
    return 0
  fi
  return 1
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
  info_log "Retrieved $NUM_EVENTS events from the user's calendar for week $fromweek"
  if [[ "$dryrun" -eq 1 ]]; then
    info_log "Dryrun only, no events will be created"
  else
    info_log "Cloning events from\nweek $fromweek toweek $toweek"
  fi

  clone_event() {
    local row=$1
    _jq() {
      echo ${row} | base64 --decode | jq -r ${1}
    }
    SUBJECT=$(_jq '.subject')
    BODY="This event was cloned from week $fromweek."
    START_DATE_TIME=$(_jq '.start.dateTime')
    END_DATE_TIME=$(_jq '.end.dateTime')
    TIME_ZONE=$(_jq '.start.timeZone')
    days_diff=$(((toweek - fromweek) * 7))

    # Remove fractional seconds from the date-time strings
    START_DATE_TIME=$(echo $START_DATE_TIME | sed 's/\.[0-9]*//')
    END_DATE_TIME=$(echo $END_DATE_TIME | sed 's/\.[0-9]*//')

    NEW_START_DATE_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" -v+${days_diff}d "${START_DATE_TIME}" "+%Y-%m-%dT%H:%M:%S")
    NEW_END_DATE_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" -v+${days_diff}d "${END_DATE_TIME}" "+%Y-%m-%dT%H:%M:%S")
    CATEGORIES=$(_jq '.categories')

    # Combine default categories with specified categories
    combined_categories=$(combine_categories "$default_categories" "$categories")

    # Check if the event should be skipped based on categories
    if should_skip_event "$CATEGORIES" "$combined_categories" "$ignore_categories"; then
      return
    fi
    CLONED_EVENTS=$((CLONED_EVENTS + 1))

    if [[ "$log_events" -eq 1 ]]; then
      info_log ""
      info_log "Subject\t\t$SUBJECT"
      # info_log "Start\t\t$START_DATE_TIME"
      # info_log "End\t\t$END_DATE_TIME"
      # info_log "New start\t$NEW_START_DATE_TIME"
      # info_log "New end \t$NEW_END_DATE_TIME"
      info_log "Start/End\t$START_DATE_TIME - $END_DATE_TIME"
      info_log "New Start/End\t$NEW_START_DATE_TIME - $NEW_END_DATE_TIME"
      info_log "Categories\t$(echo $CATEGORIES | tr -d '\n')"
      info_log""
    fi

    if [[ "$dryrun" -eq 1 ]]; then
      return # Skip creating events in dry-run mode
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
  }

  # Loop through events and create new ones for the "toweek"
  for row in $(echo "${EVENTS}" | jq -r '.[] | @base64'); do
    clone_event "$row"
  done
else
  info_log "No events to process."
fi
info_log "\n------------------\nEvents from week $fromweek to week $toweek"
info_log "$CLONED_EVENTS\tcloned\n$IGNORED_EVENTS\tignored\n$SKIPPED_EVENTS\tskipped\n$NUM_EVENTS\ttotal"
