// Bridges Swift to zsign and minizip.
#include "MangoEngine.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <getopt.h>
#include <mutex>
#include <string>
#include <unistd.h>
#include <vector>

#include "third-party/minizip/unzip.h"

// zsign's main(), renamed in ThirdParty/zsign/src/zsign.cpp.
int zsign_main(int argc, char *argv[]);

static std::mutex g_signLock;

extern "C" int mango_zsign(int argc, const char *const *argv, const char *logPath) {
    std::lock_guard<std::mutex> guard(g_signLock);

    // Send zsign's output to the log file while it runs.
    fflush(stdout);
    fflush(stderr);
    int savedOut = dup(STDOUT_FILENO);
    int savedErr = dup(STDERR_FILENO);
    int fd = logPath ? open(logPath, O_WRONLY | O_CREAT | O_TRUNC, 0644) : -1;
    if (fd >= 0) {
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        close(fd);
    }

    std::vector<char *> args;
    args.reserve(argc + 1);
    for (int i = 0; i < argc; i++) args.push_back(strdup(argv[i] ? argv[i] : ""));
    args.push_back(nullptr);

    // getopt keeps its position between calls; start fresh every time.
#ifdef __APPLE__
    optreset = 1;
    optind = 1;
#else
    optind = 0; // glibc's way to start over
#endif
    int rc = zsign_main(argc, args.data());

    fflush(stdout);
    fflush(stderr);
    if (savedOut >= 0) { dup2(savedOut, STDOUT_FILENO); close(savedOut); }
    if (savedErr >= 0) { dup2(savedErr, STDERR_FILENO); close(savedErr); }
    for (char *a : args) free(a);
    return rc;
}

extern "C" char *mango_zip_names(const char *zipPath) {
    unzFile uf = unzOpen64(zipPath);
    if (!uf) return nullptr;
    std::string out;
    if (unzGoToFirstFile(uf) == UNZ_OK) {
        do {
            char name[2048];
            unz_file_info64 info;
            if (unzGetCurrentFileInfo64(uf, &info, name, sizeof(name), nullptr, 0, nullptr, 0) == UNZ_OK) {
                out += name;
                out += '\n';
            }
        } while (unzGoToNextFile(uf) == UNZ_OK);
    }
    unzClose(uf);
    return strdup(out.c_str());
}

extern "C" int mango_zip_read(const char *zipPath, const char *name, unsigned long maxSize, void **outData, unsigned long *outLen) {
    if (!outData || !outLen) return -1;
    *outData = nullptr;
    *outLen = 0;
    unzFile uf = unzOpen64(zipPath);
    if (!uf) return -1;
    int rc = -1;
    if (unzLocateFile(uf, name, 1) == UNZ_OK) {
        unz_file_info64 info;
        if (unzGetCurrentFileInfo64(uf, &info, nullptr, 0, nullptr, 0, nullptr, 0) == UNZ_OK &&
            info.uncompressed_size <= maxSize && unzOpenCurrentFile(uf) == UNZ_OK) {
            unsigned long size = (unsigned long)info.uncompressed_size;
            char *buf = (char *)malloc(size ? size : 1);
            unsigned long got = 0;
            while (buf && got < size) {
                int n = unzReadCurrentFile(uf, buf + got, (unsigned)std::min<unsigned long>(size - got, 1 << 20));
                if (n <= 0) break;
                got += (unsigned long)n;
            }
            unzCloseCurrentFile(uf);
            if (buf && got == size) {
                *outData = buf;
                *outLen = size;
                rc = 0;
            } else {
                free(buf);
            }
        }
    }
    unzClose(uf);
    return rc;
}

extern "C" void mango_free(void *ptr) { free(ptr); }
