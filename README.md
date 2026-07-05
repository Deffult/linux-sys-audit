# Linux System Audit & Monitor

A comprehensive Bash script designed for Linux system administrators to perform quick health checks, audit security, and monitor system performance.

## Features
- **OS Detection:** Automatically identifies Linux distribution and kernel info.
- **Update Scanner:** Checks for available package updates (APT, DNF, YUM, Pacman).
- **Performance Monitor:** Monitors CPU usage, RAM, Disk I/O, and Network stats.
- **Security Audit:** Detects outdated or insecure services (e.g., Telnet, FTP, old SSH).
- **Reports:** Generates detailed **TXT** and **JSON** reports for logs.

## Requirements
- Bash 4.0+
- `sudo` privileges (for update checking)
- `bc`, `sysstat` (recommended for full performance stats)

## Usage
1. Clone the repo:
   ```bash
   git clone [https://github.com/Deffult/linux-sys-audit.git](https://github.com/Deffult/linux-sys-audit.git)
