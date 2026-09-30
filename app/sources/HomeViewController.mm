#import "HomeViewController.h"
#import "HUDHelper.h"
#import "rootless.h"
#import "pid.h"
#import "ESPPrefs.h"
#import "esp.h"
#import "GameOffsets.h"
#import "roothide/varCleanController.h"
#import "AppSettingsViewController.h"
#import "../KernelBoot.h"
#import "oxorany/oxorany.h"

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonRandom.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/sysctl.h>
#import <sys/syscall.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <pthread.h>

#ifndef oxorany_pchar
  #define oxorany_pchar(s) ((const char *)oxorany(s))
#endif

#define OXR(s)         [NSString stringWithUTF8String:oxorany_pchar(s)]
#define CAT2(a,b)      [NSString stringWithFormat:OXR("%@%@"),    (a),(b)]
#define CAT3(a,b,c)    [NSString stringWithFormat:OXR("%@%@%@"),  (a),(b),(c)]
#define CAT4(a,b,c,d)  [NSString stringWithFormat:OXR("%@%@%@%@"),(a),(b),(c),(d)]

static volatile uint8_t _opaque_seed = 0xA5;
#define DEAD_BRANCH(stmt)  do { volatile uint8_t v = _opaque_seed; \
    if ((v ^ v) != 0) { stmt; } } while (0)
#define ALWAYS_TRUE  ((((int)_opaque_seed) * ((int)_opaque_seed)) >= 0)

static const CGFloat kMenuButtonSize = 56.0f;

#pragma mark - VN TOOL iOS light theme

static UIColor *VNBg(void)       { return [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]; }
static UIColor *VNCard(void)     { return [UIColor whiteColor]; }
static UIColor *VNPanel2(void)   { return [UIColor colorWithWhite:0.90 alpha:1.0]; }
static UIColor *VNLine(void)     { return [UIColor colorWithWhite:0.85 alpha:1.0]; }
static UIColor *VNText(void)     { return [UIColor blackColor]; }
static UIColor *VNMuted(void)    { return [UIColor colorWithWhite:0.42 alpha:1.0]; }
static UIColor *VNAccent(void)   { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]; }
static UIColor *VNAccentDim(void){ return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:0.5]; }
static UIColor *VNBlue(void)     { return VNAccent(); }
static UIColor *VNOrange(void)   { return VNAccent(); }
static UIColor *VNRed(void)      { return [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0]; }

static UIView *VNMakeCard(void) {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = VNCard();
    v.layer.cornerRadius = 12.0f;
    v.layer.borderWidth = 0.0f;
    v.clipsToBounds = YES;
    return v;
}

static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

#pragma mark - Security / Anti-Debug

static void  HardenAntiDebug(void);
static BOOL  IsBeingTraced(void);
static BOOL  ReparentedByDebugger(void);
static BOOL  DyldHasHookFramework(void);
static BOOL  FridaGadgetActive(void);
static BOOL  JailbreakPathPresent(void);
static void  CanaryCapture(void);
static BOOL  CanarySwizzled(void);
static NSData *ComputeTextSectionSHA256(void);

static uint8_t  gSessionKM[64];
static BOOL     gSessionKeyReady = NO;
static pthread_once_t gOnce = PTHREAD_ONCE_INIT;

static void _hkdfSha256(const void *ikm, size_t ikmLen,
                        const void *salt, size_t saltLen,
                        const void *info, size_t infoLen,
                        uint8_t *out, size_t outLen) {
    uint8_t prk[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, salt, saltLen, ikm, ikmLen, prk);
    uint8_t t[CC_SHA256_DIGEST_LENGTH]; size_t tLen = 0;
    uint8_t ctr = 1; size_t off = 0;
    while (off < outLen) {
        CCHmacContext c;
        CCHmacInit(&c, kCCHmacAlgSHA256, prk, sizeof(prk));
        if (tLen) CCHmacUpdate(&c, t, tLen);
        CCHmacUpdate(&c, info, infoLen);
        CCHmacUpdate(&c, &ctr, 1);
        CCHmacFinal(&c, t);
        tLen = CC_SHA256_DIGEST_LENGTH;
        size_t cp = MIN(tLen, outLen - off);
        memcpy(out + off, t, cp);
        off += cp; ctr++;
    }
    memset(prk, 0, sizeof(prk));
    memset(t,   0, sizeof(t));
}

static void _initSessionKey(void) {
    uint8_t seed[32];
    CCRandomGenerateBytes(seed, sizeof(seed));
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"x";
    NSData   *idfvD = [idfv dataUsingEncoding:NSUTF8StringEncoding];
    const char *info = "vntool.vault.session.v1";
    _hkdfSha256(seed, sizeof(seed),
                idfvD.bytes, idfvD.length,
                info, strlen(info),
                gSessionKM, sizeof(gSessionKM));
    memset(seed, 0, sizeof(seed));
    gSessionKeyReady = YES;
}
static void SessionKeyEnsure(void) { pthread_once(&gOnce, _initSessionKey); }

static void SessionKeyReroll(void) {
    uint8_t seed[32];
    CCRandomGenerateBytes(seed, sizeof(seed));
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"x";
    NSData   *idfvD = [idfv dataUsingEncoding:NSUTF8StringEncoding];
    const char *info = "vntool.vault.session.v1";
    _hkdfSha256(seed, sizeof(seed),
                idfvD.bytes, idfvD.length,
                info, strlen(info),
                gSessionKM, sizeof(gSessionKM));
    memset(seed, 0, sizeof(seed));
}

static NSMutableData *VaultPut(NSString *s) {
    SessionKeyEnsure();
    NSData *raw = [s dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    uint8_t iv[kCCBlockSizeAES128];
    CCRandomGenerateBytes(iv, sizeof(iv));
    size_t outCap = raw.length + kCCBlockSizeAES128;
    NSMutableData *ct = [NSMutableData dataWithLength:outCap];
    size_t outLen = 0;
    if (CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                gSessionKM, 32, iv,
                raw.bytes, raw.length,
                (uint8_t *)ct.mutableBytes, outCap, &outLen) != kCCSuccess) return nil;
    ct.length = outLen;
    NSMutableData *blob = [NSMutableData dataWithCapacity:sizeof(iv) + outLen + 32];
    [blob appendBytes:iv length:sizeof(iv)];
    [blob appendData:ct];
    uint8_t tag[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, gSessionKM + 32, 32, blob.bytes, blob.length, tag);
    [blob appendBytes:tag length:sizeof(tag)];
    memset((void *)ct.mutableBytes, 0, ct.length);
    return blob;
}

static NSString *VaultGet(NSData *blob) {
    if (!blob || blob.length < (kCCBlockSizeAES128 + CC_SHA256_DIGEST_LENGTH)) return nil;
    SessionKeyEnsure();
    const uint8_t *p = (const uint8_t *)blob.bytes;
    size_t total = blob.length;
    size_t ctLen = total - kCCBlockSizeAES128 - CC_SHA256_DIGEST_LENGTH;
    uint8_t tag[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, gSessionKM + 32, 32, p, kCCBlockSizeAES128 + ctLen, tag);
    const uint8_t *recv = p + kCCBlockSizeAES128 + ctLen;
    uint8_t diff = 0;
    for (size_t i = 0; i < sizeof(tag); i++) diff |= tag[i] ^ recv[i];
    if (diff != 0) return nil;
    size_t outCap = ctLen + kCCBlockSizeAES128;
    NSMutableData *pt = [NSMutableData dataWithLength:outCap];
    size_t outLen = 0;
    if (CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                gSessionKM, 32, p,
                p + kCCBlockSizeAES128, ctLen,
                (uint8_t *)pt.mutableBytes, outCap, &outLen) != kCCSuccess) return nil;
    pt.length = outLen;
    NSString *r = [[NSString alloc] initWithData:pt encoding:NSUTF8StringEncoding];
    memset((void *)pt.mutableBytes, 0, pt.length);
    return r;
}

typedef int (*ptrace_t)(int, pid_t, caddr_t, int);
#define PT_DENY_ATTACH 31

static void HardenAntiDebug(void) {
    char name[8] = { 'p','t','r','a','c','e', 0, 0 };
    void *h = dlopen(NULL, RTLD_NOW);
    if (h) {
        ptrace_t pt = (ptrace_t)dlsym(h, name);
        if (pt) pt(PT_DENY_ATTACH, 0, 0, 0);
    }
    syscall(26, PT_DENY_ATTACH, 0, 0, 0);
}

static BOOL IsBeingTraced(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc info; size_t sz = sizeof(info);
    memset(&info, 0, sz);
    if (sysctl(mib, 4, &info, &sz, NULL, 0) != 0) return NO;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

static BOOL ReparentedByDebugger(void) {
    pid_t pp = getppid();
    return (pp != 1);
}

static BOOL DyldHasHookFramework(void) {
    static const char *kNeedles[] = {
        "MobileSubstrate", "SubstrateLoader.dylib", "Substitute",
        "libhooker", "frida", "FridaGadget", "cycript", "RevealServer",
        "SSLKillSwitch", "Liberty", "Choicy", "FlyJB", "Shadow",
    };
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *p = _dyld_get_image_name(i);
        if (!p) continue;
        for (size_t j = 0; j < sizeof(kNeedles)/sizeof(kNeedles[0]); j++) {
            if (strcasestr(p, kNeedles[j])) return YES;
        }
    }
    return NO;
}

static BOOL JailbreakPathPresent(void) {
    static const char *kPaths[] = {
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
        "/var/lib/apt", "/etc/apt", "/usr/sbin/sshd", "/bin/bash", "/usr/bin/ssh",
        "/private/var/lib/apt", "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/libexec/cydia/firmware.sh", "/var/jb",
    };
    struct stat st;
    for (size_t i = 0; i < sizeof(kPaths)/sizeof(kPaths[0]); i++) {
        if (stat(kPaths[i], &st) == 0) return YES;
    }
    return NO;
}

static BOOL HookTcpProbeOpen(uint16_t port) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return NO;
    struct sockaddr_in a; memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET; a.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    struct timeval tv = { .tv_sec = 0, .tv_usec = 200000 };
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int r = connect(s, (struct sockaddr *)&a, sizeof(a));
    close(s);
    return r == 0;
}
static BOOL FridaGadgetActive(void) {
    return HookTcpProbeOpen(27042) || HookTcpProbeOpen(27043);
}

static IMP gCanaryIMP = NULL;
static void CanaryCapture(void) {
    Method m = class_getInstanceMethod([NSObject class],
                NSSelectorFromString(OXR("description")));
    if (m) gCanaryIMP = method_getImplementation(m);
}
static BOOL CanarySwizzled(void) {
    if (!gCanaryIMP) return NO;
    Method m = class_getInstanceMethod([NSObject class],
                NSSelectorFromString(OXR("description")));
    if (!m) return YES;
    return method_getImplementation(m) != gCanaryIMP;
}

static NSData *ComputeTextSectionSHA256(void) {
#if defined(__LP64__)
    const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header(0);
    unsigned long size = 0;
    uint8_t *p = getsectiondata((const struct mach_header_64 *)h, "__TEXT", "__text", &size);
#else
    const struct mach_header *h = _dyld_get_image_header(0);
    unsigned long size = 0;
    uint8_t *p = getsectiondata(h, "__TEXT", "__text", &size);
#endif
    if (!p || size == 0) return nil;
    uint8_t out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(p, (CC_LONG)size, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}

#pragma mark - Keychain

@interface KC : NSObject
+ (BOOL)set:(NSData *)d forKey:(NSString *)k;
+ (NSData *)get:(NSString *)k;
+ (BOOL)del:(NSString *)k;
@end

@implementation KC
+ (NSDictionary *)q:(NSString *)k {
    return @{
        (__bridge id)kSecClass:          (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:    OXR("vntool.vault.v3"),
        (__bridge id)kSecAttrAccount:    k,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
}
+ (BOOL)set:(NSData *)d forKey:(NSString *)k {
    NSMutableDictionary *q = [[self q:k] mutableCopy];
    SecItemDelete((__bridge CFDictionaryRef)q);
    q[(__bridge id)kSecValueData] = d;
    return SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess;
}
+ (NSData *)get:(NSString *)k {
    NSMutableDictionary *q = [[self q:k] mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess) return nil;
    return (__bridge_transfer NSData *)out;
}
+ (BOOL)del:(NSString *)k {
    return SecItemDelete((__bridge CFDictionaryRef)[self q:k]) == errSecSuccess;
}
@end

#pragma mark - EtM / HKDF / FP

static NSData *HKDF(NSData *ikm, NSData *salt, NSData *info, size_t outLen) {
    uint8_t prk[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, ikm.bytes, ikm.length, prk);
    NSMutableData *out = [NSMutableData data];
    uint8_t T[CC_SHA256_DIGEST_LENGTH]; size_t Tlen = 0;
    uint8_t ctr = 1;
    while (out.length < outLen) {
        CCHmacContext ctx;
        CCHmacInit(&ctx, kCCHmacAlgSHA256, prk, sizeof(prk));
        if (Tlen) CCHmacUpdate(&ctx, T, Tlen);
        CCHmacUpdate(&ctx, info.bytes, info.length);
        CCHmacUpdate(&ctx, &ctr, 1);
        CCHmacFinal(&ctx, T);
        Tlen = CC_SHA256_DIGEST_LENGTH;
        [out appendBytes:T length:Tlen];
        ctr++;
    }
    return [out subdataWithRange:NSMakeRange(0, outLen)];
}

static NSData *DeviceMasterKey(void) {
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: OXR("fallback");
    NSData *ikm  = [idfv dataUsingEncoding:NSUTF8StringEncoding];
    NSData *salt = [OXR("vntool.kdf.salt.v3") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *info = [OXR("vntool.master.key.v3") dataUsingEncoding:NSUTF8StringEncoding];
    return HKDF(ikm, salt, info, 64);
}

static NSData *EtM_Encrypt(NSData *plain) {
    NSData *mk = DeviceMasterKey();
    const void *encK = mk.bytes;
    const void *macK = (const uint8_t *)mk.bytes + 32;
    uint8_t iv[16]; CCRandomGenerateBytes(iv, 16);
    size_t cap = plain.length + 32;
    NSMutableData *ct = [NSMutableData dataWithLength:cap];
    size_t moved = 0;
    if (CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                encK, 32, iv, plain.bytes, plain.length,
                (uint8_t *)ct.mutableBytes, cap, &moved) != kCCSuccess) return nil;
    ct.length = moved;
    NSMutableData *blob = [NSMutableData dataWithBytes:iv length:16];
    [blob appendData:ct];
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, macK, 32, blob.bytes, blob.length, mac);
    [blob appendBytes:mac length:CC_SHA256_DIGEST_LENGTH];
    return blob;
}

static NSData *EtM_Decrypt(NSData *blob) {
    if (blob.length < 16 + 16 + CC_SHA256_DIGEST_LENGTH) return nil;
    NSData *mk = DeviceMasterKey();
    const void *encK = mk.bytes;
    const void *macK = (const uint8_t *)mk.bytes + 32;
    NSUInteger bodyLen = blob.length - CC_SHA256_DIGEST_LENGTH;
    NSData *body = [blob subdataWithRange:NSMakeRange(0, bodyLen)];
    const uint8_t *mac = (const uint8_t *)blob.bytes + bodyLen;
    uint8_t expect[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, macK, 32, body.bytes, body.length, expect);
    uint8_t diff = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) diff |= (mac[i] ^ expect[i]);
    if (diff) return nil;
    const uint8_t *iv = (const uint8_t *)body.bytes;
    NSData *ct = [body subdataWithRange:NSMakeRange(16, body.length - 16)];
    size_t cap = ct.length + 16;
    NSMutableData *pt = [NSMutableData dataWithLength:cap];
    size_t moved = 0;
    if (CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                encK, 32, iv, ct.bytes, ct.length,
                (uint8_t *)pt.mutableBytes, cap, &moved) != kCCSuccess) return nil;
    pt.length = moved;
    return pt;
}

static NSString *DeviceFingerprint(void) {
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: OXR("unknown");
    NSData *key = [OXR("vntool-fp-v3") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *msg = [idfv dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, msg.bytes, msg.length, mac);
    NSMutableString *h = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [h appendFormat:OXR("%02x"), mac[i]];
    return h;
}

#pragma mark - Pinned URL Session

@interface PinnedDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)shared;
@end

@implementation PinnedDelegate
+ (instancetype)shared {
    static PinnedDelegate *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [PinnedDelegate new]; });
    return s;
}
- (NSSet<NSData *> *)pinnedSPKIHashes {
    return [NSSet set];
}
- (void)URLSession:(NSURLSession *)s
didReceiveChallenge:(NSURLAuthenticationChallenge *)ch
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))cb {
    SecTrustRef trust = ch.protectionSpace.serverTrust;
    if (!trust) { cb(NSURLSessionAuthChallengePerformDefaultHandling, nil); return; }
    NSSet<NSData *> *pins = [self pinnedSPKIHashes];
    if (pins.count == 0) {
        cb(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
        return;
    }
    SecTrustResultType r;
    if (SecTrustEvaluate(trust, &r) != errSecSuccess) {
        cb(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return;
    }
    CFIndex cnt = SecTrustGetCertificateCount(trust);
    for (CFIndex i = 0; i < cnt; i++) {
        SecCertificateRef c = SecTrustGetCertificateAtIndex(trust, i);
        NSData *d = (__bridge_transfer NSData *)SecCertificateCopyData(c);
        uint8_t h[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(d.bytes, (CC_LONG)d.length, h);
        NSData *hh = [NSData dataWithBytes:h length:CC_SHA256_DIGEST_LENGTH];
        if ([pins containsObject:hh]) {
            cb(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
            return;
        }
    }
    cb(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}
@end

static NSURLSession *PinnedSession(void) {
    static NSURLSession *s; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForRequest = 15;
        c.timeoutIntervalForResource = 20;
        s = [NSURLSession sessionWithConfiguration:c
                                          delegate:[PinnedDelegate shared]
                                     delegateQueue:nil];
    });
    return s;
}

#pragma mark - Firestore paths

static NSString *FB_PROJECT(void)      { return CAT3(OXR("vntool"), OXR("-"), OXR("license")); }
static NSString *FB_COLLECTION(void)   { return CAT2(OXR("licen"), OXR("ses")); }
static NSString *UD_LANG(void)         { return CAT2(OXR("vntool_"), OXR("lang")); }
static NSString *KC_KEY(void)          { return CAT2(OXR("VN_LIC_"), OXR("V3")); }
static NSString *KC_BASELINE(void)     { return CAT2(OXR("VN_INTG_"), OXR("V3")); }

static NSString *FirestoreBase(void) {
    return CAT4(OXR("https://"), OXR("firestore."), OXR("googleapis.com"), OXR("/v1"));
}
static NSString *DocPath(NSString *col, NSString *id_) {
    return [NSString stringWithFormat:
        CAT4(OXR("%@/projects/"), OXR("%@/databases/"), OXR("(default)/documents/"), OXR("%@/%@")),
        FirestoreBase(), FB_PROJECT(), col, id_];
}

#pragma mark - LicenseGate

@interface LicenseGate : NSObject
+ (NSDictionary *)getJSON:(NSString *)url status:(NSInteger *)code;
+ (NSInteger)maintenance:(NSString **)msg;
+ (NSDictionary *)fetch:(NSString *)key;
+ (BOOL)patch:(NSString *)key devices:(NSArray<NSString *> *)devs acts:(NSInteger)acts;
+ (NSInteger)verify:(NSString *)key;
+ (void)saveKey:(NSString *)key;
+ (NSString *)loadKey;
+ (void)forgetKey;
+ (NSDate *)parseISO:(NSString *)s;
@end

@implementation LicenseGate

+ (NSDictionary *)getJSON:(NSString *)urlStr status:(NSInteger *)outCode {
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 15;
    __block NSData *data = nil; __block NSInteger code = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[PinnedSession() dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            data = d;
            if ([r isKindOfClass:[NSHTTPURLResponse class]])
                code = [(NSHTTPURLResponse *)r statusCode];
            dispatch_semaphore_signal(sem);
        }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20*NSEC_PER_SEC));
    if (outCode) *outCode = code;
    if (!data) return nil;
    id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    DEAD_BRANCH(NSLog(OXR("vault=%p"), &gSessionKM));
    return [j isKindOfClass:[NSDictionary class]] ? j : nil;
}

+ (NSInteger)maintenance:(NSString **)outMsg {
    NSString *u = DocPath(CAT2(OXR("syst"), OXR("em")), OXR("maintenance"));
    NSInteger code = 0;
    NSDictionary *j = [self getJSON:u status:&code];
    if (!j || code != 200) return -1;
    NSDictionary *f = j[OXR("fields")];
    BOOL en = [f[OXR("enabled")][OXR("booleanValue")] boolValue];
    if (outMsg) *outMsg = f[OXR("message")][OXR("stringValue")] ?: @"";
    return en ? 1 : 0;
}

+ (NSDictionary *)fetch:(NSString *)key {
    NSString *u = DocPath(FB_COLLECTION(), key.uppercaseString);
    NSInteger code = 0;
    NSDictionary *j = [self getJSON:u status:&code];
    if (!j || j[OXR("error")]) return nil;
    return j[OXR("fields")];
}

+ (BOOL)patch:(NSString *)key devices:(NSArray<NSString *> *)devs acts:(NSInteger)acts {
    NSString *base = DocPath(FB_COLLECTION(), key.uppercaseString);
    NSString *u = [base stringByAppendingString:
        CAT3(OXR("?updateMask.fieldPaths=device_ids"),
             OXR("&updateMask.fieldPaths=activations"),
             OXR(""))];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    req.HTTPMethod = OXR("PATCH");
    [req setValue:OXR("application/json") forHTTPHeaderField:OXR("Content-Type")];
    req.timeoutInterval = 15;

    uint8_t nb[12]; CCRandomGenerateBytes(nb, 12);
    NSMutableString *nonce = [NSMutableString string];
    for (int i = 0; i < 12; i++) [nonce appendFormat:OXR("%02x"), nb[i]];
    NSString *toSign = [NSString stringWithFormat:OXR("%@|%@|%ld"), key.uppercaseString, nonce, (long)acts];
    NSData *sigKey = [OXR("vntool-req-sig-v3") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sigMsg = [toSign dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t mac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, sigKey.bytes, sigKey.length, sigMsg.bytes, sigMsg.length, mac);
    NSMutableString *sig = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [sig appendFormat:OXR("%02x"), mac[i]];

    NSMutableArray *vals = [NSMutableArray array];
    for (NSString *d in devs) [vals addObject:@{ OXR("stringValue"): d }];
    NSDictionary *body = @{
        OXR("fields"): @{
            OXR("device_ids"):  @{ OXR("arrayValue"): @{ OXR("values"): vals } },
            OXR("activations"): @{ OXR("integerValue"): [@(acts) stringValue] },
            OXR("_nonce"):      @{ OXR("stringValue"): nonce },
            OXR("_sig"):        @{ OXR("stringValue"): sig },
        }
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    __block NSInteger code = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[PinnedSession() dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            if ([r isKindOfClass:[NSHTTPURLResponse class]])
                code = [(NSHTTPURLResponse *)r statusCode];
            dispatch_semaphore_signal(sem);
        }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 20*NSEC_PER_SEC));
    return code == 200;
}

+ (NSDate *)parseISO:(NSString *)s {
    if (!s.length) return nil;
    NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
    f.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *d = [f dateFromString:s]; if (d) return d;
    f.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [f dateFromString:s];
}

+ (NSInteger)verify:(NSString *)key {
    if (CanarySwizzled()) return 4;
    NSDictionary *f = [self fetch:key];
    if (!f) return 1;
    NSString *status = f[OXR("status")][OXR("stringValue")];
    if (![status isEqualToString:OXR("active")]) return 2;
    NSString *exp = f[OXR("expires_at")][OXR("timestampValue")] ?: f[OXR("expires_at")][OXR("stringValue")];
    if (exp) {
        NSDate *d = [self parseISO:exp];
        if (d && [d timeIntervalSinceNow] < 0) return 2;
    }
    NSInteger maxA = [f[OXR("max_activations")][OXR("integerValue")] integerValue];
    NSInteger cur  = [f[OXR("activations")][OXR("integerValue")] integerValue];
    NSArray *vs = f[OXR("device_ids")][OXR("arrayValue")][OXR("values")];
    NSMutableArray<NSString *> *devs = [NSMutableArray array];
    for (NSDictionary *v in vs) {
        NSString *s = v[OXR("stringValue")];
        if (s) [devs addObject:s];
    }
    NSString *me = DeviceFingerprint();
    if ([devs containsObject:me]) return 0;
    if (maxA > 0 && cur >= maxA) return 3;
    [devs addObject:me];
    return [self patch:key devices:devs acts:cur+1] ? 0 : 4;
}

+ (void)saveKey:(NSString *)key {
    NSData *plain = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSData *blob = EtM_Encrypt(plain);
    if (blob) [KC set:blob forKey:KC_KEY()];
}
+ (NSString *)loadKey {
    NSData *blob = [KC get:KC_KEY()];
    if (!blob) return nil;
    NSData *plain = EtM_Decrypt(blob);
    if (!plain) return nil;
    return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
}
+ (void)forgetKey { [KC del:KC_KEY()]; }
@end

#pragma mark - Runtime harden

static void RuntimeHardenOrDie(void) {
    SessionKeyEnsure();
    HardenAntiDebug();
    CanaryCapture();

    if (IsBeingTraced())        exit(0);
    if (ReparentedByDebugger()) exit(0);
    if (DyldHasHookFramework()) exit(0);
    if (FridaGadgetActive())    exit(0);
    (void)JailbreakPathPresent();

    NSData *cur = ComputeTextSectionSHA256();
    if (cur) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (![defaults boolForKey:@"AppHasRunBefore"]) {
            [KC del:KC_BASELINE()];
            [defaults setBool:YES forKey:@"AppHasRunBefore"];
            [defaults synchronize];
        }
        NSData *stored = [KC get:KC_BASELINE()];
        if (!stored) {
            [KC set:cur forKey:KC_BASELINE()];
        } else if (![stored isEqualToData:cur]) {
            exit(0);
        }
    }
}

#pragma mark - HomeViewController

@interface HomeViewController ()
// ==== UI (giữ nguyên từ bản gốc) ====
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIButton *settingsBtn;

@property (nonatomic, strong) UIView *controlCard;
@property (nonatomic, strong) UIImageView *controlIconView;
@property (nonatomic, strong) UILabel *controlTitleLabel;
@property (nonatomic, strong) UILabel *controlSubtitleLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *killAllButton;

@property (nonatomic, strong) UIView *togglesCard;
@property (nonatomic, strong) UILabel *aimbotLabel;
@property (nonatomic, strong) UISwitch *aimbotSwitch;
@property (nonatomic, strong) UILabel *aimBehindWallLabel;
@property (nonatomic, strong) UISwitch *aimBehindWallSwitch;
@property (nonatomic, strong) UILabel *silentAimLabel;
@property (nonatomic, strong) UISwitch *silentAimSwitch;
@property (nonatomic, strong) UILabel *camLabel;
@property (nonatomic, strong) UISwitch *camSwitch;
@property (nonatomic, strong) UISlider *camSlider;
@property (nonatomic, strong) UILabel *camValueLabel;

@property (nonatomic, strong) UIView *espCard;
@property (nonatomic, strong) UILabel *espCardTitle;
@property (nonatomic, strong) UILabel *espLabel;
@property (nonatomic, strong) UISwitch *espSwitch;
@property (nonatomic, strong) UILabel *espBoxLabel;
@property (nonatomic, strong) UISwitch *espBoxSwitch;
@property (nonatomic, strong) UILabel *espLineLabel;
@property (nonatomic, strong) UISwitch *espLineSwitch;
@property (nonatomic, strong) UILabel *espBoneLabel;
@property (nonatomic, strong) UISwitch *espBoneSwitch;
@property (nonatomic, strong) UILabel *espHealthLabel;
@property (nonatomic, strong) UISwitch *espHealthSwitch;
@property (nonatomic, strong) UILabel *espCountLabel;
@property (nonatomic, strong) UISwitch *espCountSwitch;
@property (nonatomic, strong) UILabel *espDistanceLimitLabel;
@property (nonatomic, strong) UISlider *espDistanceLimitSlider;
@property (nonatomic, strong) UILabel *espDistanceLimitValueLabel;

@property (nonatomic, strong) UIView *aimCard;
@property (nonatomic, strong) UILabel *fovLabel;
@property (nonatomic, strong) UISlider *fovSlider;
@property (nonatomic, strong) UILabel *fovValueLabel;
@property (nonatomic, strong) UILabel *triggerLabel;
@property (nonatomic, strong) UISegmentedControl *triggerSegment;
@property (nonatomic, strong) UILabel *aimPosLabel;
@property (nonatomic, strong) UISegmentedControl *aimPosSegment;

@property (nonatomic, strong) UILabel *versionSectionLabel;
@property (nonatomic, strong) UIButton *ffCard;
@property (nonatomic, strong) UIImageView *ffIconView;
@property (nonatomic, strong) UILabel *ffNameLabel;

@property (nonatomic, strong) UIView *statusCard;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *openGameButton;

@property (nonatomic, strong) UIView *licenseCard;
@property (nonatomic, strong) UILabel *licenseTitleLabel;
@property (nonatomic, strong) UILabel *licenseValueLabel;

@property (nonatomic, strong) UIView *authCard;
@property (nonatomic, strong) UILabel *authTitleLabel;
@property (nonatomic, strong) UILabel *authValueLabel;

@property (nonatomic, strong) UIView *supportCard;
@property (nonatomic, strong) UILabel *supportTitleLabel;
@property (nonatomic, strong) UILabel *supportSubtitleLabel;
@property (nonatomic, strong) UIButton *joinButton;

@property (nonatomic, strong) UIView *extraCard;
@property (nonatomic, strong) UILabel *autoCleanLabel;
@property (nonatomic, strong) UISwitch *autoCleanSwitch;
@property (nonatomic, strong) UILabel *authorizationLabel;
@property (nonatomic, strong) UIButton *authorizationButton;

// ==== Polling / HUD state ====
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;

// ==== License gate (thêm mới) ====
@property (nonatomic, strong) UIView *gateOverlay;
@property (nonatomic, strong) UIActivityIndicatorView *gateSpinner;
@property (nonatomic, strong) UILabel *gateLabel;
@property (nonatomic, assign) BOOL unlocked;
@property (nonatomic, strong) NSMutableData *vaultedKey;
@end

@implementation HomeViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleDarkContent; }

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    // Anti-debug + integrity (như bản gốc server-key)
    RuntimeHardenOrDie();

    // Chỉ dùng Free Fire
    GameTargetSetSelectedId(@"ff");

    [self buildUI];
    [self buildGateOverlay];

    // Ẩn UI chính cho đến khi unlock
    _scrollView.hidden = YES;
    _settingsBtn.hidden = YES;
    [self showGateMessage:[self isVi] ? OXR("Đang kiểm tra…") : OXR("Checking…")];

    _gameMissingStreak = 0;
    _pendingHUDEnableUntil = 0;
    _hudRequestSerial = 0;
    _unlocked = NO;

    GameOffsetsReload();
    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appResignedActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];

    // Bắt đầu gate flow (không startPollingGameState ở đây, sẽ start sau unlock)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self runGate]; });

    [self schedulePeriodicHardenCheck];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
    if (self.navigationController) {
        self.navigationController.navigationBar.barStyle = UIBarStyleDefault;
        self.navigationController.navigationBar.translucent = NO;
        self.navigationController.navigationBar.barTintColor = VNBg();
        self.navigationController.navigationBar.tintColor = VNAccent();
        self.navigationController.view.backgroundColor = VNBg();
    }
    if (self.tabBarController) {
        self.tabBarController.tabBar.barStyle = UIBarStyleDefault;
        self.tabBarController.tabBar.translucent = NO;
        self.tabBarController.tabBar.barTintColor = VNCard();
        self.tabBarController.tabBar.tintColor = VNAccent();
        self.tabBarController.tabBar.unselectedItemTintColor = VNMuted();
        self.tabBarController.view.backgroundColor = VNBg();
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_pollTimer invalidate];
    _pollTimer = nil;
}

- (BOOL)isVi {
    NSString *l = [[NSUserDefaults standardUserDefaults] stringForKey:UD_LANG()] ?: OXR("vi");
    return [l isEqualToString:OXR("vi")];
}

- (void)schedulePeriodicHardenCheck {
    __weak __typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(30*NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        __typeof(self) ss = ws; if (!ss) return;
        if (IsBeingTraced() || DyldHasHookFramework() || FridaGadgetActive() || CanarySwizzled()) {
            dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
            return;
        }
        [ss schedulePeriodicHardenCheck];
    });
}

- (UIColor *)cardBackground { return VNCard(); }
- (UIColor *)accentGreen { return VNAccent(); }
- (UIColor *)accentBlue { return VNBlue(); }
- (UIColor *)accentOrange { return VNOrange(); }

- (void)openSettings {
    AppSettingsViewController *vc = [[AppSettingsViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)applyTheme {
    self.view.backgroundColor = VNBg();

    _controlCard.backgroundColor = VNCard();
    _controlTitleLabel.textColor = VNText();
    _controlSubtitleLabel.textColor = VNMuted();
    _startButton.backgroundColor = VNAccent();
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _killAllButton.backgroundColor = VNPanel2();
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];

    _togglesCard.backgroundColor = VNCard();
    _aimbotLabel.textColor = VNText();
    _aimbotSwitch.onTintColor = VNAccent();
    _aimBehindWallLabel.textColor = VNText();
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _silentAimLabel.textColor = VNText();
    _silentAimSwitch.onTintColor = VNAccent();
    _camLabel.textColor = VNText();
    _camSwitch.onTintColor = VNAccent();
    _camSlider.minimumTrackTintColor = VNAccent();
    _camValueLabel.textColor = VNMuted();

    _espCard.backgroundColor = VNCard();
    _espCardTitle.textColor = VNMuted();
    _espLabel.textColor = VNText();
    _espSwitch.onTintColor = VNAccent();
    for (UILabel *l in @[_espBoxLabel, _espLineLabel, _espBoneLabel,
                          _espHealthLabel, _espCountLabel, _espDistanceLimitLabel]) {
        l.textColor = VNText();
    }
    for (UISwitch *s in @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                           _espHealthSwitch, _espCountSwitch]) {
        s.onTintColor = VNAccent();
    }
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();
    _espDistanceLimitValueLabel.textColor = VNMuted();

    _aimCard.backgroundColor = VNCard();
    _fovLabel.textColor = VNText();
    _fovSlider.minimumTrackTintColor = VNAccent();
    _fovValueLabel.textColor = VNMuted();
    _triggerLabel.textColor = VNText();
    _triggerSegment.selectedSegmentTintColor = VNAccent();
    _triggerSegment.backgroundColor = VNPanel2();
    _aimPosLabel.textColor = VNText();
    _aimPosSegment.selectedSegmentTintColor = VNAccent();
    _aimPosSegment.backgroundColor = VNPanel2();

    _versionSectionLabel.textColor = VNMuted();
    _ffCard.backgroundColor = VNCard();
    _ffNameLabel.textColor = VNText();

    _statusCard.backgroundColor = VNCard();
    _statusLabel.textColor = VNText();
    _openGameButton.backgroundColor = VNAccent();
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _licenseCard.backgroundColor = VNCard();
    _authCard.backgroundColor = VNCard();
    _licenseTitleLabel.textColor = VNMuted();
    _licenseValueLabel.textColor = VNText();
    _authTitleLabel.textColor = VNMuted();
    _authValueLabel.textColor = VNAccent();

    _supportCard.backgroundColor = VNCard();
    _supportTitleLabel.textColor = VNText();
    _supportSubtitleLabel.textColor = VNMuted();
    _joinButton.backgroundColor = VNAccent();
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    _extraCard.backgroundColor = VNCard();
    _autoCleanLabel.textColor = VNText();
    _autoCleanSwitch.onTintColor = VNAccent();
    _authorizationLabel.textColor = VNText();
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];

    _settingsBtn.backgroundColor = VNPanel2();
    _settingsBtn.tintColor = VNAccent();

    [self updateVersionSelectionUI];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (UIImage *)imageNamedWebPOrPNG:(NSString *)baseName {
    UIImage *img = [UIImage imageNamed:baseName];
    if (img) return img;
    NSString *path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"webp"];
    if (path.length) { img = [UIImage imageWithContentsOfFile:path]; if (img) return img; }
    path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (path.length) img = [UIImage imageWithContentsOfFile:path];
    return img;
}

- (UIView *)makeCard { return VNMakeCard(); }

- (UIButton *)makeIconButton:(NSString *)systemName {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = VNPanel2();
    b.layer.cornerRadius = 10.0f;
    b.tintColor = VNAccent();
    UIImage *img = [UIImage systemImageNamed:systemName];
    if (img) [b setImage:img forState:UIControlStateNormal];
    return b;
}

- (void)beginAuthorization { [self updateAuthorizationPresentation]; [self refreshHUDState]; }
- (void)retryAuthorization:(id)sender { (void)sender; [self beginAuthorization]; }
- (void)revokeAuthorization {
    SetHUDEnabled(NO);
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
}

- (void)updateAuthorizationPresentation {
    if (!self.isViewLoaded) return;
    // License/Auth card giờ phản ánh trạng thái gate thật
    if (_unlocked) {
        _authorizationLabel.text = @"Đã kích hoạt";
        [_authorizationButton setTitle:@"Unlocked" forState:UIControlStateNormal];
        _authorizationButton.enabled = NO;
        _licenseValueLabel.text = @"Active";
        _authValueLabel.text = @"Hoạt động";
        _authValueLabel.textColor = VNAccent();
    } else {
        _authorizationLabel.text = @"Chưa kích hoạt";
        [_authorizationButton setTitle:@"Locked" forState:UIControlStateNormal];
        _authorizationButton.enabled = NO;
        _licenseValueLabel.text = @"—";
        _authValueLabel.text = @"—";
        _authValueLabel.textColor = VNMuted();
    }
    _authorizationLabel.textColor = VNText();
    _autoCleanSwitch.enabled = YES;
    _autoCleanLabel.alpha = 1.0;
    _startButton.alpha = 1.0;
}

#pragma mark - Build UI (giữ nguyên layout gốc)

- (void)buildUI {
    self.view.backgroundColor = VNBg();

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.backgroundColor = VNBg();
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.backgroundColor = VNBg();
    [_scrollView addSubview:_contentView];

    _settingsBtn = [self makeIconButton:@"gearshape.fill"];
    [_settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_settingsBtn];

    // Control card
    _controlCard = [self makeCard];
    [_contentView addSubview:_controlCard];
    _controlIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _controlIconView.contentMode = UIViewContentModeScaleAspectFill;
    _controlIconView.clipsToBounds = YES;
    _controlIconView.layer.cornerRadius = 12.0f;
    _controlIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _controlIconView.backgroundColor = VNPanel2();
    [_controlCard addSubview:_controlIconView];

    _controlTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlTitleLabel.text = @"Điều khiển HUD";
    _controlTitleLabel.font = VNFont(17, UIFontWeightBold);
    _controlTitleLabel.textColor = VNText();
    _controlTitleLabel.adjustsFontSizeToFitWidth = YES;
    _controlTitleLabel.minimumScaleFactor = 0.85f;
    [_controlCard addSubview:_controlTitleLabel];

    _controlSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _controlSubtitleLabel.text = @"Nhấn Bắt đầu khi game đã mở";
    _controlSubtitleLabel.font = VNFont(12, UIFontWeightMedium);
    _controlSubtitleLabel.textColor = VNMuted();
    _controlSubtitleLabel.numberOfLines = 2;
    [_controlCard addSubview:_controlSubtitleLabel];

    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _startButton.backgroundColor = VNAccent();
    _startButton.layer.cornerRadius = 12.0f;
    _startButton.titleLabel.font = VNFont(15, UIFontWeightBold);
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
    [_startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_startButton];

    _killAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _killAllButton.backgroundColor = VNPanel2();
    _killAllButton.layer.cornerRadius = 12.0f;
    _killAllButton.layer.borderWidth = 1.5f;
    _killAllButton.layer.borderColor = VNRed().CGColor;
    _killAllButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_killAllButton setTitleColor:VNRed() forState:UIControlStateNormal];
    [_killAllButton setTitle:@"Tắt hết" forState:UIControlStateNormal];
    [_killAllButton addTarget:self action:@selector(killAllTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_controlCard addSubview:_killAllButton];

    // Toggles card
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimbotLabel.text = @"Aimbot";
    _aimbotLabel.font = VNFont(17, UIFontWeightSemibold);
    _aimbotLabel.textColor = VNText();
    [_togglesCard addSubview:_aimbotLabel];
    _aimbotSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimbotSwitch.onTintColor = VNAccent();
    _aimbotSwitch.on = ESPPrefsBool(@"Aimbot", NO);
    [_aimbotSwitch addTarget:self action:@selector(aimbotSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimbotSwitch];

    _aimBehindWallLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimBehindWallLabel.text = @"Aim Behind Wall";
    _aimBehindWallLabel.font = VNFont(17, UIFontWeightSemibold);
    _aimBehindWallLabel.textColor = VNText();
    [_togglesCard addSubview:_aimBehindWallLabel];

    _aimBehindWallSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _aimBehindWallSwitch.onTintColor = VNAccent();
    _aimBehindWallSwitch.on = ESPPrefsBool(@"AimBehindWall", NO);
    [_aimBehindWallSwitch addTarget:self action:@selector(aimBehindWallSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_aimBehindWallSwitch];

    _silentAimLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _silentAimLabel.text = @"Silent Aim";
    _silentAimLabel.font = VNFont(17, UIFontWeightSemibold);
    _silentAimLabel.textColor = VNText();
    [_togglesCard addSubview:_silentAimLabel];
    _silentAimSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _silentAimSwitch.onTintColor = VNAccent();
    _silentAimSwitch.on = ESPPrefsBool(@"AimSilent", NO);
    [_silentAimSwitch addTarget:self action:@selector(silentAimSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_silentAimSwitch];

    _camLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camLabel.text = @"Camera Xa (CamPC)";
    _camLabel.font = VNFont(17, UIFontWeightSemibold);
    _camLabel.textColor = VNText();
    [_togglesCard addSubview:_camLabel];
    _camSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _camSwitch.onTintColor = VNAccent();
    _camSwitch.on = ESPPrefsBool(@"CamPC", NO);
    [_camSwitch addTarget:self action:@selector(camSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSwitch];

    _camSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _camSlider.minimumValue = 0.0f;
    _camSlider.maximumValue = 150.0f;
    _camSlider.value = ESPPrefsFloat(@"CamPCValue", 30.0f);
    _camSlider.minimumTrackTintColor = VNAccent();
    [_camSlider addTarget:self action:@selector(camSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_togglesCard addSubview:_camSlider];
    _camValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _camValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _camValueLabel.textColor = VNMuted();
    _camValueLabel.textAlignment = NSTextAlignmentRight;
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", _camSlider.value];
    [_togglesCard addSubview:_camValueLabel];

    // ESP card
    _espCard = [self makeCard];
    [_contentView addSubview:_espCard];
    _espCardTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCardTitle.text = @"ESP ELEMENTS";
    _espCardTitle.font = VNFont(13, UIFontWeightBold);
    _espCardTitle.textColor = VNMuted();
    [_espCard addSubview:_espCardTitle];

    _espLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLabel.text = @"Bật ESP";
    _espLabel.font = VNFont(17, UIFontWeightSemibold);
    _espLabel.textColor = VNText();
    [_espCard addSubview:_espLabel];
    _espSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espSwitch.onTintColor = VNAccent();
    _espSwitch.on = ESPPrefsBool(@"EnableESP", YES);
    [_espSwitch addTarget:self action:@selector(espSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espSwitch];

    _espBoxLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoxLabel.text = @"Box";
    _espBoxLabel.font = VNFont(17, UIFontWeightSemibold);
    _espBoxLabel.textColor = VNText();
    [_espCard addSubview:_espBoxLabel];
    _espBoxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoxSwitch.onTintColor = VNAccent();
    _espBoxSwitch.on = ESPPrefsBool(@"Box", YES);
    [_espBoxSwitch addTarget:self action:@selector(espBoxChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoxSwitch];

    _espLineLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espLineLabel.text = @"Snapline";
    _espLineLabel.font = VNFont(17, UIFontWeightSemibold);
    _espLineLabel.textColor = VNText();
    [_espCard addSubview:_espLineLabel];
    _espLineSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espLineSwitch.onTintColor = VNAccent();
    _espLineSwitch.on = ESPPrefsBool(@"Line", YES);
    [_espLineSwitch addTarget:self action:@selector(espLineChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espLineSwitch];

    _espBoneLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espBoneLabel.text = @"Bone / Skeleton";
    _espBoneLabel.font = VNFont(17, UIFontWeightSemibold);
    _espBoneLabel.textColor = VNText();
    [_espCard addSubview:_espBoneLabel];
    _espBoneSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espBoneSwitch.onTintColor = VNAccent();
    _espBoneSwitch.on = ESPPrefsBool(@"Bone", YES);
    [_espBoneSwitch addTarget:self action:@selector(espBoneChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espBoneSwitch];

    _espHealthLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espHealthLabel.text = @"Health Bar";
    _espHealthLabel.font = VNFont(17, UIFontWeightSemibold);
    _espHealthLabel.textColor = VNText();
    [_espCard addSubview:_espHealthLabel];
    _espHealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espHealthSwitch.onTintColor = VNAccent();
    _espHealthSwitch.on = ESPPrefsBool(@"Health", YES);
    [_espHealthSwitch addTarget:self action:@selector(espHealthChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espHealthSwitch];

    _espCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCountLabel.text = @"Player Count";
    _espCountLabel.font = VNFont(17, UIFontWeightSemibold);
    _espCountLabel.textColor = VNText();
    [_espCard addSubview:_espCountLabel];
    _espCountSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _espCountSwitch.onTintColor = VNAccent();
    _espCountSwitch.on = ESPPrefsBool(@"Count", YES);
    [_espCountSwitch addTarget:self action:@selector(espCountChanged:) forControlEvents:UIControlEventValueChanged];
    [_espCard addSubview:_espCountSwitch];

    _espDistanceLimitLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitLabel.text = @"Max Distance (m)";
    _espDistanceLimitLabel.font = VNFont(17, UIFontWeightSemibold);
    _espDistanceLimitLabel.textColor = VNText();
    [_espCard addSubview:_espDistanceLimitLabel];
    _espDistanceLimitValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _espDistanceLimitValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _espDistanceLimitValueLabel.textColor = VNMuted();
    _espDistanceLimitValueLabel.textAlignment = NSTextAlignmentRight;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f", ESPPrefsFloat(@"EspDistanceLimit", 150.0f)];
    [_espCard addSubview:_espDistanceLimitValueLabel];
    _espDistanceLimitSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _espDistanceLimitSlider.minimumValue = 20.0f;
    _espDistanceLimitSlider.maximumValue = 300.0f;
    _espDistanceLimitSlider.value = ESPPrefsFloat(@"EspDistanceLimit", 150.0f);
    _espDistanceLimitSlider.minimumTrackTintColor = VNAccent();
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitChanged:) forControlEvents:UIControlEventValueChanged];
    [_espDistanceLimitSlider addTarget:self action:@selector(espDistanceLimitCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_espCard addSubview:_espDistanceLimitSlider];

    // Aimbot card
    _aimCard = [self makeCard];
    [_contentView addSubview:_aimCard];
    _fovLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovLabel.text = @"FOV size";
    _fovLabel.font = VNFont(17, UIFontWeightSemibold);
    _fovLabel.textColor = VNText();
    [_aimCard addSubview:_fovLabel];

    _fovSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    _fovSlider.minimumValue = 30.0f;
    _fovSlider.maximumValue = 360.0f;
    _fovSlider.value = ESPPrefsFloat(@"Fov", 150.0f);
    _fovSlider.minimumTrackTintColor = VNAccent();
    [_fovSlider addTarget:self action:@selector(fovSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_fovSlider];

    _fovValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _fovValueLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _fovValueLabel.textColor = VNMuted();
    _fovValueLabel.textAlignment = NSTextAlignmentRight;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", _fovSlider.value];
    [_aimCard addSubview:_fovValueLabel];

    _triggerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _triggerLabel.text = @"Trigger";
    _triggerLabel.font = VNFont(17, UIFontWeightSemibold);
    _triggerLabel.textColor = VNText();
    [_aimCard addSubview:_triggerLabel];

    _triggerSegment = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"Fire", @"Scope", @"Both"]];
    {
        NSInteger idx = (NSInteger)ESPPrefsFloat(@"TriggerMode", 0.0f);
        if (idx < 0) idx = 0;
        if (idx > 3) idx = 3;
        _triggerSegment.selectedSegmentIndex = idx;
    }
    if (@available(iOS 13.0, *)) {
        _triggerSegment.selectedSegmentTintColor = VNAccent();
        _triggerSegment.backgroundColor = VNPanel2();
    }
    [_triggerSegment addTarget:self action:@selector(triggerSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_triggerSegment];

    _aimPosLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _aimPosLabel.text = @"Aim Position (Aimbot + Silent)";
    _aimPosLabel.font = VNFont(17, UIFontWeightSemibold);
    _aimPosLabel.textColor = VNText();
    [_aimCard addSubview:_aimPosLabel];

    _aimPosSegment = [[UISegmentedControl alloc] initWithItems:@[@"Đầu", @"Cổ", @"Thân"]];
    {
        NSInteger idx = (NSInteger)ESPPrefsFloat(@"AimPos", 0.0f);
        if (idx < 0) idx = 0;
        if (idx > 2) idx = 2;
        _aimPosSegment.selectedSegmentIndex = idx;
    }
    if (@available(iOS 13.0, *)) {
        _aimPosSegment.selectedSegmentTintColor = VNAccent();
        _aimPosSegment.backgroundColor = VNPanel2();
    }
    [_aimPosSegment addTarget:self action:@selector(aimPosSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    // Version section (chỉ FF)
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Phiên bản:";
    _versionSectionLabel.font = VNFont(14, UIFontWeightBold);
    _versionSectionLabel.textColor = VNMuted();
    [_contentView addSubview:_versionSectionLabel];

    _ffCard = [UIButton buttonWithType:UIButtonTypeCustom];
    _ffCard.backgroundColor = VNPanel2();
    _ffCard.layer.cornerRadius = 14.0f;
    _ffCard.clipsToBounds = YES;
    _ffCard.layer.borderWidth = 2.5f;
    _ffCard.layer.borderColor = VNAccent().CGColor;
    _ffCard.adjustsImageWhenHighlighted = NO;
    _ffCard.userInteractionEnabled = NO;
    [_contentView addSubview:_ffCard];

    _ffIconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _ffIconView.contentMode = UIViewContentModeScaleAspectFill;
    _ffIconView.clipsToBounds = YES;
    _ffIconView.layer.cornerRadius = 10.0f;
    _ffIconView.userInteractionEnabled = NO;
    _ffIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    [_ffCard addSubview:_ffIconView];

    _ffNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _ffNameLabel.text = @"Free Fire";
    _ffNameLabel.font = VNFont(14, UIFontWeightSemibold);
    _ffNameLabel.textColor = VNText();
    _ffNameLabel.textAlignment = NSTextAlignmentCenter;
    _ffNameLabel.userInteractionEnabled = NO;
    [_ffCard addSubview:_ffNameLabel];

    // Status card
    _statusCard = [self makeCard];
    [_contentView addSubview:_statusCard];
    _statusDot = [[UIView alloc] initWithFrame:CGRectZero];
    _statusDot.layer.cornerRadius = 6.0f;
    _statusDot.backgroundColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [_statusCard addSubview:_statusDot];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = VNFont(16, UIFontWeightSemibold);
    _statusLabel.textColor = VNText();
    _statusLabel.text = @"Trạng thái · Game chưa chạy";
    [_statusCard addSubview:_statusLabel];
    _openGameButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _openGameButton.backgroundColor = VNAccent();
    _openGameButton.layer.cornerRadius = 12.0f;
    _openGameButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_openGameButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_openGameButton setTitle:@"Vào Game" forState:UIControlStateNormal];
    [_openGameButton addTarget:self action:@selector(openGameTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_statusCard addSubview:_openGameButton];

    // License + auth
    _licenseCard = [self makeCard];
    [_contentView addSubview:_licenseCard];
    _licenseTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseTitleLabel.text = @"Giấy phép";
    _licenseTitleLabel.font = VNFont(13, UIFontWeightBold);
    _licenseTitleLabel.textColor = VNMuted();
    [_licenseCard addSubview:_licenseTitleLabel];
    _licenseValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _licenseValueLabel.font = VNFont(17, UIFontWeightBold);
    _licenseValueLabel.textColor = VNText();
    _licenseValueLabel.numberOfLines = 3;
    _licenseValueLabel.text = @"—";
    [_licenseCard addSubview:_licenseValueLabel];

    _authCard = [self makeCard];
    [_contentView addSubview:_authCard];
    _authTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authTitleLabel.text = @"Trạng thái";
    _authTitleLabel.font = VNFont(13, UIFontWeightBold);
    _authTitleLabel.textColor = VNMuted();
    [_authCard addSubview:_authTitleLabel];
    _authValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authValueLabel.font = VNFont(18, UIFontWeightBold);
    _authValueLabel.textColor = VNAccent();
    _authValueLabel.numberOfLines = 2;
    _authValueLabel.text = @"—";
    [_authCard addSubview:_authValueLabel];

    // Support
    _supportCard = [self makeCard];
    [_contentView addSubview:_supportCard];
    _supportTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportTitleLabel.text = @"Liên hệ hỗ trợ";
    _supportTitleLabel.font = VNFont(17, UIFontWeightSemibold);
    _supportTitleLabel.textColor = VNText();
    [_supportCard addSubview:_supportTitleLabel];
    _supportSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _supportSubtitleLabel.text = @"Nhấn Join để nhận hỗ trợ";
    _supportSubtitleLabel.font = VNFont(13, UIFontWeightMedium);
    _supportSubtitleLabel.textColor = VNMuted();
    [_supportCard addSubview:_supportSubtitleLabel];
    _joinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _joinButton.backgroundColor = VNAccent();
    _joinButton.layer.cornerRadius = 12.0f;
    _joinButton.titleLabel.font = VNFont(15, UIFontWeightBold);
    [_joinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_joinButton setTitle:@"Join" forState:UIControlStateNormal];
    [_joinButton addTarget:self action:@selector(joinSupportTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_supportCard addSubview:_joinButton];

    // Extra
    _extraCard = [self makeCard];
    [_contentView addSubview:_extraCard];
    _autoCleanLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _autoCleanLabel.text = @"VarClean before HUD";
    _autoCleanLabel.font = VNFont(16, UIFontWeightSemibold);
    _autoCleanLabel.textColor = VNText();
    [_extraCard addSubview:_autoCleanLabel];
    _autoCleanSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _autoCleanSwitch.onTintColor = VNAccent();
    _autoCleanSwitch.on = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    [_autoCleanSwitch addTarget:self action:@selector(autoCleanSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_extraCard addSubview:_autoCleanSwitch];
    _authorizationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _authorizationLabel.font = VNFont(14, UIFontWeightSemibold);
    _authorizationLabel.textColor = VNText();
    [_extraCard addSubview:_authorizationLabel];
    _authorizationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authorizationButton.titleLabel.font = VNFont(14, UIFontWeightBold);
    [_authorizationButton setTitleColor:VNAccent() forState:UIControlStateNormal];
    [_authorizationButton addTarget:self action:@selector(retryAuthorization:) forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    [self applyTheme];
}

#pragma mark - Gate overlay (thêm mới)

- (void)buildGateOverlay {
    _gateOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _gateOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _gateOverlay.backgroundColor = VNBg();
    UIActivityIndicatorViewStyle spinnerStyle;
    if (@available(iOS 13.0, *)) spinnerStyle = UIActivityIndicatorViewStyleLarge;
    else spinnerStyle = UIActivityIndicatorViewStyleWhiteLarge;
    _gateSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:spinnerStyle];
    _gateSpinner.color = VNAccent();
    [_gateSpinner startAnimating];
    [_gateOverlay addSubview:_gateSpinner];
    _gateLabel = [[UILabel alloc] init];
    _gateLabel.textColor = VNText();
    _gateLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _gateLabel.textAlignment = NSTextAlignmentCenter;
    _gateLabel.numberOfLines = 0;
    [_gateOverlay addSubview:_gateLabel];
    [self.view addSubview:_gateOverlay];
}

- (void)showGateMessage:(NSString *)t {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showGateMessage:t]; });
        return;
    }
    _gateLabel.text = t ?: @"";
    [self.view setNeedsLayout];
}

- (void)presentSafely:(UIViewController *)vc {
    if (!vc) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self presentSafely:vc]; });
        return;
    }
    if (!self.isViewLoaded || !self.view.window) {
        __weak __typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong __typeof(ws) ss = ws;
            [ss presentSafely:vc];
        });
        return;
    }
    UIViewController *top = self;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    if (top.presentedViewController && top.presentedViewController.isBeingDismissed) {
        __weak __typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong __typeof(ws) ss = ws;
            [ss presentSafely:vc];
        });
        return;
    }
    if ([top isKindOfClass:[UIAlertController class]]) {
        __weak __typeof(self) ws = self;
        [top dismissViewControllerAnimated:NO completion:^{
            __strong __typeof(ws) ss = ws;
            [ss presentSafely:vc];
        }];
        return;
    }
    [top presentViewController:vc animated:YES completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    _scrollView.frame = self.view.bounds;

    CGFloat gear = 44.0f;
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, insets.top + 8, gear, gear);

    CGFloat contentW = width;
    CGFloat xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 62.0f;

    // CONTROL
    CGFloat controlH = 100.0f;
    _controlCard.frame = CGRectMake(xPad, y, cardW, controlH);
    CGFloat iconSize = 64.0f;
    _controlIconView.frame = CGRectMake(14, (controlH - iconSize) * 0.5f, iconSize, iconSize);
    CGFloat btnW = 96;
    _startButton.frame = CGRectMake(cardW - btnW - 16, 18, btnW, 36);
    _killAllButton.frame = CGRectMake(cardW - btnW - 16, 60, btnW, 32);
    CGFloat textX = 14 + iconSize + 12;
    CGFloat textW = cardW - btnW - textX - 10;
    _controlTitleLabel.frame = CGRectMake(textX, 22, textW, 24);
    _controlSubtitleLabel.frame = CGRectMake(textX, 48, textW, 36);
    y = CGRectGetMaxY(_controlCard.frame) + 16;

    // TOGGLES
    CGFloat toggleRowH = 62.0f;
    CGFloat sliderAreaH = 82.0f;
    CGFloat togglesH = toggleRowH * 4 + sliderAreaH;
    _togglesCard.frame = CGRectMake(xPad, y, cardW, togglesH);
    CGFloat rowY = 0;
    _aimbotLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _aimbotSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;
    _aimBehindWallLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _aimBehindWallSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;
    _silentAimLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _silentAimSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;
    _camLabel.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
    _camSwitch.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
    rowY += toggleRowH;
    _camSlider.frame = CGRectMake(20, rowY + 24, cardW - 100, 30);
    _camValueLabel.frame = CGRectMake(cardW - 64, rowY + 26, 48, 26);
    y = CGRectGetMaxY(_togglesCard.frame) + 16;

    // ESP
    CGFloat espTitleH = 40.0f;
    CGFloat espRowH = 60.0f;
    CGFloat espSliderArea = 82.0f;
    CGFloat espH = espTitleH + espRowH * 6 + espSliderArea;
    _espCard.frame = CGRectMake(xPad, y, cardW, espH);
    _espCardTitle.frame = CGRectMake(20, 14, cardW - 40, 20);
    _espLabel.frame = CGRectMake(20, espTitleH, cardW - 110, espRowH);
    _espSwitch.frame = CGRectMake(cardW - 71, espTitleH + (espRowH - 31) * 0.5f, 51, 31);
    NSArray<UILabel *> *espLabelsArr = @[_espBoxLabel, _espLineLabel, _espBoneLabel,
                                          _espHealthLabel, _espCountLabel];
    NSArray<UISwitch *> *espSwitchesArr = @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                                             _espHealthSwitch, _espCountSwitch];
    CGFloat espY = espTitleH + espRowH;
    for (NSUInteger i = 0; i < 5; i++) {
        UILabel *l = espLabelsArr[i];
        UISwitch *s = espSwitchesArr[i];
        l.frame = CGRectMake(20, espY, cardW - 110, espRowH);
        s.frame = CGRectMake(cardW - 71, espY + (espRowH - 31) * 0.5f, 51, 31);
        espY += espRowH;
    }
    _espDistanceLimitLabel.frame = CGRectMake(20, espY, cardW - 110, 30);
    _espDistanceLimitValueLabel.frame = CGRectMake(cardW - 64, espY, 48, 30);
    _espDistanceLimitSlider.frame = CGRectMake(20, espY + 34, cardW - 40, 30);
    y = CGRectGetMaxY(_espCard.frame) + 16;

    // AIM
    CGFloat fovAreaH = 90.0f;
    CGFloat segAreaH = 100.0f;
    CGFloat aimH = fovAreaH + segAreaH * 2;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimH);
    _fovLabel.frame = CGRectMake(20, 18, 140, 24);
    _fovValueLabel.frame = CGRectMake(cardW - 64, 18, 48, 24);
    _fovSlider.frame = CGRectMake(20, 50, cardW - 40, 30);
    _triggerLabel.frame = CGRectMake(20, fovAreaH + 14, 140, 24);
    _triggerSegment.frame = CGRectMake(20, fovAreaH + 46, cardW - 40, 38);
    _aimPosLabel.frame = CGRectMake(20, fovAreaH + segAreaH + 14, 220, 24);
    _aimPosSegment.frame = CGRectMake(20, fovAreaH + segAreaH + 46, cardW - 40, 38);
    y = CGRectGetMaxY(_aimCard.frame) + 22;

    // VERSION (FF only, full width)
    _versionSectionLabel.frame = CGRectMake(xPad + 4, y, cardW - 8, 22);
    y = CGRectGetMaxY(_versionSectionLabel.frame) + 10;
    CGFloat versionH = 136.0f;
    _ffCard.frame = CGRectMake(xPad, y, cardW, versionH);
    CGFloat iconSide = 68.0f;
    _ffIconView.frame = CGRectMake((cardW - iconSide) * 0.5f, 20, iconSide, iconSide);
    _ffNameLabel.frame = CGRectMake(8, 96, cardW - 16, 24);
    y = CGRectGetMaxY(_ffCard.frame) + 16;

    // STATUS
    CGFloat statusH = 72.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(20, (statusH - 12) * 0.5f, 12, 12);
    _openGameButton.frame = CGRectMake(cardW - 116, (statusH - 38) * 0.5f, 100, 38);
    _statusLabel.frame = CGRectMake(42, 0, cardW - 116 - 50, statusH);
    y = CGRectGetMaxY(_statusCard.frame) + 16;

    // INFO
    CGFloat infoH = 60.0f;
    _licenseCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _licenseTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _licenseValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_licenseCard.frame) + 1;
    _authCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _authTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _authValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_authCard.frame) + 16;

    // SUPPORT
    CGFloat supportH = 80.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 96, (supportH - 38) * 0.5f, 80, 38);
    _supportTitleLabel.frame = CGRectMake(20, 20, cardW - 130, 26);
    _supportSubtitleLabel.frame = CGRectMake(20, 48, cardW - 130, 20);
    y = CGRectGetMaxY(_supportCard.frame) + 16;

    // EXTRA
    CGFloat extraH = 104.0f;
    _extraCard.frame = CGRectMake(xPad, y, cardW, extraH);
    _autoCleanLabel.frame = CGRectMake(20, 18, cardW - 100, 26);
    CGSize sw = _autoCleanSwitch.intrinsicContentSize;
    _autoCleanSwitch.frame = CGRectMake(cardW - sw.width - 20, 18, sw.width, sw.height);
    _authorizationLabel.frame = CGRectMake(20, 58, cardW - 170, 30);
    _authorizationButton.frame = CGRectMake(cardW - 140, 58, 120, 30);
    y = CGRectGetMaxY(_extraCard.frame) + 24 + insets.bottom;

    _contentView.frame = CGRectMake(0, 0, contentW, MAX(y, height));
    _scrollView.contentSize = _contentView.bounds.size;

    // Gate overlay
    _gateOverlay.frame = self.view.bounds;
    CGFloat cy = self.view.bounds.size.height/2;
    _gateSpinner.center = CGPointMake(self.view.bounds.size.width/2, cy - 20);
    _gateLabel.frame = CGRectMake(24, cy + 12, self.view.bounds.size.width - 48, 60);
}

#pragma mark - Gate flow (thêm mới)

- (void)runGate {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self runGate]; });
        return;
    }
    [self showGateMessage:[self isVi] ? OXR("Đang kiểm tra…") : OXR("Checking…")];
    __weak __typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong __typeof(ws) ss = ws;
        if (!ss) return;
        NSString *msg = nil;
        NSInteger st = [LicenseGate maintenance:&msg];
        if (st == 1) {
            dispatch_async(dispatch_get_main_queue(), ^{ [ss showMaintenance:msg]; });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [ss afterMaintenance]; });
    });
}

- (void)afterMaintenance {
    if (![[NSUserDefaults standardUserDefaults] stringForKey:UD_LANG()]) {
        [self pickLanguageThen:^{ [self tryAutoLogin]; }];
    } else {
        [self tryAutoLogin];
    }
}

- (void)tryAutoLogin {
    NSString *saved = [LicenseGate loadKey];
    if (saved.length > 0) {
        [self showGateMessage:[self isVi] ? OXR("Đang xác thực key…") : OXR("Verifying key…")];
        __weak __typeof(self) ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSInteger r = [LicenseGate verify:saved];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong __typeof(ws) ss = ws;
                if (!ss) return;
                if (r == 0) [ss unlock:saved];
                else { [LicenseGate forgetKey]; [ss promptKey]; }
            });
        });
    } else { [self promptKey]; }
}

- (void)promptKey {
    BOOL vi = [self isVi];
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:OXR("VN TOOL FIFAI")
        message:vi ? OXR("Nhập license key để kích hoạt") : OXR("Enter license key to activate")
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = OXR("");
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:(vi?OXR("Kích hoạt"):OXR("Activate"))
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            NSString *k = [ac.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (k.length == 0) {
                __weak __typeof(self) ws = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    __strong __typeof(ws) ss = ws;
                    [ss promptKey];
                });
                return;
            }
            [self showGateMessage:vi ? OXR("Đang xác thực…") : OXR("Verifying…")];
            __weak __typeof(self) ws = self;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSInteger r = [LicenseGate verify:k];
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong __typeof(ws) ss = ws;
                    if (!ss) return;
                    if (r == 0) { [LicenseGate saveKey:k]; [ss unlock:k]; }
                    else        { [ss showKeyError:r]; }
                });
            });
        }]];
    [ac addAction:[UIAlertAction actionWithTitle:(vi?OXR("Thoát"):OXR("Exit"))
        style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ exit(0); }]];
    [self presentSafely:ac];
}

- (void)showKeyError:(NSInteger)r {
    BOOL vi = [self isVi];
    NSString *m;
    switch (r) {
        case 1: m = vi ? OXR("Key không tồn tại.") : OXR("Key does not exist."); break;
        case 2: m = vi ? OXR("Key đã bị thu hồi hoặc hết hạn.") : OXR("Key revoked or expired."); break;
        case 3: m = vi ? OXR("Key đã vượt số máy cho phép.") : OXR("Device limit exceeded."); break;
        case 4: m = vi ? OXR("Không kết nối được server.") : OXR("Server connection failed."); break;
        default: m = vi ? OXR("Key không hợp lệ.") : OXR("Invalid key.");
    }
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:(vi?OXR("Sai key"):OXR("Wrong key")) message:m
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:(vi?OXR("Thử lại"):OXR("Retry"))
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [self promptKey]; }]];
    [ac addAction:[UIAlertAction actionWithTitle:(vi?OXR("Thoát"):OXR("Exit"))
        style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ exit(0); }]];
    [self presentSafely:ac];
}

- (void)pickLanguageThen:(void(^)(void))next {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:OXR("🌐 Ngôn ngữ / Language")
        message:OXR("Chọn ngôn ngữ / Choose language")
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:OXR("🇻🇳  Tiếng Việt")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [[NSUserDefaults standardUserDefaults] setObject:OXR("vi") forKey:UD_LANG()]; if (next) next();
        }]];
    [ac addAction:[UIAlertAction actionWithTitle:OXR("🇺🇸  English")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [[NSUserDefaults standardUserDefaults] setObject:OXR("en") forKey:UD_LANG()]; if (next) next();
        }]];
    [self presentSafely:ac];
}

- (void)showMaintenance:(NSString *)msg {
    BOOL vi = [self isVi];
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:(vi?OXR("🛠 Bảo trì"):OXR("🛠 Maintenance"))
        message:(msg.length ? msg : (vi ? OXR("Server đang bảo trì.") : OXR("Server is under maintenance.")))
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:OXR("OK")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ exit(0); }]];
    [self presentSafely:ac];
}

- (void)showExpiryFor:(NSString *)key {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *f = [LicenseGate fetch:key];
        NSString *iso = f[OXR("expires_at")][OXR("timestampValue")] ?: f[OXR("expires_at")][OXR("stringValue")];
        if (!iso.length) return;
        NSDate *exp = [LicenseGate parseISO:iso];
        if (!exp) return;
        NSTimeInterval s = [exp timeIntervalSinceNow];
        if (s <= 0) return;
        long days = (long)(s/86400);
        long h = (long)((s - days*86400)/3600);
        long m = (long)((s - days*86400 - h*3600)/60);
        BOOL vi = [self isVi];
        NSString *timeStr = days > 0
            ? (vi ? [NSString stringWithFormat:OXR("%ld ngày %02ld giờ %02ld phút"), days,h,m]
                  : [NSString stringWithFormat:OXR("%ld days %02ldh %02ldm"), days,h,m])
            : (vi ? [NSString stringWithFormat:OXR("%02ld giờ %02ld phút"), h,m]
                  : [NSString stringWithFormat:OXR("%02ldh %02ldm"), h,m]);
        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = OXR("dd/MM/yyyy HH:mm");
        NSString *expStr = [df stringFromDate:exp];
        NSString *title = vi ? OXR("🔑 Key của bạn") : OXR("🔑 Your License");
        NSString *msg = vi
            ? [NSString stringWithFormat:OXR("Còn lại: %@\nHết hạn: %@"), timeStr, expStr]
            : [NSString stringWithFormat:OXR("Remaining: %@\nExpires: %@"), timeStr, expStr];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:OXR("OK") style:UIAlertActionStyleDefault handler:nil]];
            [self presentSafely:ac];
        });
    });
}

- (void)unlock:(NSString *)verifiedKey {
    _unlocked = YES;
    self.vaultedKey = VaultPut(verifiedKey);

    // Hiện UI chính
    _scrollView.hidden = NO;
    _settingsBtn.hidden = NO;

    [UIView animateWithDuration:0.25 animations:^{
        self->_gateOverlay.alpha = 0;
    } completion:^(BOOL fin){
        [self->_gateOverlay removeFromSuperview];
        self->_gateOverlay = nil;
    }];

    _lastGameRunning = [self isGameRunning];
    [self updateAuthorizationPresentation];
    [self refreshHUDState];
    [self startPollingGameState];
    [self startMaintenancePolling];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self showExpiryFor:verifiedKey]; });
}

- (void)startMaintenancePolling {
    __weak __typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(60*NSEC_PER_SEC)),
        dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        __typeof(self) ss = ws; if (!ss) return;
        NSString *msg = nil;
        if ([LicenseGate maintenance:&msg] == 1) {
            dispatch_async(dispatch_get_main_queue(), ^{ [ss showMaintenance:msg]; });
            return;
        }
        [ss startMaintenancePolling];
    });
}

// Giữ để tránh warning (không dùng ở đây)
- (void)_touchLastGameRunning { (void)_lastGameRunning; }

#pragma mark - Version selection

- (void)updateVersionSelectionUI {
    _ffCard.layer.borderColor = VNAccent().CGColor;
    _ffCard.backgroundColor = VNPanel2();
    UIImage *icon = [self imageNamedWebPOrPNG:@"ff"];
    if (icon) _controlIconView.image = icon;
}

#pragma mark - App lifecycle

- (void)appBecameActive {
    if (IsBeingTraced() || DyldHasHookFramework() || FridaGadgetActive() || CanarySwizzled()) exit(0);
    if (!_unlocked) return;
    GameOffsetsReload();
    [self applyTheme];
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}

- (void)appResignedActive {
    if (self.vaultedKey) {
        NSString *plain = VaultGet(self.vaultedKey);
        if (plain) {
            SessionKeyReroll();
            self.vaultedKey = VaultPut(plain);
        }
    }
}

#pragma mark - HUD / game

- (BOOL)isGameRunning {
    return GameTargetIsRunning();
}

- (void)startPollingGameState {
    __weak __typeof(self) weakSelf = self;
    [_pollTimer invalidate];
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   repeats:YES
                                                     block:^(NSTimer *timer) {
        __typeof(self) ss = weakSelf;
        if (!ss || !ss.unlocked) return;
        [ss refreshHUDState];
    }];
}

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"AutoVarCleanBeforeHUD"];
}

- (void)aimbotSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Aimbot", sender.on);
    ESPSyncFromPrefs();
}

- (void)silentAimSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimSilent=%d (FOV=%.0f, AimPos=%d)",
          (int)sender.on,
          ESPPrefsFloat(@"Fov", 150.0f),
          (int)ESPPrefsFloat(@"AimPos", 0.0f));
}

- (void)espSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"EnableESP", sender.on);
    ESPSyncFromPrefs();
}

- (void)camSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"CamPC", sender.on);
    ESPSyncFromPrefs();
}

- (void)camSliderChanged:(UISlider *)sender {
    float v = sender.value;
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloatLive(@"CamPCValue", v);
}

- (void)fovSliderChanged:(UISlider *)sender {
    float v = sender.value;
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloatLive(@"Fov", v);
}

- (void)espBoxChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Box", sender.on);
    ESPSyncFromPrefs();
}
- (void)espLineChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Line", sender.on);
    ESPSyncFromPrefs();
}
- (void)espBoneChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Bone", sender.on);
    ESPSyncFromPrefs();
}
- (void)espHealthChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Health", sender.on);
    ESPSyncFromPrefs();
}
- (void)espCountChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Count", sender.on);
    ESPSyncFromPrefs();
}

- (void)espDistanceLimitChanged:(UISlider *)sender {
    float v = sender.value;
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f", v];
    ESPPrefsSetFloatLive(@"EspDistanceLimit", v);
}

- (void)espDistanceLimitCommitted:(UISlider *)sender {
    ESPPrefsSetFloat(@"EspDistanceLimit", sender.value);
    ESPSyncFromPrefs();
}

- (void)triggerSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"TriggerMode"];
    [std setFloat:v forKey:@"TriggerMode_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"TriggerMode", v);
    ESPSyncFromPrefs();
    NSLog(@"[VN] TriggerMode set to %.0f", v);
}

- (void)aimPosSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"AimPos"];
    [std setFloat:v forKey:@"AimPos_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"AimPos", v);
    ESPSyncFromPrefs();
    NSLog(@"[VN] AimPos set to %.0f", v);
}

- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSyncFromPrefs();
}

#pragma mark - Start / Kill All

- (void)startButtonTapped:(UIButton *)sender {
    (void)sender;
    if (!_unlocked) return;
    BOOL hudOn = IsHUDEnabled();
    if (hudOn) {
        ++_hudRequestSerial;
        _pendingHUDEnableUntil = 0;
        SetHUDEnabled(NO);
        [self refreshHUDState];
        return;
    }

    NSInteger requestSerial = ++_hudRequestSerial;
    _startButton.enabled = NO;
    [self startHUDForRequest:requestSerial];
}

- (void)startHUDForRequest:(NSInteger)requestSerial {
    _pendingHUDEnableUntil = CACurrentMediaTime() + 2.5;
    GameOffsetsReload();
    BOOL autoClean = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    if (!autoClean) {
        // Log nằm ở tab riêng — LogViewController tự set kernelBootLog.
        kernelBootStart();
        self.startButton.enabled = YES;
        [self refreshHUDState];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[varCleanController sharedInstance] runVarCleanNowWithCompletion:^(BOOL authorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestSerial != self.hudRequestSerial || !authorized) {
                    self.pendingHUDEnableUntil = 0;
                    [self refreshHUDState];
                    return;
                }
                SetHUDEnabled(YES);
                self.startButton.enabled = YES;
                [self refreshHUDState];
            });
        }];
    });
}

- (void)killAllTapped:(id)sender {
    (void)sender;

    ++_hudRequestSerial;
    _pendingHUDEnableUntil = 0;

    SetHUDEnabled(NO);

    ESPPrefsSetBoolLive(@"Aimbot", NO);
    ESPPrefsSetBoolLive(@"AimSilent", NO);
    ESPPrefsSetBoolLive(@"EnableESP", NO);
    ESPPrefsSetBoolLive(@"CamPC", NO);
    ESPPrefsSetBoolLive(@"Box", NO);
    ESPPrefsSetBoolLive(@"Line", NO);
    ESPPrefsSetBoolLive(@"Bone", NO);
    ESPPrefsSetBoolLive(@"Health", NO);
    ESPPrefsSetBoolLive(@"Count", NO);
    ESPPrefsSetBoolLive(@"AimBehindWall", NO);

    ESPSyncFromPrefs();

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.aimbotSwitch setOn:NO animated:YES];
        [self.silentAimSwitch setOn:NO animated:YES];
        [self.espSwitch setOn:NO animated:YES];
        [self.camSwitch setOn:NO animated:YES];
        [self.espBoxSwitch setOn:NO animated:YES];
        [self.espLineSwitch setOn:NO animated:YES];
        [self.espBoneSwitch setOn:NO animated:YES];
        [self.espHealthSwitch setOn:NO animated:YES];
        [self.espCountSwitch setOn:NO animated:YES];
        [self.aimBehindWallSwitch setOn:NO animated:YES];

        [self refreshHUDState];
    });
}

#pragma mark - Open game / support

- (void)openGameTapped:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"vn.vng.freefireth://"];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app canOpenURL:url]) {
        [app openURL:url options:@{} completionHandler:nil];
        return;
    }
    NSArray<NSString *> *fallbacks = @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) {
            [app openURL:u options:@{} completionHandler:nil];
            return;
        }
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Không mở được game"
                                            message:@"Hãy mở Free Fire thủ công, rồi quay lại nhấn Bắt đầu."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)joinSupportTapped:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://t.me/vntool"];
    if (!url) return;
    if (@available(iOS 9.0, *)) {
        SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:svc animated:YES completion:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)refreshHUDState {
    if (!self.isViewLoaded) return;
    if (!_unlocked) return;
    GameOffsetsReload();

    BOOL gameIsRunning = [self isGameRunning];
    BOOL hudIsEnabled = IsHUDEnabled();
    _gameMissingStreak = gameIsRunning ? 0 : _gameMissingStreak + 1;
    BOOL gameIsAvailable = gameIsRunning || _gameMissingStreak < 8;

    if (gameIsRunning) {
        _statusDot.backgroundColor = VNAccent();
        _statusLabel.text = @"Trạng thái · Free Fire đang chạy";
    } else {
        _statusDot.backgroundColor = VNRed();
        _statusLabel.text = @"Trạng thái · Game chưa chạy";
    }

    if (!gameIsAvailable) {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.enabled = YES;
        _startButton.alpha = 1.0;
        _controlSubtitleLabel.alpha = 1.0;
        _pendingHUDEnableUntil = 0;
        _startButton.backgroundColor = VNAccent();
        return;
    }

    _startButton.enabled = YES;
    _startButton.alpha = 1.0;
    _controlSubtitleLabel.alpha = 1.0;

    CFTimeInterval now = CACurrentMediaTime();
    BOOL isWithinEnableGracePeriod = _pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil;
    if (!hudIsEnabled && isWithinEnableGracePeriod) {
        [_startButton setTitle:@"Đang bật…" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccentDim();
        return;
    }

    if (hudIsEnabled) {
        _pendingHUDEnableUntil = 0;
        [_startButton setTitle:@"Tắt HUD" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNPanel2();
    } else {
        [_startButton setTitle:@"Bắt đầu" forState:UIControlStateNormal];
        _startButton.backgroundColor = VNAccent();
    }
}

@end
