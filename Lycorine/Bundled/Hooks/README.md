# hooks + general architecture

## part 1: tweak injection
1. resign stuff from roothelper to /var/jb/<path> with:
* get-task-allow
* dynamic-codesigning
* disable library validation
* skip library validation

1.1: copy cryptexes over to /var/jb/cryptex
* copy the sshd, the jitterd, etc.
* launchdhook will restart it

1.2: patch dyld
* roothelper patchfinds dyld to allow `DYLD_INSERT_LIBRARIES` to work. it puts it in /var/jb/basebins/gen/dyld.patched

2. launchdhook gets injected
3. userspace reboot
4. posix spawn hooks spawn to itself: "/sbin/launchd" redirected to /var/jb/usr/libexec/lycorine/faked
5. faked has 2 jobs: 
* bind mount /var/jb/basebins/gen over /usr/lib. this way, dyld is patched for the whole system to allow `DYLD_INSERT_LIBRARIES`
* respawn launchd, but this time from `/var/jb/sbin/launchd` <- this launchd contains a LC_LOAD_DYLIB load command for /var/jb/h.dylib, which reloads the hook

6. respawned launchd rebinds again, does more things:
* restarts launch daemons under /var/jb by hooking `xpc_dictionary_get_value`
* rebind posix_spawns for 3 things:
|-> first path for system clones (eg. /var/jb/System/Library/CoreServices/SpringBoard.app)
|-> 2nd path for jailbroken binaries not under any of them. it passes them to ExecMainBinary which is a LiveContainer wrapper, pretrustcached
|-> 3rd: it skips xpcproxy until jitterd has spawned and loaded (explained later)

7. assuming path for SpringBoard:
|-> posix spawn hook spawns suspended, sends mach message to jitterd.
jitterd ptraces and detaches, gives CS_DEBUGGED
|-> launchd uses SETEXEC to continue spawn

8. finally!! generalhook!! 
* generalhook does a few things:
0. rebinds and fixes csops
1. loads in dyld library validation bypass, mmap and fcntl patch
2. consumes sandbox extensions 
3. dlopen tweaks :D

## ok... but how about xpcproxy spawned stuff?
the problem: if i try to jitterd xpcproxy before it's been spawned, the whole thing kind of just blows up :(

the solution: hence why i said not to jit and dlopen xpcproxy specifically. it relies only on function rebinding and hence doesn't need invalid pages (CS_DEBUGGED). the only thing that launchd does for that is redirect its spawn, and give it its send port. this allows xpcproxy to jitterd stuff that ITSELF spawns. 

## part 2: app tweaks
