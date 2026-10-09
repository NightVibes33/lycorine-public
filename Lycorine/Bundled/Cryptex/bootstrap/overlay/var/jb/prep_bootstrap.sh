#!/var/jb/usr/bin/dash
set -e

PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

/var/jb/usr/libexec/firmware
/var/jb/usr/bin/cp /var/jb/usr/share/debianutils/shells /var/jb/etc/shells
printf '%s\n' \
    /var/jb/bin/dash /var/jb/usr/bin/dash \
    /var/jb/bin/bash /var/jb/usr/bin/bash \
    /var/jb/bin/zsh /var/jb/usr/bin/zsh >> /var/jb/etc/shells
/var/jb/usr/sbin/pwd_mkdb -p /var/jb/etc/master.passwd

/var/jb/usr/bin/rm -f /var/jb/prep_bootstrap.sh
