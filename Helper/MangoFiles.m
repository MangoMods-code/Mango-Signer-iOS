// MangoFiles: a tiny helper Mango Signer adds to an app when a tweak comes with settings files.
// When the app opens, it copies everything in <App>.app/MangoFiles/ into the app's Documents folder,
// skipping files that are already there (so changes you make to them are kept).
#import <Foundation/Foundation.h>

__attribute__((constructor)) static void MangoFilesCopy(void) {
    @autoreleasepool {
        @try {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *src = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"MangoFiles"];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:src isDirectory:&isDir] || !isDir) return;
            NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            if (docs.length == 0) return;
            [fm createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
            for (NSString *rel in [fm subpathsOfDirectoryAtPath:src error:nil]) {
                NSString *from = [src stringByAppendingPathComponent:rel];
                BOOL d = NO;
                if (![fm fileExistsAtPath:from isDirectory:&d] || d) continue;
                NSString *to = [docs stringByAppendingPathComponent:rel];
                if ([fm fileExistsAtPath:to]) continue;
                [fm createDirectoryAtPath:[to stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                [fm copyItemAtPath:from toPath:to error:nil];
            }
        } @catch (id e) {}
    }
}
