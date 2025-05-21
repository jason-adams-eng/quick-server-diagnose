# Windows Server Spot-Check Script

![PowerShell](https://img.shields.io/badge/language-PowerShell-5391FE?logo=powershell&logoColor=white)

![PowerShell Lint](https://github.com/jason-adams-eng/ADUserGUI/actions/workflows/lint.yml/badge.svg)

![Markdown Lint](https://github.com/jason-adams-eng/ADUserGUI/actions/workflows/mdlint.yml/badge.svg)

This PowerShell script provides a quick health summary for one or more Windows servers. It collects key diagnostics and exports results to a CSV file for easy review.

## Features

- Checks CPU, memory, and disk usage
- Reports server uptime (last boot time)
- Summarizes recent errors from System and Application event logs
- Verifies status of key Windows services (customizable)
- For IIS servers, checks application pool and site status
- Confirms whether HTTP/HTTPS ports are listening
- Reads server names from `servers.txt` (one per line)
- Handles errors gracefully and reports them in the output

## Usage

1. Clone or download the script.
2. Create a `servers.txt` file in the script directory. Add one server name per line.
3. Adjust the list of key services to check by editing the `$ServiceNames` variable in the script.
4. Run the script in PowerShell 5.1 or later with appropriate permissions.
5. Review the results in `ServerHealthReport.csv` after execution.

## Requirements

- PowerShell 5.1 or later
- Remote management permissions on the target servers
- WinRM/WSMan enabled for remote CIM queries
- Administrative privileges may be required for certain checks

## Customization

- Update the `$ServiceNames` array in the script to match the critical services in your environment.
- The script detects IIS presence automatically and runs web server checks if applicable.

## License

MIT License
