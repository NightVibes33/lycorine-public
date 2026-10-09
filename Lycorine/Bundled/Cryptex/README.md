* builds cryptexes with procursus, openssh, seals

The derived `/var/jb` bootstrap includes ElleKit 1.2 as a staged Debian
package and opainject 1.0.6 at `/var/jb/usr/bin/opainject`. The build signs
their Mach-O files before generating the Cryptex trust cache. They are
installed as tools; neither loader is automatically injected into launchd.
## Commands

```sh
make -C Cryptex fetch
AUTHORIZED_KEYS_FILE=/path/id_ed25519.pub \
make -C Cryptex image
make -C Cryptex bundle
```
