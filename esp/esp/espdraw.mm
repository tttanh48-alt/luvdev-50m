#import "esp.h"
#import "GameLogic.h"
#import "mahoa.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <cmath>

extern NSMutableDictionary *gWeaponTextures;

#ifdef __cplusplus
extern "C" {
#endif

static inline float Clamp01f(float v) {
    if (v < 0.0f) return 0.0f;
    if (v > 1.0f) return 1.0f;
    return v;
}

static UIFont *cachedFonts[40] = {nil};

UIFont *GetCustomFont(CGFloat size) {
    int intSize = (int)roundf(size);
    if (intSize >= 4 && intSize < 40) {
        if (!cachedFonts[intSize]) {
            cachedFonts[intSize] = [UIFont fontWithName:NSSENCRYPT("arialbd") size:(CGFloat)intSize] ?: [UIFont boldSystemFontOfSize:(CGFloat)intSize];
        }
        return cachedFonts[intSize];
    }
    return [UIFont fontWithName:NSSENCRYPT("arialbd") size:size] ?: [UIFont boldSystemFontOfSize:size];
}

static inline void ESPAddLine(CGMutablePathRef path, CGPoint p1, CGPoint p2) {
    if (!path) return;
    CGPathMoveToPoint(path, NULL, p1.x, p1.y);
    CGPathAddLineToPoint(path, NULL, p2.x, p2.y);
}

static inline void ESPAddCircle(CGMutablePathRef path, CGPoint center, CGFloat radius) {
    if (!path) return;
    CGRect rect = CGRectMake(center.x - radius, center.y - radius, radius * 2.0f, radius * 2.0f);
    CGPathAddEllipseInRect(path, NULL, rect);
}

BOOL RenderFOVCirclePath(
    CGMutablePathRef path,
    float viewWidth,
    float viewHeight,
    BOOL aimbotEnabled,
    float fovRadius
) {
    if (!path || !aimbotEnabled || fovRadius <= 0) return NO;
    const int kSegs = 72;
    const float cx = viewWidth / 2.0f;
    const float cy = viewHeight / 2.0f;
    const float kTwoPi = 6.28318530718f;
    for (int i = 0; i <= kSegs; i++) {
        const float a = (float)i * kTwoPi / (float)kSegs;
        const float px = cx + cosf(a) * fovRadius;
        const float py = cy + sinf(a) * fovRadius;
        if (i == 0) CGPathMoveToPoint(path, NULL, px, py);
        else        CGPathAddLineToPoint(path, NULL, px, py);
    }
    CGPathCloseSubpath(path);
    return YES;
}

void RenderTotalEnemyCount(ESPAddTextCallback textCallback, void *callbackContext, int totalCount, float layerWidth) {
    if (!textCallback || totalCount < 0) return;
    NSString *countStr = [NSString stringWithFormat:@"%d", totalCount];
    textCallback(callbackContext, countStr, CGRectMake((layerWidth / 2.0f) - 50.0f, 45.0f, 100.0f, 35.0f), [UIColor redColor], 26.0f, NO);
}

uint32_t CurrentWeaponID(uint64_t PawnObject) {
    if (!isVaildPtr(PawnObject)) return UINT32_MAX;
    uint32_t weaponID = ReadAddr<uint32_t>(PawnObject + 0x13C);
    if (weaponID == 0) return 1;
    return weaponID;
}

NSString* WeaponNameForPlayerNS(uint64_t PawnObject) {
    uint32_t wid = CurrentWeaponID(PawnObject);
    if (wid == UINT32_MAX) return @"";
    switch(wid) {
        case 0:
        case 1:   return @"Tay không";
        case 2:   return @"M4A1";
        case 4:   return @"AWM";
        case 5:   return @"M1014";
        case 6:   return @"AK47";
        case 7:   return @"UMP";
        case 8:   return @"MP5";
        case 9:   return @"Desert Eagle";
        case 15:  return @"MP40";
        case 16:  return @"Chảo";
        case 21:  return @"Kar98k";
        case 28:  return @"XM8";
        case 30:  return @"M60";
        case 41:  return @"M1887";
        case 45:  return @"M82B";
        case 48:  return @"Woodpecker";
        case 50:  return @"MAG-7";
        case 1204:return @"Bom Keo";
        default:  return [NSString stringWithFormat:@"Súng %d", wid];
    }
}

// ============================================================
// CORE RENDER
// ============================================================
static void ESPRenderPawnCore(
    ESPGeometryBuffers *buffers,
    ESPAddTextCallback textCallback,
    ESPAddImageCallback imageCallback,
    void *callbackContext,
    uint64_t PawnObject,
    int CurHP,
    float dis,
    float *matrix,
    float layerWidth,
    float layerHeight,
    float matrixVpWidth,
    float matrixVpHeight,
    float headX, float headY, float headZ,
    float hipX, float hipY, float hipZ,
    int isBotFlag,
    int isKnockedFlag
) {
    if (dis > 400.0f || !buffers || !matrix || !PawnObject || dis < 1.0f) return;
    if (headX == 0.0f && headY == 0.0f && headZ == 0.0f) return;

    int MaxHP = get_MaxHP(PawnObject);
    if (MaxHP <= 0 || MaxHP > 2000) MaxHP = 200;

    const bool isKnocked = (isKnockedFlag != 0);
    const bool isBot = (isBotFlag != 0);
    NSString *Name = GetNickName(PawnObject);
    if (!Name || Name.length == 0) Name = isBot ? @"BOT" : @"Player";

    Vector3 HeadPos; HeadPos.x = headX; HeadPos.y = headY; HeadPos.z = headZ;
    Vector3 HipPos;  HipPos.x = hipX;  HipPos.y = hipY;  HipPos.z = hipZ;
    Vector3 RightToePos = getPositionExt(getRightToeNode(PawnObject));
    Vector3 LeftToePos  = getPositionExt(getLeftAnkle(PawnObject));

    if (fabsf(RightToePos.x) < 0.1f && fabsf(RightToePos.y) < 0.1f && fabsf(RightToePos.z) < 0.1f) {
        RightToePos = HeadPos;
        RightToePos.y -= 1.65f;
    }
    if (fabsf(LeftToePos.x) < 0.1f && fabsf(LeftToePos.y) < 0.1f && fabsf(LeftToePos.z) < 0.1f) {
        LeftToePos = RightToePos;
    }

    float worldHeight = fabsf(HeadPos.y - RightToePos.y);

    Vector3 L_Ankle      = getPositionExt(getLeftAnkle(PawnObject));
    Vector3 R_Ankle      = getPositionExt(getRightAnkle(PawnObject));
    Vector3 L_ForeArm    = getPositionExt(getLeftElbow(PawnObject));
    Vector3 R_ForeArm    = getPositionExt(getRightElbow(PawnObject));
    Vector3 L_Hand       = getPositionExt(getLeftHand(PawnObject));
    Vector3 R_Hand       = getPositionExt(getRightHand(PawnObject));

    Vector3 HeadTop = HeadPos; HeadTop.y += 0.2f;
    Vector3 w2sHead    = WorldToScreenLayer(HeadTop, matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
    Vector3 w2sToe     = WorldToScreenLayer(RightToePos, matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
    Vector3 w2sLeftToe = WorldToScreenLayer(LeftToePos, matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
    Vector3 w2sHip     = WorldToScreenLayer(HipPos, matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);

    if (w2sHead.z < 0.001f) return;
    const float margin = layerWidth * 0.6f;
    if (w2sHead.x < -margin || w2sHead.x > layerWidth + margin || w2sHead.y < -margin || w2sHead.y > layerHeight + margin) return;

    // Box
    float top = w2sHead.y;
    float bottom = fmaxf(w2sToe.y, w2sLeftToe.y);
    if (top > bottom) { float temp = top; top = bottom; bottom = temp; }

    float screenRealHeight = bottom - top;

    Vector3 fakeBasePos = HeadPos;
    fakeBasePos.y -= 1.65f;
    Vector3 w2sFakeBase = WorldToScreenLayer(fakeBasePos, matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
    float stdHeight = fabsf(w2sHead.y - w2sFakeBase.y);

    float boxHeight, boxWidth, x, y;

    if (isKnocked || CurHP <= 0 || worldHeight < 0.7f) {
        boxHeight = stdHeight * 0.35f;
        boxWidth  = stdHeight * 0.45f;
        x = w2sHip.x - boxWidth * 0.5f;
        y = w2sHip.y - boxHeight * 0.5f;
    } else if (worldHeight < 1.35f) {
        boxHeight = screenRealHeight;
        boxWidth  = stdHeight * 0.45f;
        x = w2sHead.x - boxWidth * 0.5f;
        y = top;
    } else {
        boxHeight = screenRealHeight;
        boxWidth  = boxHeight * 0.45f;
        x = w2sHead.x - boxWidth * 0.5f;
        y = top;
    }

    if (boxHeight < 6.0f) boxHeight = 6.0f;
    if (boxWidth < 4.0f) boxWidth = 4.0f;

    CGFloat dynFontSize = fmaxf(4.5f, fminf(10.0f, 350.0f / fmaxf(dis, 1.0f)));
    float centerX = x + boxWidth * 0.5f;

    // ---------------------------------------------------------
    // BONE
    // ---------------------------------------------------------
    if (isBone) {
        Vector3 wHead   = WorldToScreenLayer(HeadPos,   matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wLE     = WorldToScreenLayer(L_ForeArm,  matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wRE     = WorldToScreenLayer(R_ForeArm,  matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wLH     = WorldToScreenLayer(L_Hand,      matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wRH     = WorldToScreenLayer(R_Hand,      matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wLA     = WorldToScreenLayer(L_Ankle,     matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wRA     = WorldToScreenLayer(R_Ankle,     matrix, matrixVpWidth, matrixVpHeight, layerWidth, layerHeight);
        Vector3 wLT     = w2sLeftToe;
        Vector3 wRT     = w2sToe;

        CGPoint pHead = CGPointMake(wHead.x, wHead.y);
        CGPoint pHip  = CGPointMake(w2sHip.x,  w2sHip.y);
        CGPoint pNeck = CGPointMake(pHead.x + (pHip.x - pHead.x) * 0.15f, pHead.y + (pHip.y - pHead.y) * 0.15f);
        CGPoint pLE = CGPointMake(wLE.x, wLE.y);
        CGPoint pRE = CGPointMake(wRE.x, wRE.y);
        CGPoint pLS = CGPointMake(pNeck.x + (pLE.x - pNeck.x) * 0.3f, pNeck.y + (pLE.y - pNeck.y) * 0.3f);
        CGPoint pRS = CGPointMake(pNeck.x + (pRE.x - pNeck.x) * 0.3f, pNeck.y + (pRE.y - pNeck.y) * 0.3f);
        CGPoint pLH = CGPointMake(wLH.x, wLH.y);
        CGPoint pRH = CGPointMake(wRH.x, wRH.y);
        CGPoint pLK = CGPointMake(pHip.x + (wLA.x - pHip.x) * 0.45f, pHip.y + (wLA.y - pHip.y) * 0.45f);
        CGPoint pRK = CGPointMake(pHip.x + (wRA.x - pHip.x) * 0.45f, pHip.y + (wRA.y - pHip.y) * 0.45f);
        CGPoint pLA = CGPointMake(wLA.x, wLA.y);
        CGPoint pRA = CGPointMake(wRA.x, wRA.y);
        CGPoint pLT = CGPointMake(wLT.x, wLT.y);
        CGPoint pRT = CGPointMake(wRT.x, wRT.y);

        CGFloat headToHip = fabs(pHead.y - pHip.y);
        CGFloat headRadius = fmaxf(headToHip / 4.5f, 1.0f);
        ESPAddCircle(buffers->bonePath, CGPointMake(pHead.x, pHead.y - headRadius * 0.5f), headRadius);
        ESPAddLine(buffers->bonePath, pNeck, pHip);
        ESPAddLine(buffers->bonePath, pNeck, pLS); ESPAddLine(buffers->bonePath, pLS, pLE); ESPAddLine(buffers->bonePath, pLE, pLH);
        ESPAddLine(buffers->bonePath, pNeck, pRS); ESPAddLine(buffers->bonePath, pRS, pRE); ESPAddLine(buffers->bonePath, pRE, pRH);
        ESPAddLine(buffers->bonePath, pHip, pLK); ESPAddLine(buffers->bonePath, pLK, pLA); ESPAddLine(buffers->bonePath, pLA, pLT);
        ESPAddLine(buffers->bonePath, pHip, pRK); ESPAddLine(buffers->bonePath, pRK, pRA); ESPAddLine(buffers->bonePath, pRA, pRT);
        buffers->boneDirty = true;
    }

    // ---------------------------------------------------------
    // WEAPON
    // ---------------------------------------------------------
    if (isWeapon) {
        float wCX = centerX + 8.5f;
        float wTY = y - 20.0f;
        uint32_t wid = CurrentWeaponID(PawnObject);

        UIImage *wimg = (wid != UINT32_MAX && gWeaponTextures) ? gWeaponTextures[@(wid)] : nil;
        const float wIconH = 14.0f;

        if (wimg && imageCallback) {
            float wScl = wIconH / wimg.size.height;
            float wIconW = wimg.size.width * wScl;
            imageCallback(callbackContext, wimg, CGRectMake(wCX - wIconW/2, wTY - wIconH - 2, wIconW, wIconH));
        } else if (textCallback) {
            NSString *wname = WeaponNameForPlayerNS(PawnObject);
            if (wname && wname.length > 0) {
                textCallback(callbackContext, wname, CGRectMake(wCX - 50.0f, wTY - wIconH - 2, 100.0f, wIconH), [UIColor yellowColor], 6.5f, NO);
            }
        }
    }

    // ---------------------------------------------------------
    // LINE
    // ---------------------------------------------------------
    if (isLine) {
        CGPoint lineStart = CGPointMake(layerWidth / 2.0f, 35.0f);
        CGPoint boxTopCenter = CGPointMake(centerX, y);

        if (isKnocked) { ESPAddLine(buffers->snaplineKnockedPath, lineStart, boxTopCenter); buffers->snaplineKnockedDirty = true; }
        else if (isBot) { ESPAddLine(buffers->snaplineBotPath, lineStart, boxTopCenter); buffers->snaplineBotDirty = true; }
        else { ESPAddLine(buffers->snaplinePath, lineStart, boxTopCenter); buffers->snaplineDirty = true; }
    }

    // ---------------------------------------------------------
    // BOX
    // ---------------------------------------------------------
    if (isBox) {
        CGRect boxRect = CGRectMake(x, y, boxWidth, boxHeight);
        if (isKnocked) { CGPathAddRect(buffers->boxKnockedPath, NULL, boxRect); buffers->boxKnockedDirty = true; }
        else if (isBot) { CGPathAddRect(buffers->boxBotPath, NULL, boxRect); buffers->boxBotDirty = true; }
        else { CGPathAddRect(buffers->boxPath, NULL, boxRect); buffers->boxDirty = true; }
    }

    // ---------------------------------------------------------
    // HEALTH BAR — HORIZONTAL, ABOVE THE BOX
    //
    // Was a vertical 2pt bar to the LEFT of the box (barX = x - 2 - 1,
    // full box height). The user asked for it horizontal above the head.
    // The fill is anchored to the left edge and grows to the right, the
    // same direction the box is read.
    //
    // Position: hpBarY = y - hpBarH - 2 puts it 2pt above the box top,
    // where the name text would sit. The name has been pushed further up
    // (see NAME block below) so they do not overlap.
    // ---------------------------------------------------------
    if (isHealth) {
        float healthRatio = Clamp01f((float)CurHP / (float)fmaxf(MaxHP, 1.0f));
        const CGFloat hpBarH = 3.0f;
        const CGFloat hpBarW = boxWidth;
        const CGFloat hpBarX = x;
        const CGFloat hpBarY = y - hpBarH - 2.0f;
        const CGFloat hpFillW = hpBarW * healthRatio;

        // Black background across the full width.
        CGPathAddRect(buffers->bgFillBlackPath, NULL,
                      CGRectMake(hpBarX, hpBarY, hpBarW, hpBarH));
        buffers->bgFillBlackDirty = true;

        // Coloured fill from the left edge.
        CGRect fillRect = CGRectMake(hpBarX, hpBarY, hpFillW, hpBarH);
        if (CurHP >= 150) {
            CGPathAddRect(buffers->hpFillGreenPath, NULL, fillRect);
            buffers->hpFillGreenDirty = true;
        } else if (CurHP >= 75) {
            CGPathAddRect(buffers->hpFillOrangePath, NULL, fillRect);
            buffers->hpFillOrangeDirty = true;
        } else if (CurHP > 0) {
            CGPathAddRect(buffers->hpFillRedPath, NULL, fillRect);
            buffers->hpFillRedDirty = true;
        }
    }

    // ---------------------------------------------------------
    // NAME — pushed above the HP bar
    // Was: y - dynFontSize - 6. Now shifted up by HP bar height (3) +
    // the 2pt gap + a small pad so the two never touch.
    // ---------------------------------------------------------
    if (isName && textCallback) {
        NSString *dispName = (isEspBot && isBot) ? NSSENCRYPT("BOT") : Name;
        if (dispName.length > 0) {
            CGFloat nameY = y - dynFontSize - 6.0f;
            if (isHealth) nameY -= 5.0f; // clear the HP bar
            textCallback(callbackContext, dispName,
                         CGRectMake(centerX - 100.0f, nameY, 200.0f, dynFontSize + 4.0f),
                         [UIColor yellowColor], dynFontSize, NO);
        }
    }

    // ---------------------------------------------------------
    // DISTANCE
    // ---------------------------------------------------------
    if (isDis && textCallback) {
        NSString *distString = [NSString stringWithFormat:NSSENCRYPT("[%dM]"), (int)dis];
        textCallback(callbackContext, distString,
                     CGRectMake(centerX - 100.0f, y + boxHeight + 2.0f, 200.0f, dynFontSize + 4.0f),
                     [UIColor whiteColor], dynFontSize, NO);
    }
}

// ==========================================
// FAST PATH
// ==========================================
void RenderESPForPawnEx(
    ESPGeometryBuffers *buffers,
    ESPAddTextCallback textCallback,
    ESPAddImageCallback imageCallback,
    void *callbackContext,
    uint64_t PawnObject,
    int CurHP,
    float dis,
    float *matrix,
    float layerWidth,
    float layerHeight,
    float matrixVpWidth,
    float matrixVpHeight,
    float headX, float headY, float headZ,
    float hipX, float hipY, float hipZ,
    int isBotFlag,
    int isKnockedFlag
) {
    ESPRenderPawnCore(buffers, textCallback, imageCallback, callbackContext,
                      PawnObject, CurHP, dis, matrix,
                      layerWidth, layerHeight, matrixVpWidth, matrixVpHeight,
                      headX, headY, headZ,
                      hipX, hipY, hipZ,
                      isBotFlag, isKnockedFlag);
}

#ifdef __cplusplus
}
#endif
