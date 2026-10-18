#!/usr/bin/env python3
"""Prevent idle sleep only on AC power; do not keep the display on or unlock it."""
import os
import subprocess
import time

ENV = {'PATH':'/usr/bin:/bin'}


def on_ac():
    try:
        result=subprocess.run(['/usr/bin/pmset','-g','batt'],stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=ENV,timeout=5)
        return result.returncode==0 and len(result.stdout)<=4096 and result.stdout.splitlines()[0]==b"Now drawing from 'AC Power'"
    except (OSError,IndexError,subprocess.SubprocessError):return False


class Guard:
    def __init__(self):self.child=None
    def refresh(self,ac):
        if self.child and self.child.poll() is not None:self.child=None
        if not ac:self.close()
        elif not self.child:
            # -w binds the assertion to this process even after a crash/SIGKILL.
            self.child=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(os.getpid())],
                stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=ENV)
    def close(self):
        if self.child:
            self.child.terminate()
            try:self.child.wait(timeout=2)
            except subprocess.TimeoutExpired:self.child.kill();self.child.wait(timeout=2)
            self.child=None


if __name__=='__main__':
    guard=Guard()
    try:
        while True:
            guard.refresh(on_ac());time.sleep(30)
    finally:guard.close()
