#ifndef ROOTHIDE_H
#define ROOTHIDE_H

#include <rootless.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wnullability-completeness"

#include <string.h>

#ifdef __cplusplus
#include <string>
#endif

#ifdef __OBJC__
#import <Foundation/NSString.h>
#endif

//stub functions

#ifdef __cplusplus
extern "C" {
#endif

static const char* rootfs_alloc(const char* path) { return path ? strdup(path) : path; }
static const char* jbroot_alloc(const char* path) { return path ? strdup(ROOT_PATH_VAR(path)) : path; }
static const char* jbrootat_alloc(int fd, const char* path) { return path ? strdup(ROOT_PATH_VAR(path)) : path; }

static unsigned long long jbrand() { return 0; }
static const char* jbroot(const char* path) { return ROOT_PATH_VAR(path); }
static const char* rootfs(const char* path) { return path; }

#ifdef __OBJC__
static NSString* _Nonnull __attribute__((overloadable)) jbroot(NSString* _Nonnull path) { return ROOT_PATH_NS_VAR(path); }
static NSString* _Nonnull __attribute__((overloadable)) rootfs(NSString* _Nonnull path) { return path; }
#endif

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
static std::string jbroot(std::string path) { return std::string(ROOT_PATH_VAR(path.c_str())); }
static std::string rootfs(std::string path) { return path; }
#endif

#pragma GCC diagnostic pop

#define __INCOMPATIBLE_MACRO	_Pragma("GCC error \"Please upgrade to the roothide APIs for full compatibility with rootful/rootless/roothide : https://github.com/roothide/Developer\"")

#undef	ROOT_PATH
#undef	ROOT_PATH_NS
#undef	ROOT_PATH_VAR
#undef	ROOT_PATH_NS_VAR
#undef	JBROOT_PATH
#undef	JBROOT_PATH_CSTRING
#undef	JBROOT_PATH_NSSTRING
#undef	ROOTFS_PATH
#undef	ROOTFS_PATH_CSTRING
#undef	ROOTFS_PATH_NSSTRING

#define ROOT_PATH(path)					({__INCOMPATIBLE_MACRO; (const char *)0; })
#define ROOT_PATH_NS(path)				({__INCOMPATIBLE_MACRO; (const char *)0; })

#define ROOT_PATH_VAR(path)				({__INCOMPATIBLE_MACRO; (const char *)0; })
#define ROOT_PATH_NS_VAR(path)			({__INCOMPATIBLE_MACRO; (const char *)0; })

#define JBROOT_PATH(path)				({__INCOMPATIBLE_MACRO; (const char *)0; })
#define JBROOT_PATH_CSTRING(path)		({__INCOMPATIBLE_MACRO; (const char *)0; })
#define JBROOT_PATH_NSSTRING(path)		({__INCOMPATIBLE_MACRO; (const char *)0; })

#define ROOTFS_PATH(path) 				({__INCOMPATIBLE_MACRO; (const char *)0; })
#define ROOTFS_PATH_CSTRING(path) 		({__INCOMPATIBLE_MACRO; (const char *)0; })
#define ROOTFS_PATH_NSSTRING(path) 		({__INCOMPATIBLE_MACRO; (const char *)0; })

#endif /* ROOTHIDE_H */