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
import time

JOBS = {
    'net.iris.connect.login': ('Iris Connect.app', 'IrisConnect'),
    'net.iris.mcp-host.login': ('Iris MCP.app', 'IrisMCPHost'),
}
WORKER = 'net.iris.briefing-worker'


def worker_spec(repo):
    return {'Label':WORKER,'ProgramArguments':['/usr/bin/python3','-E','-s',str(repo/'services/iris-core/workflow.py'),'watch'],
            'WorkingDirectory':str(repo),'RunAtLoad':True,'LimitLoadToSessionType':'Aqua',
            'KeepAlive':{'SuccessfulExit':False},'ThrottleInterval':30,'ExitTimeOut':10,'Umask':0o077,
            'StandardOutPath':'/dev/null','StandardErrorPath':'/dev/null'}


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
        if len(columns) == 3 and columns[2] in {*JOBS,WORKER}:
            loaded[columns[2]] = {
                'running': columns[0].isdigit(),
                'pid': int(columns[0]) if columns[0].isdigit() else None,
                'exitStatus': int(columns[1]) if re.fullmatch(r'-?\d+', columns[1]) else None,
            }
    jobs = {}
    for label in [*JOBS,WORKER]:
        path = folder / (label + '.plist')
        checked_existing(path, worker_spec(repo) if label==WORKER else spec(repo, label))
        jobs[label] = {'installed': path.exists(), **loaded.get(label, {'running': False, 'pid': None, 'exitStatus': None})}
    boot = run(['/usr/sbin/sysctl', '-n', 'kern.boottime'])
    found = re.search(rb'sec = (\d+),', boot.stdout)
    return {'ok': result.returncode == 0, 'bootTime': int(found[1]) if found else None, 'jobs': jobs}


def connect_job(action, repo, folder):
    """Update Connect without interrupting the independent tunnel host."""
    label = 'net.iris.connect.login'
    path = folder / (label + '.plist')
    checked_existing(path, spec(repo, label))
    if not path.exists():
        raise ValueError('agent_registration_failed')
    if action == 'stop-connect':
        helper = repo / 'build/Iris Connect.app/Contents/MacOS/IrisControl'
        reply = run([str(helper), 'status'])
        try:
            value = json.loads(reply.stdout) if len(reply.stdout) <= 8192 else None
        except (ValueError, TypeError):
            value = None
        if reply.returncode or not isinstance(value, dict) or value.get('ok') is not True or type(value.get('busy')) is not bool:
            raise ValueError('control_status_unavailable')
        if value['busy']:
            raise ValueError('active_login')
        if run(['/bin/launchctl', 'bootout', f'gui/{os.getuid()}/{label}']).returncode != 0:
            raise ValueError('agent_registration_failed')
        for _ in range(50):
            result = run(['/usr/bin/pgrep', '-x', 'IrisConnect']).returncode
            if result == 1:
                return
            if result != 0:
                break
            time.sleep(0.1)
        raise ValueError('apps_must_be_stopped')
    elif action == 'start-connect':
        if run(['/usr/bin/pgrep', '-x', 'IrisConnect']).returncode != 1:
            raise ValueError('apps_must_be_stopped')
        if run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(repo / 'build/Iris Connect.app')]).returncode != 0:
            raise ValueError('app_integrity')
        if run(['/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', str(path)]).returncode != 0:
            raise ValueError('agent_registration_failed')
    else:
        raise ValueError('wrong_installation_target')


def process_table():
    # Only PID/PPID/executable names, never arguments or process environments.
    result=run(['/bin/ps','-axo','pid,ppid,comm'])
    if result.returncode:raise ValueError('process_check_failed')
    rows={}
    for line in result.stdout.decode(errors='replace').splitlines():
        parts=line.split(None,2)
        if len(parts)==3 and parts[0].isdigit() and parts[1].isdigit():rows[int(parts[0])]=(int(parts[1]),parts[2])
    return rows


def mcp_job(action,repo,folder):
    label='net.iris.mcp-host.login';path=folder/(label+'.plist')
    checked_existing(path,spec(repo,label))
    if not path.exists():raise ValueError('agent_registration_failed')
    if action=='stop-mcp':
        before=status(repo,folder)['jobs'][label]['pid'];rows=process_table();tracked={before} if before else set()
        while True:
            children={pid for pid,(parent,_) in rows.items() if parent in tracked}
            if children.issubset(tracked):break
            tracked.update(children)
        identities={pid:rows[pid][1] for pid in tracked if pid in rows}
        if run(['/bin/launchctl','bootout',f'gui/{os.getuid()}/{label}']).returncode:raise ValueError('agent_registration_failed')
        for _ in range(50):
            current=process_table()
            if not any(pid in current and current[pid][1]==comm for pid,comm in identities.items()):return
            time.sleep(0.1)
        raise ValueError('apps_must_be_stopped')
    elif action=='start-mcp':
        if run(['/usr/bin/pgrep','-x','IrisMCPHost']).returncode!=1:raise ValueError('apps_must_be_stopped')
        if run(['/usr/bin/codesign','--verify','--deep','--strict',str(repo/'build/Iris MCP.app')]).returncode:raise ValueError('app_integrity')
        if run(['/bin/launchctl','bootstrap',f'gui/{os.getuid()}',str(path)]).returncode:raise ValueError('agent_registration_failed')
    else:raise ValueError('wrong_installation_target')


def worker_job(action,repo,folder):
    path=folder/(WORKER+'.plist');expected=worker_spec(repo);checked_existing(path,expected)
    if action=='install-worker':
        for name in ['workflow.py','briefing.py','preparation.py']:
            source=repo/'services/iris-core'/name
            if source.is_symlink() or not source.is_file() or source.stat().st_uid!=os.getuid():raise ValueError('app_integrity')
        run(['/bin/launchctl','bootout',f'gui/{os.getuid()}/{WORKER}'])
        temporary=path.with_suffix('.tmp');fd=os.open(temporary,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
        try:
            with os.fdopen(fd,'wb') as handle:plistlib.dump(expected,handle)
            os.replace(temporary,path)
        finally:
            if temporary.exists():temporary.unlink()
        if run(['/bin/launchctl','bootstrap',f'gui/{os.getuid()}',str(path)]).returncode:raise ValueError('agent_registration_failed')
    elif action=='remove-worker':
        run(['/bin/launchctl','bootout',f'gui/{os.getuid()}/{WORKER}']);path.unlink(missing_ok=True)
    else:raise ValueError('wrong_installation_target')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['status', 'install', 'remove', 'stop-connect', 'start-connect','stop-mcp','start-mcp','install-worker','remove-worker'])
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
    elif args.action in {'stop-connect', 'start-connect'}:
        connect_job(args.action, repo, folder)
    elif args.action in {'stop-mcp','start-mcp'}:
        mcp_job(args.action,repo,folder)
    elif args.action in {'install-worker','remove-worker'}:
        worker_job(args.action,repo,folder)
    print(json.dumps(status(repo, folder)))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        known = {'unsafe_agent_file', 'foreign_agent_file', 'wrong_installation_target', 'unsafe_agent_directory',
                 'apps_must_be_stopped', 'process_check_failed', 'app_integrity', 'agent_registration_failed',
                 'active_login', 'control_status_unavailable'}
        code = str(error) if type(error) is ValueError and str(error) in known else 'startup_operation_failed'
        print(json.dumps({'ok': False, 'error': code}))
        sys.exit(1)
