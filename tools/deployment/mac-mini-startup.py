#!/usr/bin/env python3
"""Manage only the two Iris GUI LaunchAgents, without secrets or system daemons."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import subprocess
import sys

JOBS = {
    'net.iris.connect.login': ('Iris Connect.app', 'IrisConnect'),
    'net.iris.mcp-host.login': ('Iris MCP.app', 'IrisMCPHost'),
}


def allowed_target(target, platform, account, home, repo):
    accounts = {'mac-mini': 'irisagent', 'current-mac': 'milosvodrazka'}
    return (platform == 'darwin' and account == accounts.get(target)
            and home == Path('/Users') / account
            and repo == home / 'Personal/milos-executive-assisitantg03')


def spec(repo, label):
    bundle, binary = JOBS[label]
    return {
        'Label': label,
        'ProgramArguments': [str(repo / 'build' / bundle / 'Contents/MacOS' / binary)],
        'WorkingDirectory': str(repo),
        'RunAtLoad': True,
        'LimitLoadToSessionType': 'Aqua',
        'KeepAlive': {'SuccessfulExit': False},
        'ThrottleInterval': 20,
        'ExitTimeOut': 10,
        'Umask': 0o077,
        'StandardOutPath': '/dev/null',
        'StandardErrorPath': '/dev/null',
    }


def run(args):
    # Never print raw errors or launchctl detail/environment dumps.
    return subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, timeout=20)


def checked_existing(path, expected):
    if path.is_symlink():
        raise ValueError('unsafe_agent_file')
    if path.exists():
        info = path.stat()
        if not path.is_file() or info.st_uid != os.getuid() or info.st_size > 8192:
            raise ValueError('unsafe_agent_file')
        if plistlib.loads(path.read_bytes()) != expected:
            raise ValueError('foreign_agent_file')


def status(repo, folder):
    # launchctl list's table is PID/exit status/label only, never process environments.
    result = run(['/bin/launchctl', 'list'])
    loaded = {}
    for line in result.stdout.decode('utf-8', errors='replace').splitlines():
        columns = line.split()
        if len(columns) == 3 and columns[2] in JOBS:
            loaded[columns[2]] = {
                'running': columns[0].isdigit(),
                'pid': int(columns[0]) if columns[0].isdigit() else None,
                'exitStatus': int(columns[1]) if re.fullmatch(r'-?\d+', columns[1]) else None,
            }
    jobs = {}
    for label in JOBS:
        path = folder / (label + '.plist')
        checked_existing(path, spec(repo, label))
        jobs[label] = {'installed': path.exists(), **loaded.get(label, {'running': False, 'pid': None, 'exitStatus': None})}
    boot = run(['/usr/sbin/sysctl', '-n', 'kern.boottime'])
    found = re.search(rb'sec = (\d+),', boot.stdout)
    return {'ok': result.returncode == 0, 'bootTime': int(found[1]) if found else None, 'jobs': jobs}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'install', 'remove'])
    parser.add_argument('--target', choices=['mac-mini', 'current-mac'], default='mac-mini',
                        help='Explicit fixed installation target; defaults to the existing Mini deployment.')
    args = parser.parse_args()
    home = Path.home()
    repo = Path(__file__).resolve().parents[2]
    if not allowed_target(args.target, sys.platform, pwd.getpwuid(os.getuid()).pw_name, home, repo):
        raise ValueError('wrong_installation_target')
    folder = home / 'Library/LaunchAgents'
    if folder.is_symlink():
        raise ValueError('unsafe_agent_directory')
    if folder.exists() and (folder.stat().st_uid != os.getuid() or folder.stat().st_mode & 0o022):
        raise ValueError('unsafe_agent_directory')
    for label in JOBS:
        checked_existing(folder / (label + '.plist'), spec(repo, label))
    if args.action == 'install':
        # Prevent a second instance beside an app opened manually through LaunchServices.
        for bundle, binary in JOBS.values():
            process_check = run(['/usr/bin/pgrep', '-x', binary]).returncode
            if process_check == 0:
                raise ValueError('apps_must_be_stopped')
            if process_check != 1:
                raise ValueError('process_check_failed')
            if run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(repo / 'build' / bundle)]).returncode != 0:
                raise ValueError('app_integrity')
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        for label in JOBS:
            path = folder / (label + '.plist')
            run(['/bin/launchctl', 'bootout', f'gui/{os.getuid()}/{label}'])
            temporary = path.with_suffix('.tmp')
            # No symlink following, and no credentials or environment in the job definition.
            fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            try:
                with os.fdopen(fd, 'wb') as handle:
                    plistlib.dump(spec(repo, label), handle)
                os.replace(temporary, path)
            finally:
                if temporary.exists(): temporary.unlink()
            if run(['/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', str(path)]).returncode != 0:
                raise ValueError('agent_registration_failed')
    elif args.action == 'remove':
        for label in JOBS:
            run(['/bin/launchctl', 'bootout', f'gui/{os.getuid()}/{label}'])
            (folder / (label + '.plist')).unlink(missing_ok=True)
    print(json.dumps(status(repo, folder)))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        known = {'unsafe_agent_file', 'foreign_agent_file', 'wrong_installation_target', 'unsafe_agent_directory',
                 'apps_must_be_stopped', 'process_check_failed', 'app_integrity', 'agent_registration_failed'}
        code = str(error) if type(error) is ValueError and str(error) in known else 'startup_operation_failed'
        print(json.dumps({'ok': False, 'error': code}))
        sys.exit(1)
