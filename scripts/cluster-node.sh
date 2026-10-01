#!/bin/bash
set -e

NODES_FILE="/etc/vpn-cluster/nodes.json"

if [ "$1" == "add" ]; then
    if [ -z "$5" ]; then
        echo "Usage: $0 add <id> <name> <dc> <ip> [amnezia_url]"
        exit 1
    fi
    ID="$2"
    NAME="$3"
    DC="$4"
    IP="$5"
    AMZ="$6"
    
    python3 -c '
import sys, json
path = sys.argv[1]
try:
    with open(path, "r") as f: data = json.load(f)
except:
    data = []
data = [d for d in data if d.get("id") != sys.argv[2]]
data.append({"id": sys.argv[2], "name": sys.argv[3], "dc": sys.argv[4], "ip": sys.argv[5], "port": 443, "amnezia_url": sys.argv[6]})
with open(path, "w") as f: json.dump(data, f, ensure_ascii=False, indent=2)
' "$NODES_FILE" "$ID" "$NAME" "$DC" "$IP" "$AMZ"
    
    echo "Node $ID added."
    /root/autoXRAY_davida_custom.sh serverfix vpn-ch.example.com
    
elif [ "$1" == "rm" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 rm <id>"
        exit 1
    fi
    ID="$2"
    
    python3 -c '
import sys, json
path = sys.argv[1]
try:
    with open(path, "r") as f: data = json.load(f)
except:
    data = []
data = [d for d in data if d.get("id") != sys.argv[2]]
with open(path, "w") as f: json.dump(data, f, ensure_ascii=False, indent=2)
' "$NODES_FILE" "$ID"
    
    echo "Node $ID removed."
    /root/autoXRAY_davida_custom.sh serverfix vpn-ch.example.com
    
elif [ "$1" == "list" ]; then
    cat "$NODES_FILE" | jq .
else
    echo "Commands: add, rm, list"
fi
