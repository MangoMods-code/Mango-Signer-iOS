// The C interface Swift uses to reach zsign (signing) and minizip (reading .ipa files).
#ifndef MANGO_ENGINE_H
#define MANGO_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Runs zsign with command-line style arguments (argv[0] is ignored). Everything zsign prints goes to logPath.
/// Returns 0 when signing worked. Only one signing runs at a time.
int mango_zsign(int argc, const char *const *argv, const char *logPath);

/// Newline-separated list of every file name inside a zip (.ipa). Free with mango_free. NULL if it can't be opened.
char *mango_zip_names(const char *zipPath);

/// Reads one file out of a zip. On success returns 0 and sets *outData (free with mango_free) and *outLen.
/// Files bigger than maxSize are refused.
int mango_zip_read(const char *zipPath, const char *name, unsigned long maxSize, void **outData, unsigned long *outLen);

void mango_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif
