"""One private local UNIX socket with four fixed business methods; no auth API."""
import ctypes
import fcntl
import json
import os
import socket
import stat
import threading

import briefing
import workflow
import work_requests


def peer_uid(connection):
    # macOS getpeereid reports the kernel peer identity; no process inspection.
    user=ctypes.c_uint(); group=ctypes.c_uint()
    function=ctypes.CDLL(None,use_errno=True).getpeereid
    function.argtypes=[ctypes.c_int,ctypes.POINTER(ctypes.c_uint),ctypes.POINTER(ctypes.c_uint)]
    function.restype=ctypes.c_int
    if function(connection.fileno(),ctypes.byref(user),ctypes.byref(group))!=0:raise ValueError('peerDenied')
    return user.value


def serve_connection(connection):
    value={'ok':False,'error':'workUnavailable'}
    try:
        connection.settimeout(3)
        if peer_uid(connection)!=os.getuid():raise ValueError('peerDenied')
        raw=bytearray()
        while b'\n' not in raw:
            chunk=connection.recv(8193-len(raw))
            if not chunk:raise ValueError('invalidRequest')
            raw.extend(chunk)
            if len(raw)>8192:raise ValueError('invalidRequest')
        if not raw.endswith(b'\n') or raw.count(b'\n')!=1:raise ValueError('invalidRequest')
        request=json.loads(raw)
        if not isinstance(request,dict) or set(request)!={'method','params'}:raise ValueError('invalidRequest')
        value=work_requests.handle(request['method'],request['params'])
    except (OSError,ValueError,KeyError,TypeError,AttributeError):pass
    encoded=json.dumps(value,ensure_ascii=False).encode()
    if len(encoded)>16384:encoded=b'{"ok":false,"error":"workUnavailable"}'
    try:connection.sendall(encoded+b'\n')
    except OSError:pass
    finally:connection.close()


def start_bridge():
    workflow.directory()
    lock=os.open(briefing.RUNTIME/'work-bridge.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    info=os.fstat(lock)
    if info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o600 or not stat.S_ISREG(info.st_mode) or info.st_nlink!=1:raise ValueError('unsafe_bridge')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    path=briefing.RUNTIME/'w.sock'
    try:
        old=path.lstat()
        if not stat.S_ISSOCK(old.st_mode) or old.st_uid!=os.getuid() or stat.S_IMODE(old.st_mode)!=0o600:raise ValueError('unsafe_bridge')
        path.unlink()
    except FileNotFoundError:pass
    listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    # Private containing directory prevents access during bind/chmod.
    listener.bind(str(path));os.chmod(path,0o600);listener.listen(4);listener.settimeout(0.5)
    def loop():
        while True:
            try:connection,_=listener.accept()
            except socket.timeout:continue
            except OSError:break
            serve_connection(connection)
    thread=threading.Thread(target=loop,name='iris-work-bridge',daemon=True);thread.start()
    return listener,lock,thread
