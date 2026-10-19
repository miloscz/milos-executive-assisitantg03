"""Fixed, private local business storage. No auth data, network or MCP surface."""
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import secrets
import sqlite3
import stat

import evidence

ROOT = Path(__file__).resolve().parents[2] / '.iris-runtime'
ALLOWED_JSON = {'pilot-report.json', 'pilot-context.json', 'pilot-memo.json'}
DB_ID = 0x49524953


def validate(info, directory=False):
    mode = 0o700 if directory else 0o600
    if (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != mode
            or not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
            or (not directory and info.st_nlink != 1)):
        raise ValueError('unsafe_private_storage')


class Store:
    def __init__(self, runtime=ROOT):
        self.runtime = Path(runtime)
        self.path = self.runtime / 'work-evidence'
        self.fd = None
        self.db = None

    def _open(self, name, create=False):
        fd = os.open(name, os.O_RDWR | os.O_NOFOLLOW | (os.O_CREAT if create else 0), 0o600, dir_fd=self.fd)
        try:
            validate(os.fstat(fd))
        except BaseException:
            os.close(fd)
            raise
        return fd

    def _connect(self, name):
        # Sidecars must never be symlinks or readable by other users.
        for suffix in ('', '-journal', '-wal', '-shm'):
            try:
                validate(os.stat(name + suffix, dir_fd=self.fd, follow_symlinks=False))
            except FileNotFoundError:
                pass
        fd = self._open(name, create=True)
        try:
            before = os.fstat(fd)
            db = sqlite3.connect(self.path / name, timeout=0)
            try:
                after = os.stat(name, dir_fd=self.fd, follow_symlinks=False)
                validate(after)
                if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
                    raise ValueError('storage_changed')
                db.execute('PRAGMA journal_mode=DELETE')
                db.execute('PRAGMA synchronous=FULL')
                db.execute('PRAGMA foreign_keys=ON')
                db.execute('PRAGMA trusted_schema=OFF')
                app = db.execute('PRAGMA application_id').fetchone()[0]
                if app not in (0, DB_ID):
                    raise ValueError('unsupported_database')
                return db
            except BaseException:
                db.close()
                raise
        finally:
            os.close(fd)

    @contextmanager
    def locked(self):
        if self.fd is not None:
            raise ValueError('store_already_open')
        self.runtime.mkdir(mode=0o700, exist_ok=True)
        validate(self.runtime.lstat(), True)
        rootfd = os.open(self.runtime, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        lock = None
        old_umask = os.umask(0o077)
        try:
            try:
                os.mkdir('work-evidence', mode=0o700, dir_fd=rootfd)
            except FileExistsError:
                pass
            self.fd = os.open('work-evidence', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=rootfd)
            validate(os.fstat(self.fd), True)
            lock = self._open('store.lock', create=True)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.db = self._connect('state.sqlite')
            evidence.migrate(self.db)
            self.db.execute('PRAGMA application_id=' + str(DB_ID))
            self.db.row_factory = sqlite3.Row
            self.db.execute('PRAGMA quick_check').fetchone()[0] == 'ok' or self.fail()
            yield self
            if self.db.in_transaction:
                raise ValueError('unfinished_transaction')
        finally:
            if self.db is not None:
                self.db.close()
                self.db = None
            if lock is not None:
                os.close(lock)
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
            os.close(rootfd)
            os.umask(old_umask)

    @staticmethod
    def fail():
        raise ValueError('database_integrity')

    def write_json(self, name, value):
        if name not in ALLOWED_JSON or self.fd is None:
            raise ValueError('unknown_private_artifact')
        raw = (evidence.canonical(value) + '\n').encode()
        self._write(name, raw)

    def write_memo(self, body):
        if not isinstance(body, str) or self.fd is None:
            raise ValueError('invalid_private_document')
        self._write('pilot-memo.md', body.encode())

    def _write(self, name, raw):
        if len(raw) > 262144:
            raise ValueError('artifact_too_large')
        try:
            validate(os.stat(name, dir_fd=self.fd, follow_symlinks=False))
        except FileNotFoundError:
            pass
        temporary = '.write-' + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        try:
            with os.fdopen(fd, 'wb') as handle:
                handle.write(raw)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
            os.fsync(self.fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError:
                pass

    def backup_check(self, name='backup.sqlite'):
        if name not in {'backup.sqlite', 'prebinding.sqlite', 'pre-handoff.sqlite'}:
            raise ValueError('unknown_backup')
        if self.db.in_transaction:
            raise ValueError('backup_during_transaction')
        backup = self._connect(name)
        try:
            self.db.backup(backup)
            if backup.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                self.fail()
            if backup.execute('PRAGMA foreign_key_check').fetchone() is not None:
                self.fail()
            # Restore into an independent temporary in-memory database and compare
            # all rows, not just table counts. Never overwrites the live database.
            restored = sqlite3.connect(':memory:')
            try:
                backup.backup(restored)
                for row in self.db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
                    name = row[0]
                    if not name.replace('_', '').isalnum():
                        self.fail()
                    query = 'SELECT * FROM "' + name + '" ORDER BY rowid'
                    a = [tuple(r) for r in self.db.execute(query)]
                    b = restored.execute(query).fetchall()
                    if a != b:
                        self.fail()
            finally:
                restored.close()
            return {'integrity': True, 'restoredRowsMatch': True}
        finally:
            backup.close()

    def metadata(self):
        return {'schemaVersion': self.db.execute('PRAGMA user_version').fetchone()[0],
                'workItems': self.db.execute('SELECT count(*) FROM work_items').fetchone()[0],
                'claims': self.db.execute('SELECT count(*) FROM knowledge_claims').fetchone()[0],
                'captures': self.db.execute('SELECT count(*) FROM captures').fetchone()[0]}
