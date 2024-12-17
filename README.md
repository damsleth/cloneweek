# C.L.O.N.E.W.E.E.K 
**C**alendar **L**ogistics **O**ptimized for **N**ew **E**vents **W**ith **E**fficient **E**vent **K**loning.

## Motivation
Doing timesheets is a pain.  
I have to manually copy my calendar events from the previous week to the current week.  
This script automates that process, so I can spend more time on fun stuff, like writing scripts to automate my timesheets.  

## TL;DR

***macos only***

1. Clone repo and cd into it: `git clone https://github.com/yourusername/cloneweek.git && cd cloneweek`
2. Copy `.env.sample` to `.env` and fill in your Azure AD app settings (ask [@damsleth](https://github.com/damsleth) for pzl-specifics).
3. Make the script executable: `chmod +x cloneweek.zsh`
4. Ensure `ncat`, `curl` and `jq` installed: `brew install jq netcat` (curl is installed by default but the built-in `nc` sucks so we use `ncat` instead)
5. Run `./cloneweek.zsh` and follow the instructions

## Features

- **Date Calculation**:
  - The script uses macOS-specific `date` commands to calculate the date range for the previous week and adjust dates for the current week.

- **Event Retrieval and Creation**:
  - Retrieves events from the previous week using the Microsoft Graph API.
  - Checks if an event has a custom ignore category (default is "IGNORE") and skips it if so.
  - Clones all events in the `default_categories` setting in `.env`, as well as those you specify with the `--categories` flag.
  - Creates new events for the current week with the same categories as the original event (`body` is stripped out to save bandwidth).  

- **Access Token**:
  - The `get_token.zsh` script fetches your access token by default if you have the client ID and secret set in the `.env` file. However, you can specify the access token yourself by replacing `YOUR_ACCESS_TOKEN` in the script, or implement token caching.

## Environment Variables

Environment variables which should be set in the `.env` file:

- `client_id`: Azure AD application client ID.
- `client_secret`: Azure AD application client secret.
- `tenant_id`: Azure AD tenant ID.
- `oauth_host`: OAuth host URL.
- `oauth_path`: OAuth authorization path.
- `oauth_token_path`: OAuth token path.
- `scope`: OAuth scope for Microsoft Graph API.
- `callback_host`: Callback host URL.
- `callback_port`: Callback port number.
- `callback_path`: Callback path.
- `ignore_categories`: Categories to ignore when cloning events.
- `default_categories`: Default categories to clone if not specified.
- `auto_close_browser`: Automatically close the browser after authentication (1 to enable, 0 to disable).
- `auth_token`: Authentication token to use, if not provided, the app will open a browser to authenticate.
- `dryrun`: Perform a dry run without creating events (1 to enable, 0 to disable).
- `debug`: Enable debug logging (1 to enable, 0 to disable).
- `verbose`: Enable verbose logging (1 to enable, 0 to disable).
- `log_events`: Log calendar events to stdout (1 to enable, 0 to disable).
- `log_ignored_events`: Log ignored and unmatched events to stdout (1 to enable, 0 to disable).
- `prefix_log`: Prefix log messages with ["INFO", "DEBUG", "ERROR"] (1 to enable, 0 to disable).

This script should work effectively on macOS to clone your Outlook calendar events from the previous week to the current week, excluding events based on the custom ignore category and filters. Adjust the script as needed based on your specific requirements.

## License

[WTFPL](http://www.wtfpl.net/about/) - see [LICENSE](LICENSE.md) for details.