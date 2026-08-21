#!/usr/bin/env python3
"""Convenient entry point for the AWG gateway workflows."""
import argparse
from pathlib import Path
import subprocess
import sys

ANSIBLE_DIR = Path(__file__).resolve().parent
INVENTORY = ANSIBLE_DIR / "inventory" / "hosts.yaml"
PLAYBOOKS = {
    "prepare": "vpn-gateway-install.yaml",
    "update": "vpn-gateway-config-update.yaml",
    "add-client": "vpn-client-add.yaml",
}

def run(playbook, target=None, client_name=None):
    command = ["ansible-playbook", "-i", str(INVENTORY), str(ANSIBLE_DIR / "playbooks" / playbook)]
    if target:
        command.extend(["-e", f"target={target}"])
    if client_name:
        command.extend(["-e", f"vpn_client_name={client_name}"])
    return subprocess.run(command, cwd=ANSIBLE_DIR.parent.parent, check=False).returncode

def main():
    parser = argparse.ArgumentParser(description="Manage the AWG gateway")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "update"):
        item = commands.add_parser(name)
        item.add_argument("--target")
    client = commands.add_parser("add-client")
    client.add_argument("name")
    client.add_argument("--target", required=True)
    args = parser.parse_args()
    sys.exit(run(PLAYBOOKS[args.command], getattr(args, "target", None), getattr(args, "name", None)))

if __name__ == "__main__":
    main()
