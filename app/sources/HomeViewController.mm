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
#import "VNLog.h"
#import "oxorany/oxorany.h"

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonRandom.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <pthread.h>

#ifndef oxorany_pchar
  #define oxorany_pchar(s) ((const char *)oxorany(s))
#endif
#define OXR(s)         [NSString stringWithUTF8String:oxorany_pchar(s)]
#define CAT2(a,b)      [NSString stringWithFormat:OXR("%@%@"),    (a),(b)]
#define CAT3(a,b,c)    [NSString stringWithFormat:OXR("%@%@%@"),  (a),(b),(c)]
#define CAT4(a,b,c,d)  [NSString stringWithFormat:OXR("%@%@%@%@"),(a),(b),(c),(d)]

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
    v.clipsToBounds = YES;
    return v;
}
static UIFont *VNFont(CGFloat size, UIFontWeight weight) {
    return [UIFont systemFontOfSize:size weight:weight];
}

#pragma mark - ===== License crypto (server key) =====

static uint8_t  gSessionKM[64];
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
    _hkdfSha256(seed, sizeof(seed), idfvD.bytes, idfvD.length,
                info, strlen(info), gSessionKM, sizeof(gSessionKM));
    memset(seed, 0, sizeof(seed));
}
static void SessionKeyEnsure(void) { pthread_once(&gOnce, _initSessionKey); }

static void SessionKeyReroll(void) {
    uint8_t seed[32];
    CCRandomGenerateBytes(seed, sizeof(seed));
    NSString *idfv = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"x";
    NSData   *idfvD = [idfv dataUsingEncoding:NSUTF8StringEncoding];
    const char *info = "vntool.vault.session.v1";
    _hkdfSha256(seed, sizeof(seed), idfvD.bytes, idfvD.length,
                info, strlen(info), gSessionKM, sizeof(gSessionKM));
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
                gSessionKM, 32, iv, raw.bytes, raw.length,
                (uint8_t *)ct.mutableBytes, outCap, &outLen) != kCCSuccess) return nil;
    ct.length = outLen;
    NSMutableData *blob = [NSMutableData dataWithCapacity:sizeof(iv) + outLen + 32];
    [blob appendBytes:iv length:sizeof(iv)];
    [blob appendData:ct];
    uint8_t tag[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, gSessionKM + 32, 32, blob.bytes, blob.length, tag);
    [blob appendBytes:tag length:sizeof(tag)];
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
                gSessionKM, 32, p, p + kCCBlockSizeAES128, ctLen,
                (uint8_t *)pt.mutableBytes, outCap, &outLen) != kCCSuccess) return nil;
    pt.length = outLen;
    return [[NSString alloc] initWithData:pt encoding:NSUTF8StringEncoding];
}

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

static NSData *HKDF(NSData *ikm, NSData *salt, NSData *info, size_t outLen) {
    uint8_t prk[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, ikm.bytes, ikm.length, prk);
    NSMutableData *out = [NSMutableData data];
    uint8_t T[CC_SHA256_DIGEST_LENGTH]; size_t Tlen = 0; uint8_t ctr = 1;
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

@interface PinnedDelegate : NSObject <NSURLSessionDelegate>
+ (instancetype)shared;
@end
@implementation PinnedDelegate
+ (instancetype)shared {
    static PinnedDelegate *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [PinnedDelegate new]; });
    return s;
}
- (void)URLSession:(NSURLSession *)s
didReceiveChallenge:(NSURLAuthenticationChallenge *)ch
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))cb {
    SecTrustRef trust = ch.protectionSpace.serverTrust;
    if (!trust) { cb(NSURLSessionAuthChallengePerformDefaultHandling, nil); return; }
    cb(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
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

static NSString *FB_PROJECT(void)    { return CAT3(OXR("vntool"), OXR("-"), OXR("license")); }
static NSString *FB_COLLECTION(void) { return CAT2(OXR("licen"), OXR("ses")); }
static NSString *UD_LANG(void)       { return CAT2(OXR("vntool_"), OXR("lang")); }
static NSString *KC_KEY(void)        { return CAT2(OXR("VN_LIC_"), OXR("V3")); }

static NSString *FirestoreBase(void) {
    return CAT4(OXR("https://"), OXR("firestore."), OXR("googleapis.com"), OXR("/v1"));
}
static NSString *DocPath(NSString *col, NSString *id_) {
    return [NSString stringWithFormat:
        CAT4(OXR("%@/projects/"), OXR("%@/databases/"), OXR("(default)/documents/"), OXR("%@/%@")),
        FirestoreBase(), FB_PROJECT(), col, id_];
}

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
             OXR("&updateMask.fieldPaths=activations"), OXR(""))];
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
    NSData *blob = EtM_Encrypt([key dataUsingEncoding:NSUTF8StringEncoding]);
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

#pragma mark - Log sink

static void HomeVCBootLogSink(NSString *line) {
    [[VNLog shared] append:line];
}

#pragma mark - Home

@interface HomeViewController ()
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
@property (nonatomic, strong) UIButton *ffMaxCard;
@property (nonatomic, strong) UIButton *ffCard;
@property (nonatomic, strong) UIImageView *ffMaxIconView;
@property (nonatomic, strong) UIImageView *ffIconView;
@property (nonatomic, strong) UILabel *ffMaxNameLabel;
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

@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSInteger gameMissingStreak;
@property (nonatomic, assign) CFTimeInterval pendingHUDEnableUntil;
@property (nonatomic, assign) NSInteger hudRequestSerial;

// Gate
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
    [self buildUI];
    [self buildGateOverlay];
    self.scrollView.hidden = YES;
    self.settingsBtn.hidden = YES;
    [self showGateMessage:[self isVi] ? OXR("Đang kiểm tra…") : OXR("Checking…")];

    _gameMissingStreak = 0;
    _pendingHUDEnableUntil = 0;
    _hudRequestSerial = 0;
    _unlocked = NO;

    GameOffsetsReload();
    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(appBecameActive)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(appResignedActive)
        name:UIApplicationWillResignActiveNotification object:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.2*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self runGate]; });
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

#pragma mark - Theme

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
    for (UILabel *l in @[_aimbotLabel, _aimBehindWallLabel, _silentAimLabel, _camLabel])
        l.textColor = VNText();
    for (UISwitch *s in @[_aimbotSwitch, _aimBehindWallSwitch, _silentAimSwitch, _camSwitch])
        s.onTintColor = VNAccent();
    _camSlider.minimumTrackTintColor = VNAccent();
    _camValueLabel.textColor = VNMuted();

    _espCard.backgroundColor = VNCard();
    _espCardTitle.textColor = VNMuted();
    for (UILabel *l in @[_espLabel, _espBoxLabel, _espLineLabel, _espBoneLabel,
                          _espHealthLabel, _espCountLabel, _espDistanceLimitLabel])
        l.textColor = VNText();
    for (UISwitch *s in @[_espSwitch, _espBoxSwitch, _espLineSwitch, _espBoneSwitch,
                           _espHealthSwitch, _espCountSwitch])
        s.onTintColor = VNAccent();
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
    _ffMaxCard.backgroundColor = VNCard();
    _ffCard.backgroundColor = VNCard();
    _ffMaxNameLabel.textColor = VNText();
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

- (UIButton *)makeVersionCardCapturingIcon:(UIImageView * __strong *)outIcon
                                 nameLabel:(UILabel * __strong *)outName {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.backgroundColor = VNCard();
    card.layer.cornerRadius = 14.0f;
    card.clipsToBounds = YES;
    card.layer.borderWidth = 2.0f;
    card.layer.borderColor = [UIColor clearColor].CGColor;
    card.adjustsImageWhenHighlighted = NO;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.clipsToBounds = YES;
    icon.layer.cornerRadius = 10.0f;
    icon.userInteractionEnabled = NO;
    [card addSubview:icon];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero];
    name.font = VNFont(14, UIFontWeightSemibold);
    name.textColor = VNText();
    name.textAlignment = NSTextAlignmentCenter;
    name.userInteractionEnabled = NO;
    [card addSubview:name];

    if (outIcon) *outIcon = icon;
    if (outName) *outName = name;
    return card;
}

#pragma mark - Build UI (giữ nguyên bản gốc)

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

    // ===== CONTROL CARD =====
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

    // ===== TOGGLES CARD =====
    _togglesCard = [self makeCard];
    [_contentView addSubview:_togglesCard];

    _aimbotLabel = [self makeToggleLabel:@"Aimbot" inCard:_togglesCard];
    _aimbotSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Aimbot", NO)
                                    action:@selector(aimbotSwitchChanged:) inCard:_togglesCard];

    _aimBehindWallLabel = [self makeToggleLabel:@"Aim Behind Wall" inCard:_togglesCard];
    _aimBehindWallSwitch = [self makeToggleSwitch:ESPPrefsBool(@"AimBehindWall", NO)
                                           action:@selector(aimBehindWallSwitchChanged:) inCard:_togglesCard];

    _silentAimLabel = [self makeToggleLabel:@"Silent Aim" inCard:_togglesCard];
    _silentAimSwitch = [self makeToggleSwitch:ESPPrefsBool(@"AimSilent", NO)
                                       action:@selector(silentAimSwitchChanged:) inCard:_togglesCard];

    _camLabel = [self makeToggleLabel:@"Camera Xa (CamPC)" inCard:_togglesCard];
    _camSwitch = [self makeToggleSwitch:ESPPrefsBool(@"CamPC", NO)
                                 action:@selector(camSwitchChanged:) inCard:_togglesCard];

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

    // ===== ESP CARD =====
    _espCard = [self makeCard];
    [_contentView addSubview:_espCard];
    _espCardTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _espCardTitle.text = @"ESP ELEMENTS";
    _espCardTitle.font = VNFont(13, UIFontWeightBold);
    _espCardTitle.textColor = VNMuted();
    [_espCard addSubview:_espCardTitle];

    _espLabel = [self makeToggleLabel:@"Bật ESP" inCard:_espCard];
    _espSwitch = [self makeToggleSwitch:ESPPrefsBool(@"EnableESP", YES)
                                 action:@selector(espSwitchChanged:) inCard:_espCard];

    _espBoxLabel = [self makeToggleLabel:@"Box" inCard:_espCard];
    _espBoxSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Box", YES)
                                    action:@selector(espBoxChanged:) inCard:_espCard];

    _espLineLabel = [self makeToggleLabel:@"Snapline" inCard:_espCard];
    _espLineSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Line", YES)
                                     action:@selector(espLineChanged:) inCard:_espCard];

    _espBoneLabel = [self makeToggleLabel:@"Bone / Skeleton" inCard:_espCard];
    _espBoneSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Bone", YES)
                                     action:@selector(espBoneChanged:) inCard:_espCard];

    _espHealthLabel = [self makeToggleLabel:@"Health Bar" inCard:_espCard];
    _espHealthSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Health", YES)
                                       action:@selector(espHealthChanged:) inCard:_espCard];

    _espCountLabel = [self makeToggleLabel:@"Player Count" inCard:_espCard];
    _espCountSwitch = [self makeToggleSwitch:ESPPrefsBool(@"Count", YES)
                                      action:@selector(espCountChanged:) inCard:_espCard];

    _espDistanceLimitLabel = [self makeToggleLabel:@"Max Distance (m)" inCard:_espCard];
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

    // ===== AIM CARD =====
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
        idx = MAX(0, MIN(3, idx));
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
        idx = MAX(0, MIN(2, idx));
        _aimPosSegment.selectedSegmentIndex = idx;
    }
    if (@available(iOS 13.0, *)) {
        _aimPosSegment.selectedSegmentTintColor = VNAccent();
        _aimPosSegment.backgroundColor = VNPanel2();
    }
    [_aimPosSegment addTarget:self action:@selector(aimPosSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [_aimCard addSubview:_aimPosSegment];

    // ===== VERSION SECTION =====
    _versionSectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _versionSectionLabel.text = @"Lựa chọn phiên bản:";
    _versionSectionLabel.font = VNFont(14, UIFontWeightBold);
    _versionSectionLabel.textColor = VNMuted();
    [_contentView addSubview:_versionSectionLabel];

    UIImageView *ffMaxIcon = nil; UILabel *ffMaxName = nil;
    _ffMaxCard = [self makeVersionCardCapturingIcon:&ffMaxIcon nameLabel:&ffMaxName];
    _ffMaxIconView = ffMaxIcon; _ffMaxNameLabel = ffMaxName;
    _ffMaxIconView.image = [self imageNamedWebPOrPNG:@"ffmax"] ?: [UIImage imageNamed:@"logo"];
    _ffMaxNameLabel.text = @"Free Fire MAX";
    _ffMaxCard.tag = 2;
    [_ffMaxCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffMaxCard];

    UIImageView *ffIcon = nil; UILabel *ffName = nil;
    _ffCard = [self makeVersionCardCapturingIcon:&ffIcon nameLabel:&ffName];
    _ffIconView = ffIcon; _ffNameLabel = ffName;
    _ffIconView.image = [self imageNamedWebPOrPNG:@"ff"] ?: [UIImage imageNamed:@"logo"];
    _ffNameLabel.text = @"Free Fire";
    _ffCard.tag = 1;
    [_ffCard addTarget:self action:@selector(versionCardTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_ffCard];

    // ===== STATUS CARD =====
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

    // ===== LICENSE + AUTH =====
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

    // ===== SUPPORT =====
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

    // ===== EXTRA =====
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
    [_authorizationButton addTarget:self action:@selector(revokeAuthorization)
                   forControlEvents:UIControlEventTouchUpInside];
    [_extraCard addSubview:_authorizationButton];

    [self applyTheme];
}

- (UILabel *)makeToggleLabel:(NSString *)text inCard:(UIView *)card {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = VNFont(17, UIFontWeightSemibold);
    l.textColor = VNText();
    [card addSubview:l];
    return l;
}
- (UISwitch *)makeToggleSwitch:(BOOL)on action:(SEL)sel inCard:(UIView *)card {
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectZero];
    s.onTintColor = VNAccent();
    s.on = on;
    [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    [card addSubview:s];
    return s;
}

#pragma mark - Gate overlay

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
            [ws presentSafely:vc];
        });
        return;
    }
    UIViewController *top = self;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed)
        top = top.presentedViewController;
    if (top.presentedViewController && top.presentedViewController.isBeingDismissed) {
        __weak __typeof(self) ws = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ws presentSafely:vc];
        });
        return;
    }
    if ([top isKindOfClass:[UIAlertController class]]) {
        __weak __typeof(self) ws = self;
        [top dismissViewControllerAnimated:NO completion:^{ [ws presentSafely:vc]; }];
        return;
    }
    [top presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Gate flow

- (void)runGate {
    [self showGateMessage:[self isVi] ? OXR("Đang kiểm tra…") : OXR("Checking…")];
    __weak __typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong __typeof(ws) ss = ws; if (!ss) return;
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
    } else [self tryAutoLogin];
}
- (void)tryAutoLogin {
    NSString *saved = [LicenseGate loadKey];
    if (saved.length > 0) {
        [self showGateMessage:[self isVi] ? OXR("Đang xác thực key…") : OXR("Verifying key…")];
        __weak __typeof(self) ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSInteger r = [LicenseGate verify:saved];
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong __typeof(ws) ss = ws; if (!ss) return;
                if (r == 0) [ss unlock:saved];
                else { [LicenseGate forgetKey]; [ss promptKey]; }
            });
        });
    } else [self promptKey];
}
- (void)promptKey {
    BOOL vi = [self isVi];
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:OXR("VN TOOL")
        message:vi ? OXR("Nhập license key để kích hoạt") : OXR("Enter license key to activate")
        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = OXR("XXXX-XXXX-XXXX");
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:(vi?OXR("Kích hoạt"):OXR("Activate"))
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            NSString *k = [ac.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (k.length == 0) { [self promptKey]; return; }
            [self showGateMessage:vi ? OXR("Đang xác thực…") : OXR("Verifying…")];
            __weak __typeof(self) ws = self;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSInteger r = [LicenseGate verify:k];
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong __typeof(ws) ss = ws; if (!ss) return;
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
        dispatch_async(dispatch_get_main_queue(), ^{
            self.licenseValueLabel.text = [NSString stringWithFormat:@"%@\n%@", timeStr, expStr];
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:(vi?OXR("🔑 Key của bạn"):OXR("🔑 Your License"))
                message:(vi ? [NSString stringWithFormat:OXR("Còn lại: %@\nHết hạn: %@"), timeStr, expStr]
                            : [NSString stringWithFormat:OXR("Remaining: %@\nExpires: %@"), timeStr, expStr])
                preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:OXR("OK") style:UIAlertActionStyleDefault handler:nil]];
            [self presentSafely:ac];
        });
    });
}

- (void)unlock:(NSString *)verifiedKey {
    _unlocked = YES;
    self.vaultedKey = VaultPut(verifiedKey);

    self.scrollView.hidden = NO;
    self.settingsBtn.hidden = NO;
    self.authorizationLabel.text = @"No key required";
    [self.authorizationButton setTitle:@"Unlocked" forState:UIControlStateNormal];
    self.authorizationButton.enabled = NO;
    self.authValueLabel.text = @"Hoạt động";
    self.authValueLabel.textColor = VNAccent();

    [UIView animateWithDuration:0.25 animations:^{ self->_gateOverlay.alpha = 0; }
        completion:^(BOOL fin){
            [self->_gateOverlay removeFromSuperview];
            self->_gateOverlay = nil;
        }];

    [self updateVersionSelectionUI];
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

#pragma mark - Version selection

- (void)versionCardTapped:(UIButton *)sender {
    BOOL pickMax = (sender.tag == 2);
    GameTargetSetSelectedId(pickMax ? @"ffmax" : @"ff");
    [self updateVersionSelectionUI];
    [self refreshHUDState];
}
- (void)updateVersionSelectionUI {
    BOOL isMax = GameTargetIsMax();
    UIColor *sel = VNAccent();
    _ffMaxCard.layer.borderWidth = 2.5f;
    _ffCard.layer.borderWidth = 2.5f;
    _ffMaxCard.layer.borderColor = (isMax ? sel : [UIColor clearColor]).CGColor;
    _ffCard.layer.borderColor = (!isMax ? sel : [UIColor clearColor]).CGColor;
    _ffMaxCard.backgroundColor = isMax ? VNPanel2() : VNCard();
    _ffCard.backgroundColor = !isMax ? VNPanel2() : VNCard();
    UIImage *icon = [self imageNamedWebPOrPNG:isMax ? @"ffmax" : @"ff"];
    if (icon) _controlIconView.image = icon;
}

#pragma mark - App lifecycle

- (void)appBecameActive {
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

- (BOOL)isGameRunning { return GameTargetIsRunning(); }

- (void)startPollingGameState {
    __weak __typeof(self) ws = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        __typeof(self) ss = ws; if (!ss || !ss.unlocked) return;
        [ss refreshHUDState];
    }];
}

- (void)autoCleanSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBool(@"AutoVarCleanBeforeHUD", sender.on);
}
- (void)aimbotSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"Aimbot", sender.on);
    ESPSyncFromPrefs();
}
- (void)silentAimSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimSilent", sender.on);
    ESPSyncFromPrefs();
    [[VNLog shared] append:[NSString stringWithFormat:
        @"[VN] Silent Aim %@ (FOV %.0f, Pos %d)",
        sender.on ? @"ON" : @"OFF",
        ESPPrefsFloat(@"Fov", 150.0f),
        (int)ESPPrefsFloat(@"AimPos", 0.0f)]];
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
    _camValueLabel.text = [NSString stringWithFormat:@"%.0f", sender.value];
    ESPPrefsSetFloatLive(@"CamPCValue", sender.value);
}
- (void)fovSliderChanged:(UISlider *)sender {
    _fovValueLabel.text = [NSString stringWithFormat:@"%.0f", sender.value];
    ESPPrefsSetFloatLive(@"Fov", sender.value);
}
- (void)espBoxChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Box", sender.on); ESPSyncFromPrefs(); }
- (void)espLineChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Line", sender.on); ESPSyncFromPrefs(); }
- (void)espBoneChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Bone", sender.on); ESPSyncFromPrefs(); }
- (void)espHealthChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Health", sender.on); ESPSyncFromPrefs(); }
- (void)espCountChanged:(UISwitch *)sender { ESPPrefsSetBoolLive(@"Count", sender.on); ESPSyncFromPrefs(); }
- (void)espDistanceLimitChanged:(UISlider *)sender {
    _espDistanceLimitValueLabel.text = [NSString stringWithFormat:@"%.0f", sender.value];
    ESPPrefsSetFloatLive(@"EspDistanceLimit", sender.value);
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
}
- (void)aimPosSegmentChanged:(UISegmentedControl *)sender {
    float v = (float)sender.selectedSegmentIndex;
    NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
    [std setFloat:v forKey:@"AimPos"];
    [std setFloat:v forKey:@"AimPos_Lite"];
    [std synchronize];
    ESPPrefsSetFloat(@"AimPos", v);
    ESPSyncFromPrefs();
}
- (void)aimBehindWallSwitchChanged:(UISwitch *)sender {
    ESPPrefsSetBoolLive(@"AimBehindWall", sender.on);
    ESPSyncFromPrefs();
}

#pragma mark - Start / Kill All

- (void)startButtonTapped:(UIButton *)sender {
    if (!_unlocked) return;
    BOOL hudOn = IsHUDEnabled();
    if (hudOn) {
        ++_hudRequestSerial;
        _pendingHUDEnableUntil = 0;
        SetHUDEnabled(NO);
        [self refreshHUDState];
        return;
    }
    NSInteger serial = ++_hudRequestSerial;
    _startButton.enabled = NO;
    [self startHUDForRequest:serial];
}

- (void)startHUDForRequest:(NSInteger)serial {
    _pendingHUDEnableUntil = CACurrentMediaTime() + 2.5;
    GameOffsetsReload();
    BOOL autoClean = ESPPrefsBool(@"AutoVarCleanBeforeHUD", NO);
    if (!autoClean) {
        kernelBootLog = HomeVCBootLogSink;
        kernelBootStart();
        self.startButton.enabled = YES;
        [self refreshHUDState];
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[varCleanController sharedInstance] runVarCleanNowWithCompletion:^(BOOL authorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (serial != self.hudRequestSerial || !authorized) {
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
        [[VNLog shared] append:@"[VN] Tắt toàn bộ HUD + ESP + Aimbot"];
        [self refreshHUDState];
    });
}

#pragma mark - Open game / support

- (void)openGameTapped:(id)sender {
    NSString *bundleId = GameTargetIsMax() ? @"com.dts.freefiremax" : @"vn.vng.freefireth";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app canOpenURL:url]) { [app openURL:url options:@{} completionHandler:nil]; return; }
    NSArray<NSString *> *fallbacks = GameTargetIsMax()
        ? @[ @"freefiremax://", @"ffmax://" ]
        : @[ @"freefireth://", @"freefire://" ];
    for (NSString *scheme in fallbacks) {
        NSURL *u = [NSURL URLWithString:scheme];
        if ([app canOpenURL:u]) { [app openURL:u options:@{} completionHandler:nil]; return; }
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Không mở được game"
                                            message:@"Hãy mở Free Fire / Free Fire MAX thủ công, rồi quay lại nhấn Bắt đầu."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)joinSupportTapped:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://t.me/vntool"];
    if (!url) return;
    SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:url];
    [self presentViewController:svc animated:YES completion:nil];
}

- (void)revokeAuthorization {
    SetHUDEnabled(NO);
    [LicenseGate forgetKey];
    [[VNLog shared] append:@"[VN] Đã xoá license key"];
}

#pragma mark - HUD state

- (void)refreshHUDState {
    if (!_unlocked || !self.isViewLoaded) return;
    GameOffsetsReload();

    BOOL gameIsRunning = [self isGameRunning];
    BOOL hudIsEnabled = IsHUDEnabled();
    _gameMissingStreak = gameIsRunning ? 0 : _gameMissingStreak + 1;
    BOOL gameIsAvailable = gameIsRunning || _gameMissingStreak < 8;

    if (gameIsRunning) {
        _statusDot.backgroundColor = VNAccent();
        NSString *name = GameTargetIsMax() ? @"Free Fire MAX" : @"Free Fire";
        _statusLabel.text = [NSString stringWithFormat:@"Trạng thái · %@ đang chạy", name];
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
    BOOL inGrace = (_pendingHUDEnableUntil > 0 && now < _pendingHUDEnableUntil);
    if (!hudIsEnabled && inGrace) {
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

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    _scrollView.frame = self.view.bounds;

    CGFloat gear = 44.0f;
    _settingsBtn.frame = CGRectMake(width - insets.right - 16 - gear, insets.top + 8, gear, gear);

    CGFloat contentW = width, xPad = 16.0f;
    CGFloat cardW = contentW - xPad * 2.0f;
    CGFloat y = insets.top + 62.0f;

    // Control
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

    // Toggles
    CGFloat toggleRowH = 62.0f;
    CGFloat sliderAreaH = 82.0f;
    CGFloat togglesH = toggleRowH * 4 + sliderAreaH;
    _togglesCard.frame = CGRectMake(xPad, y, cardW, togglesH);

    CGFloat rowY = 0;
    void (^placeRow)(UILabel *, UISwitch *) = ^(UILabel *l, UISwitch *s) {
        l.frame = CGRectMake(20, rowY, cardW - 110, toggleRowH);
        s.frame = CGRectMake(cardW - 71, rowY + (toggleRowH - 31) * 0.5f, 51, 31);
        rowY += toggleRowH;
    };
    placeRow(_aimbotLabel, _aimbotSwitch);
    placeRow(_aimBehindWallLabel, _aimBehindWallSwitch);
    placeRow(_silentAimLabel, _silentAimSwitch);
    placeRow(_camLabel, _camSwitch);

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

    NSArray<UILabel *> *espLabels = @[_espBoxLabel, _espLineLabel, _espBoneLabel, _espHealthLabel, _espCountLabel];
    NSArray<UISwitch *> *espSwitches = @[_espBoxSwitch, _espLineSwitch, _espBoneSwitch, _espHealthSwitch, _espCountSwitch];
    CGFloat espY = espTitleH + espRowH;
    for (NSUInteger i = 0; i < 5; i++) {
        espLabels[i].frame = CGRectMake(20, espY, cardW - 110, espRowH);
        espSwitches[i].frame = CGRectMake(cardW - 71, espY + (espRowH - 31) * 0.5f, 51, 31);
        espY += espRowH;
    }
    _espDistanceLimitLabel.frame = CGRectMake(20, espY, cardW - 110, 30);
    _espDistanceLimitValueLabel.frame = CGRectMake(cardW - 64, espY, 48, 30);
    _espDistanceLimitSlider.frame = CGRectMake(20, espY + 34, cardW - 40, 30);
    y = CGRectGetMaxY(_espCard.frame) + 16;

    // Aim
    CGFloat fovAreaH = 90.0f, segAreaH = 100.0f;
    CGFloat aimH = fovAreaH + segAreaH * 2;
    _aimCard.frame = CGRectMake(xPad, y, cardW, aimH);
    _fovLabel.frame = CGRectMake(20, 18, 140, 24);
    _fovValueLabel.frame = CGRectMake(cardW - 64, 18, 48, 24);
    _fovSlider.frame = CGRectMake(20, 50, cardW - 40, 30);
    _triggerLabel.frame = CGRectMake(20, fovAreaH + 14, 140, 24);
    _triggerSegment.frame = CGRectMake(20, fovAreaH + 46, cardW - 40, 38);
    _aimPosLabel.frame = CGRectMake(20, fovAreaH + segAreaH + 14, 220, 24);
    _aimPosSegment.frame = CGRectMake(20, fovAreaH + segAreaH + 46, cardW - 40, 38);
    y = CGRectGetMaxY(_aimCard.frame) + 16;

    // Version
    y += 6;
    _versionSectionLabel.frame = CGRectMake(xPad + 4, y, cardW - 8, 22);
    y = CGRectGetMaxY(_versionSectionLabel.frame) + 10;
    CGFloat gap = 12.0f;
    CGFloat versionW = (cardW - gap) * 0.5f;
    CGFloat versionH = 136.0f;
    _ffMaxCard.frame = CGRectMake(xPad, y, versionW, versionH);
    _ffCard.frame = CGRectMake(xPad + versionW + gap, y, versionW, versionH);
    CGFloat iconSide = 68.0f;
    _ffMaxIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 20, iconSide, iconSide);
    _ffIconView.frame = CGRectMake((versionW - iconSide) * 0.5f, 20, iconSide, iconSide);
    _ffMaxNameLabel.frame = CGRectMake(8, 96, versionW - 16, 24);
    _ffNameLabel.frame = CGRectMake(8, 96, versionW - 16, 24);
    y = CGRectGetMaxY(_ffMaxCard.frame) + 16;

    // Status
    CGFloat statusH = 72.0f;
    _statusCard.frame = CGRectMake(xPad, y, cardW, statusH);
    _statusDot.frame = CGRectMake(20, (statusH - 12) * 0.5f, 12, 12);
    _openGameButton.frame = CGRectMake(cardW - 116, (statusH - 38) * 0.5f, 100, 38);
    _statusLabel.frame = CGRectMake(42, 0, cardW - 116 - 50, statusH);
    y = CGRectGetMaxY(_statusCard.frame) + 16;

    // License + Auth
    CGFloat infoH = 60.0f;
    _licenseCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _licenseTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _licenseValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_licenseCard.frame) + 1;
    _authCard.frame = CGRectMake(xPad, y, cardW, infoH);
    _authTitleLabel.frame = CGRectMake(20, 0, cardW/2, infoH);
    _authValueLabel.frame = CGRectMake(cardW/2, 0, cardW/2 - 20, infoH);
    y = CGRectGetMaxY(_authCard.frame) + 16;

    // Support
    CGFloat supportH = 80.0f;
    _supportCard.frame = CGRectMake(xPad, y, cardW, supportH);
    _joinButton.frame = CGRectMake(cardW - 96, (supportH - 38) * 0.5f, 80, 38);
    _supportTitleLabel.frame = CGRectMake(20, 20, cardW - 130, 26);
    _supportSubtitleLabel.frame = CGRectMake(20, 48, cardW - 130, 20);
    y = CGRectGetMaxY(_supportCard.frame) + 16;

    // Extra
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
    CGFloat cy = height / 2;
    _gateSpinner.center = CGPointMake(width / 2, cy - 20);
    _gateLabel.frame = CGRectMake(24, cy + 12, width - 48, 60);
}

@end
