# Bootstrap filesystem overlay

Files below this directory are merged over the expanded bootstrap after all
pinned packages are unpacked. Paths are relative to the archive root, so a
replacement for `/var/jb/usr/bin/uicache` belongs at:

`var/jb/usr/bin/uicache`

Use a pinned `.deb` in `config/bootstrap-packages.lock` when one exists. Use
this overlay for locally maintained replacements or configuration files.

