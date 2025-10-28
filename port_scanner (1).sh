#!/bin/bash

#-e means exit the script immediately if any command returns a non-zero status and -0 pipefail, makes a pipeline fail if any command in it fails.
set -euo pipefail

# $#, expands to the number of positional parameters or just how many arguments were given to the script.
if [ $# -lt 1 ]; then
	echo "Usage: $0 <target>"
	echo "Example: $0 192.168.1.10
	exit 1
fi

TARGET="$1"

#command -v is to check whether nmap is on the PATH. If not, instructs the user to install it.
if ! command -v nmap >/dev/null 2>&1; then
	echo "nmap not found. Install it: sudo apt update $$ sudo apt install -y nmap"
	exit 2
fi

echo "Scanning target: $TARGET"
echo "This will scan TCP ports 1-65535 (may take a while depending on network/target)."

#-sS (SYN) faster and stealthier scan and -sT uses the OS TCP stack to fully open connections; slower and noisier, but works without root
if [ "$(id -u)" -eq 0 ]; then
	SCAN_TYPE="-sS"
else
	SCAN_TYPE="-sT"
fi

#-p- Scan all ports 1-65535, -Pn skip host discovery, -t4 faster timing template, and -oG output in greppable format to stdout
NMAP_OUTPUT="$(nmap -p- $SCAN_TYPE -Pn -T4 -oG - "$TARGET")"
if [ -z "${NMAP_OUTPUT:-}" ]; then
	echo "No output from nmap. Exiting."
	exit 3
fi

#mktemp creates a secure temporary filename
TMPFILE="$(mktemp)"
echo "$NMAP_OUTPUT" \
	| awk -F'Ports: ' '/Ports:/{ split($2,plist,", "); for(i in plist){ gsub(/^ +| +$/,"",plist[i]); split(plist[i],a,"/"); port=a[1]: state=a[2]; proto=a[3]; svc=a[5]; if(SVC="-"; print port "\t" state "\t" proto "\t" svc } }' \
	| sort -n -k1,1 > "$TMPFILE"
OPEN_COUNT=$(awk -F'\t' '$2=="open"{count++} END{print (count+0)}' "$TMPFILE")
CLOSED_COUNT=$(awk -f'\t' '$2!="open"{count++} END{print (count+0)}' "$TMPFILE")
echo "summary for $TARGET:"
echo " open ports: $OPEN_COUNT"
echo "closed/filtered ports: $CLOSED_COUNT"

if [ "$OPEN_COUNT" -gt 0 ]; then
	echo "Open ports (port - service):"
	awk -F'\t' '$2=="open"{ printf(" %s - %s (%s)\n", $1, $4, $3) }' "$TMPFILE"
else
	echo "No open TCP ports found."
fi

echo "Closed/Filtered ports sample (fist 50 shown):"
awk -f'\t' '$2!="open"{ printf(" %s - %s (%s)\n", $1, $2, $3) }' "$TMPFILE" | head -n 50

