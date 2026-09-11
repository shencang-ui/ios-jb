// Minimal CydiaSubstrate declarations (matches libsubstrate.tbd exports).
// The upstream theos/headers repo ships only a redirect stub, and the real
// header normally comes from the CydiaSubstrate framework, which this build
// environment does not have. Only the symbols logos-generated code needs.
#ifndef CydiaSubstrate_h
#define CydiaSubstrate_h

#include <objc/runtime.h>
#include <objc/message.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *result);
void *MSHookFunction(void *symbol, void *replace, void **result);
void MSCloseImage(void *image);
void MSDebug(const char *format, ...);
void *MSFindAddress(void *image, const char *name);
void *MSFindSymbol(void *image, const char *name);
void *MSGetImageByName(const char *name);
Class *MSGetClassHook(const char *name);
void MSHookMemory(void *target, const void *data, size_t size);
void *MSImageAddress(void *image);
void MSMapImage(const char *path, void **map);

#ifdef __cplusplus
}
#endif

#endif /* CydiaSubstrate.h */
