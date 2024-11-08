# Clone Outlook Week Proof of Koncept Executor (COWPoKE)

## Motivation
Doing timesheets is a pain.  
I have to manually copy my calendar events from the previous week to the current week.  
This script automates that process, so I can spend more time on fun stuff, like writing scripts to automate my timesheets.  


## Key Points

 1. **Date Calculations**:
    - The script uses macOS-specific `date` commands to calculate the date range for the previous week and adjust dates for the current week.

 2. **Event Retrieval and Creation**:
    - Retrieves events from the previous week using the Microsoft Graph API.
    - Checks if an event has the category "IGNORE" and skips it if so.
    - Creates new events for the current week with the same details and categories as the original events.

 3. **Dependencies**:
    - Ensure `jq` is installed for JSON parsing.

 4. **Execution**:
    - Replace `YOUR_ACCESS_TOKEN` with your actual access token.
    - Make the script executable: `chmod +x script_name.sh`.
    - Run the script: `./script_name.sh`.

 This script should work effectively on macOS to clone your Outlook calendar events from the previous week to the current week, excluding events with the category "IGNORE". Adjust the script as needed based on your specific requirements.




