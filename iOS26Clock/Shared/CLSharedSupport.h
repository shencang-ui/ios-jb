#pragma once

#import <UIKit/UIKit.h>

#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#ifndef jbroot
#define jbroot(path) (path)
#endif
#endif

FOUNDATION_EXPORT NSString * const CLPrefsDomain;
FOUNDATION_EXPORT CFStringRef const CLPrefsChangedNotification;
FOUNDATION_EXPORT CFStringRef const CLPrefsRespringNotification;

NSString *CLMainBundleIdentifier(void);
BOOL CLIsSpringBoardProcess(void);
BOOL CLIsPreferencesProcess(void);

BOOL CL_prefBool(NSString *key, BOOL fallback);
CGFloat CL_prefFloat(NSString *key, CGFloat fallback);
NSInteger CL_prefInteger(NSString *key, NSInteger fallback);
NSString *CL_prefString(NSString *key, NSString *fallback);
BOOL CL_globalEnabled(void);
void CLReloadPreferences(void);
void CLSetPreferenceValue(NSString *key, id value);
void CLPostReloadNotification(void);
void CLPostRespringNotification(void);
void CLObservePreferenceChanges(dispatch_block_t block);

void CLLog(NSString *format, ...);

// Self-contained jbroot: maps absolute system paths onto the jailbreak prefix
// (/var/jb for roothide/Dopamine-style bootstraps) at runtime, without
// depending on roothide headers or libroot at link time.
NSString *CLJBRootPath(NSString *path);