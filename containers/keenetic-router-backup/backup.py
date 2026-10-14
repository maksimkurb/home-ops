#!/usr/bin/env python3
"""Back up running-config of Keenetic routers over SSH.

Routers and destinations are described in a TOML file (CONFIG_FILE, default /config/routers.toml):

    [[destinations]]
    type = "folder"
    path = "/data"

    [[destinations]]
    type = "s3"
    bucket = "backups"                                  # required
    prefix = "keenetic/"                                # optional
    endpoint_url = "http://minio.files.svc:9000"        # optional, for MinIO and other S3-compatible storage
    region = "us-east-1"                                # optional
    access_key_id = "..."                               # optional, falls back to AWS_* env / default chain
    secret_access_key = "..."

    [[routers]]
    host = "192.168.1.1"          # required
    user = "admin"                # required
    password = "secret"           # required
    port = 1122                   # optional, default 22
    cronitor_url = "https://..."  # optional
    enabled = true                # optional, default true

Each backup is stored as <host>.txt in every destination. Without
[[destinations]] a single folder destination at OUTPUT_DIR (default /data) is
used. A failed backup never overwrites or removes the previous successful one.
"""
import os
import re
import subprocess
import sys
import tomllib
import urllib.request
from datetime import datetime
from pathlib import Path

CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/config/routers.toml"))
OUTPUT_DIR = Path(os.environ.get("OUTPUT_DIR", "/data"))
SSH_TIMEOUT = int(os.environ.get("SSH_TIMEOUT", "60"))

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
CONFIG_START = "! $$$"
CONFIG_MARKER = "$$$ Model:"


class BackupError(Exception):
    pass


class FolderDestination:
    def __init__(self, options):
        self.path = Path(options.get("path") or OUTPUT_DIR)
        self.path.mkdir(parents=True, exist_ok=True)

    def __str__(self):
        return f"folder {self.path}"

    def store(self, name, content):
        target = self.path / name
        temp_file = target.with_name(target.name + ".tmp")
        try:
            temp_file.write_text(content)
            temp_file.replace(target)
        finally:
            temp_file.unlink(missing_ok=True)

    def list(self):
        for path in sorted(self.path.glob("*.txt")):
            stat = path.stat()
            yield path.name, stat.st_size, datetime.fromtimestamp(stat.st_mtime)


class S3Destination:
    def __init__(self, options):
        import boto3
        from botocore.config import Config

        if not options.get("bucket"):
            raise BackupError("s3 destination requires 'bucket'")
        self.bucket = options["bucket"]
        self.prefix = options.get("prefix", "")
        self.client = boto3.client(
            "s3",
            endpoint_url=options.get("endpoint_url"),
            region_name=options.get("region"),
            aws_access_key_id=options.get("access_key_id"),
            aws_secret_access_key=options.get("secret_access_key"),
            config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 5}),
        )

    def __str__(self):
        return f"s3://{self.bucket}/{self.prefix}"

    def store(self, name, content):
        self.client.put_object(
            Bucket=self.bucket,
            Key=self.prefix + name,
            Body=content.encode(),
            ContentType="text/plain; charset=utf-8",
        )

    def list(self):
        response = self.client.list_objects_v2(Bucket=self.bucket, Prefix=self.prefix)
        for item in response.get("Contents", []):
            if item["Key"].endswith(".txt"):
                yield item["Key"], item["Size"], item["LastModified"]


DESTINATION_TYPES = {"folder": FolderDestination, "s3": S3Destination}


def create_destinations(configs):
    if not configs:
        configs = [{"type": "folder"}]
    destinations = []
    for index, options in enumerate(configs, start=1):
        kind = options.get("type")
        if kind not in DESTINATION_TYPES:
            raise BackupError(f"destination #{index} has unknown type {kind!r}, expected one of {sorted(DESTINATION_TYPES)}")
        destinations.append(DESTINATION_TYPES[kind](options))
    return destinations


def ping_cronitor(url, state):
    if not url:
        return
    try:
        with urllib.request.urlopen(f"{url}?state={state}", timeout=15):
            pass
    except Exception as error:
        print(f"Warning: Cronitor ping failed for state '{state}': {error}", file=sys.stderr)


def fetch_config(host, port, user, password):
    command = [
        "sshpass", "-e",
        "ssh", "-p", str(port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=15",
        "-o", "LogLevel=ERROR",
        "-T",
        f"{user}@{host}",
        "show running-config",
    ]
    try:
        result = subprocess.run(
            command,
            env={**os.environ, "SSHPASS": password},
            capture_output=True,
            text=True,
            errors="replace",
            timeout=SSH_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        raise BackupError(f"SSH command timed out after {SSH_TIMEOUT}s")

    output = ANSI_ESCAPE.sub("", result.stdout)
    start = output.find(CONFIG_START)
    if start == -1 or CONFIG_MARKER not in output[start:]:
        details = (result.stderr.strip() or output.strip())[:500]
        raise BackupError(
            f"invalid output (ssh exit code {result.returncode}, missing model information): {details}"
        )
    return output[start:]


def backup_router(index, router, destinations):
    host = router.get("host")
    user = router.get("user")
    password = router.get("password")
    port = router.get("port", 22)
    cronitor_url = router.get("cronitor_url")

    if not router.get("enabled", True):
        print(f"Skipping router #{index} ({host or 'unknown'}): disabled")
        return None
    if not host or not user or not password:
        print(f"✗ Router #{index} is missing one of the required fields: host, user, password")
        return False

    name = f"{host}.txt"
    print(f"=== Backing up router #{index}: {host}:{port} ===")
    ping_cronitor(cronitor_url, "run")

    try:
        config = fetch_config(host, port, user, password)
    except BackupError as error:
        print(f"✗ Router {host} backup failed: {error}")
        ping_cronitor(cronitor_url, "fail")
        return False

    stored = 0
    for destination in destinations:
        try:
            destination.store(name, config)
            print(f"  ✓ Saved {name} to {destination}")
            stored += 1
        except Exception as error:
            print(f"  ✗ Failed to save {name} to {destination}: {error}")

    if stored < len(destinations):
        print(f"✗ Router {host} backup saved to {stored} of {len(destinations)} destination(s)")
        ping_cronitor(cronitor_url, "fail")
        return False

    print(f"✓ Router {host} backup completed successfully ({len(config.encode())} bytes)")
    print("First 5 lines of saved configuration:")
    print("\n".join(config.splitlines()[:5]))
    ping_cronitor(cronitor_url, "complete")
    return True


def main():
    print(f"Starting backup process at {datetime.now()}")
    print(f"Config file: {CONFIG_FILE}")

    try:
        config = tomllib.loads(CONFIG_FILE.read_text())
    except (OSError, tomllib.TOMLDecodeError) as error:
        print(f"Error: Cannot read config file {CONFIG_FILE}: {error}")
        return 1
    routers = config.get("routers", [])
    if not routers:
        print(f"Error: No routers configured in {CONFIG_FILE}")
        return 1
    try:
        destinations = create_destinations(config.get("destinations", []))
    except Exception as error:
        print(f"Error: Cannot set up destinations: {error}")
        return 1

    print("Destinations: " + ", ".join(map(str, destinations)))
    print(f"Found {len(routers)} configured router(s)\n")

    results = []
    for index, router in enumerate(routers, start=1):
        results.append(backup_router(index, router, destinations))
        print()

    succeeded = results.count(True)
    failed = results.count(False)
    print("=== Backup Summary ===")
    print(f"Date: {datetime.now()}")
    print(f"Succeeded: {succeeded}, failed: {failed}, skipped: {results.count(None)}")
    for destination in destinations:
        print(f"Files in {destination}:")
        try:
            for name, size, modified in destination.list():
                print(f"  {name}  {size} bytes  {modified}")
        except Exception as error:
            print(f"  Cannot list files: {error}")

    if failed:
        print("✗ One or more router backups failed")
        return 1
    print("✓ All router backups completed successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
