import hashlib
import json
import posixpath
from pathlib import Path
import sys
import tarfile
import tempfile
import urllib.request

lock = json.loads(Path(sys.argv[1]).read_text())
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as temporary:
    archive = Path(temporary) / 'runtime.tar.xz'
    digest = hashlib.sha256()
    with urllib.request.urlopen(lock['url'], timeout=60) as response, archive.open('wb') as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != lock['sha256']:
        raise SystemExit('Runtime checksum mismatch; extraction refused')
    with tarfile.open(archive) as bundle:
        def runtime_filter(member, target):
            # Alpine's busybox links assume a chroot. Keep them inside the bundled root.
            if member.issym() and member.linkname.startswith('/'):
                if not member.name.lstrip('./').startswith('alpine/'):
                    raise ValueError('Absolute link outside the Alpine runtime')
                member.linkname = posixpath.relpath('alpine/' + member.linkname.lstrip('/'),
                                                   posixpath.dirname(member.name))
            return tarfile.data_filter(member, target)
        bundle.extractall(destination, filter=runtime_filter)
print(f"Verified Enhanced build {lock['build']}.")
