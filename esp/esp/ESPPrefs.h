

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NSString *ESPPrefsPath(void);

void ESPPrefsSetBool(NSString *key, BOOL value);
void ESPPrefsSetFloat(NSString *key, float value);
// Memory-only write (no disk schedule). Use while dragging UI; call ESPPrefsSync() on touch end.
void ESPPrefsSetFloatLive(NSString *key, float value);
void ESPPrefsSetBoolLive(NSString *key, BOOL value);
void ESPPrefsSync(void);

BOOL ESPPrefsBool(NSString *key, BOOL defaultValue);
float ESPPrefsFloat(NSString *key, float defaultValue);

id AppSettingsObjectForKey(NSString *key);
void AppSettingsSetObject(NSString *key, id value);
void AppSettingsRemoveKeys(NSArray<NSString *> *keys);

#ifdef __cplusplus
}
#endif
