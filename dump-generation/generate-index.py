#!/usr/bin/env python3
"""Write dist/dumps/index.json describing every non-test dump folder.

Usage: generate-index.py <dumps-base-dir> > index.json
"""
import json
import os
import sys

base = sys.argv[1]
dumps = []
for name in sorted(os.listdir(base), reverse=True):
    path = os.path.join(base, name)
    if not os.path.isdir(path) or name.endswith("-test"):
        continue
    files = []
    for fname in sorted(os.listdir(path)):
        fpath = os.path.join(path, fname)
        if os.path.isfile(fpath):
            files.append({"name": fname, "size": os.path.getsize(fpath)})
    dumps.append({"date": name, "files": files})
json.dump({"dumps": dumps}, sys.stdout, indent=2)
