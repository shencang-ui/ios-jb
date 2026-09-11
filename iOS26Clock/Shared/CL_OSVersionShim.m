#import <Foundation/Foundation.h>

// clang 11 emits an undefined ___isOSVersionAtLeast (nm display form, i.e.
// object symbol ____isOSVersionAtLeast) for @available, and this SDK has no
// compiler-rt providing it. Our C definition of ____isOSVersionAtLeast comes
// out as object symbol _____isOSVersionAtLeast (nm shows one underscore more
// than the C name). So declare it as an asm-named symbol to hit the exact
// object name ___isOSVersionAtLeast that the caller imports.
extern int CL_OSVersionShim(unsigned int major, unsigned int minor, unsigned int patch)
    __asm__("___isOSVersionAtLeast");

int CL_OSVersionShim(unsigned int major, unsigned int minor, unsigned int patch) {
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    return (v.majorVersion > major) ||
           (v.majorVersion == major && v.minorVersion > minor) ||
           (v.majorVersion == major && v.minorVersion == minor && v.patchVersion >= patch);
}
