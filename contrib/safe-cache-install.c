#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static void die(const char *message) { perror(message); exit(1); }

static int open_directory(int parent, const char *name, uid_t owner, int allow_root) {
    int fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat st;
    if (fd < 0) die("safe-cache-install: open directory");
    if (fstat(fd, &st) || !S_ISDIR(st.st_mode)
        || (st.st_uid != owner && (!allow_root || st.st_uid != 0)) || (st.st_mode & 0022)) {
        errno = EPERM; die("safe-cache-install: unsafe directory ownership or mode");
    }
    return fd;
}

static void adopt_directory(int fd, uid_t uid, gid_t gid) {
    struct stat st;
    if (fstat(fd, &st) || !S_ISDIR(st.st_mode)
        || (st.st_uid != uid && st.st_uid != 0) || (st.st_mode & 0022)) {
        errno = EPERM; die("safe-cache-install: unsafe directory before ownership repair");
    }
    if (st.st_uid == 0 && fchown(fd, uid, gid))
        die("safe-cache-install: repair directory ownership");
}

static void adopt_regular_if_present(int parent, const char *name, uid_t uid, gid_t gid) {
    int fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat st;
    if (fd < 0) {
        if (errno == ENOENT) return;
        die("safe-cache-install: open state file");
    }
    if (fstat(fd, &st) || !S_ISREG(st.st_mode)
        || (st.st_uid != uid && st.st_uid != 0) || (st.st_mode & 0022)) {
        errno = EPERM; die("safe-cache-install: unsafe state file");
    }
    if (st.st_uid == 0 && fchown(fd, uid, gid))
        die("safe-cache-install: repair state file ownership");
    if (close(fd)) die("safe-cache-install: close state file");
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fputs("usage: safe-cache-install UID SOURCE\n", stderr); return 2;
    }
    char *end = NULL;
    errno = 0;
    unsigned long parsed = strtoul(argv[1], &end, 10);
    if (errno || !end || *end || parsed > (unsigned long)(uid_t)-1) {
        fputs("safe-cache-install: invalid uid\n", stderr); return 2;
    }
    uid_t uid = (uid_t)parsed;
    struct passwd *pw = getpwuid(uid);
    if (!pw || !pw->pw_name || !pw->pw_name[0] || strchr(pw->pw_name, '/')
        || !strcmp(pw->pw_name, ".") || !strcmp(pw->pw_name, "..")) {
        fputs("safe-cache-install: uid has no safe account name\n", stderr); return 1;
    }
    for (const unsigned char *p = (unsigned char *)pw->pw_name; *p; ++p)
        if (*p < 0x21 || *p == 0x7f) {
            fputs("safe-cache-install: unsafe account name\n", stderr); return 1;
        }

    int source = open(argv[2], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    struct stat source_st;
    if (source < 0) die("safe-cache-install: open source");
    if (fstat(source, &source_st) || !S_ISREG(source_st.st_mode)
        || source_st.st_uid != uid || (source_st.st_mode & 0022)) {
        errno = EPERM; die("safe-cache-install: unsafe source");
    }

    int root = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0) die("safe-cache-install: open root");
    int var = open_directory(root, "var", 0, 0);
    int cache = open_directory(var, "cache", 0, 0);
    int hyprpm = open_directory(cache, "hyprpm", 0, 0);
    int account = open_directory(hyprpm, pw->pw_name, uid, 1);
    int plugins = open_directory(account, "hyprland-plugins", uid, 1);

    /* HyprPM may recreate this account-specific cache as root during a system
       update. The descriptor chain above proves every component before the
       narrowly scoped ownership repair; no path is reopened afterwards. */
    adopt_directory(account, uid, pw->pw_gid);
    adopt_directory(plugins, uid, pw->pw_gid);
    adopt_regular_if_present(account, "state.toml", uid, pw->pw_gid);
    adopt_regular_if_present(plugins, "state.toml", uid, pw->pw_gid);

    char temporary[64];
    snprintf(temporary, sizeof temporary, ".hyprbars.so.install.%ld", (long)getpid());
    int output = openat(plugins, temporary,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0700);
    if (output < 0) die("safe-cache-install: create destination");
    char buffer[65536];
    for (;;) {
        ssize_t count = read(source, buffer, sizeof buffer);
        if (count < 0) die("safe-cache-install: read source");
        if (!count) break;
        for (ssize_t offset = 0; offset < count;) {
            ssize_t written = write(output, buffer + offset, (size_t)(count - offset));
            if (written < 0) die("safe-cache-install: write destination");
            offset += written;
        }
    }
    if (fchmod(output, 0755) || fchown(output, uid, pw->pw_gid) || fsync(output))
        die("safe-cache-install: finalize destination");
    if (close(output)) die("safe-cache-install: close destination");
    if (renameat(plugins, temporary, plugins, "hyprbars.so"))
        die("safe-cache-install: replace destination");
    if (fsync(plugins)) die("safe-cache-install: sync destination directory");
    return 0;
}
