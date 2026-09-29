#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#include <algorithm>
#include <vector>
static void *QBannerGlassMeshKey = &QBannerGlassMeshKey;

// CAMutableMeshTransform uses these C layouts on arm64, as in Burger Swift's
// iOS 17 glass surface. The mesh displaces backdrop sampling toward the
// middle of the rounded edge while leaving the card content untouched.
typedef struct { CGFloat x, y, z; } QGlassPoint3D;
typedef struct { CGPoint from; QGlassPoint3D to; } QGlassVertex;
typedef struct { uint32_t indices[4]; float weights[4]; } QGlassFace;

static NSArray<NSNumber *> *QGlassGrid(CGFloat length) {
    NSMutableSet<NSNumber *> *values = [NSMutableSet setWithObjects:@0, @(length), nil];
    const CGFloat edge[] = {2, 5, 8, 12, 18, 25, 34};
    for (NSUInteger i = 0; i < sizeof(edge) / sizeof(edge[0]); i++) {
        if (edge[i] < length / 2) {
            [values addObject:@(edge[i])];
            [values addObject:@(length - edge[i])];
        }
    }
    for (CGFloat point = 48; point < length - 40; point += 32)
        [values addObject:@(point)];
    return [[values allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

static CGFloat QGlassSDF(CGFloat x, CGFloat y, CGSize size, CGFloat radius) {
    CGFloat qx = fabs(x - size.width / 2) - size.width / 2 + radius;
    CGFloat qy = fabs(y - size.height / 2) - size.height / 2 + radius;
    return hypot(MAX(qx, 0), MAX(qy, 0)) + MIN(MAX(qx, qy), 0) - radius;
}

static CGFloat QGlassBezier(CGFloat value) {
    const CGFloat x1 = 0.816137566137566, y1 = 0.20502645502645533;
    const CGFloat x2 = 0.5806878306878306, y2 = 0.873015873015873;
    CGFloat t = MAX(0, MIN(1, value));
    for (int i = 0; i < 4; i++) {
        CGFloat inverse = 1 - t;
        CGFloat x = 3 * inverse * inverse * t * x1 + 3 * inverse * t * t * x2 + t * t * t;
        CGFloat slope = 3 * inverse * inverse * x1 + 6 * inverse * t * (x2 - x1) + 3 * t * t * (1 - x2);
        if (fabs(slope) < 0.0001) break;
        t = MAX(0, MIN(1, t - (x - value) / slope));
    }
    CGFloat inverse = 1 - t;
    CGFloat result = 3 * inverse * inverse * t * y1 + 3 * inverse * t * t * y2 + t * t * t;
    return result >= 0.997 ? 1 : result;
}

extern "C" void QUpdateGlassRefraction(CALayer *backdrop, CGSize size, CGFloat radius,
                                        CGFloat magnitude, UIVisualEffectView *glass) {
    Class meshClass = NSClassFromString(@"CAMutableMeshTransform");
    SEL create = NSSelectorFromString(@"meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:");
    if (!backdrop || !meshClass || ![meshClass respondsToSelector:create] ||
        size.width < 30 || size.height < 30) return;
    NSString *signature = [NSString stringWithFormat:@"rounded-v2:%.1f:%.1f:%.1f:%.1f",
                           size.width, size.height, radius, magnitude];
    if ([signature isEqual:objc_getAssociatedObject(glass, QBannerGlassMeshKey)]) return;
    CGFloat r = MAX(0, MIN(radius, MIN(size.width, size.height) / 2));
    CGFloat edgeDistance = MIN(12, MAX(r, 1));
    std::vector<QGlassVertex> vertices;
    std::vector<QGlassFace> faces;
    auto addVertex = [&](CGFloat x, CGFloat y, CGFloat depth = 0) -> uint32_t {
        CGFloat px = x - size.width / 2, py = y - size.height / 2;
        CGFloat qx = fabs(px) - size.width / 2 + r;
        CGFloat qy = fabs(py) - size.height / 2 + r;
        CGFloat nx = 0, ny = 0;
        if (qx > 0 && qy > 0) {
            CGFloat length = hypot(qx, qy);
            if (length > 0) { nx = qx / length; ny = qy / length; }
        } else if (qx > qy) nx = 1;
        else ny = 1;
        if (px < 0) nx = -nx;
        if (py < 0) ny = -ny;
        CGFloat distance = MAX(0, -QGlassSDF(x, y, size, r));
        CGFloat weight = QGlassBezier(MAX(0, MIN(1, 1 - distance / edgeDistance)));
        CGFloat edgeBand = MIN(2, r);
        if (edgeBand > 0) {
            CGFloat boost = MAX(0, MIN(1, (edgeBand - distance) / edgeBand));
            weight *= 1 + 0.5 * boost * boost * (3 - 2 * boost);
        }
        QGlassVertex vertex = {};
        vertex.from = CGPointMake(MAX(0, MIN(1, (x - nx * weight * magnitude) / size.width)),
                                  MAX(0, MIN(1, (y - ny * weight * magnitude) / size.height)));
        vertex.to = (QGlassPoint3D){x / size.width, y / size.height, depth};
        vertices.push_back(vertex);
        return (uint32_t)(vertices.size() - 1);
    };
    auto addFace = [&](uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
        QGlassFace face = {};
        face.indices[0] = a; face.indices[1] = b;
        face.indices[2] = c; face.indices[3] = d;
        faces.push_back(face);
    };
    auto addGrid = [&](const std::vector<CGFloat> &xs, const std::vector<CGFloat> &ys) {
        if (xs.size() < 2 || ys.size() < 2 ||
            xs.back() - xs.front() < 0.01 || ys.back() - ys.front() < 0.01) return;
        std::vector<uint32_t> indices;
        for (CGFloat y : ys) for (CGFloat x : xs) indices.push_back(addVertex(x, y));
        for (size_t row = 0; row + 1 < ys.size(); row++) {
            for (size_t column = 0; column + 1 < xs.size(); column++) {
                size_t top = row * xs.size() + column;
                addFace(indices[top], indices[top + 1],
                        indices[top + xs.size() + 1], indices[top + xs.size()]);
            }
        }
    };
    if (r < 1) {
        NSArray<NSNumber *> *oldX = QGlassGrid(size.width), *oldY = QGlassGrid(size.height);
        std::vector<CGFloat> xs, ys;
        for (NSNumber *number in oldX) xs.push_back(number.doubleValue);
        for (NSNumber *number in oldY) ys.push_back(number.doubleValue);
        addGrid(xs, ys);
    } else {
        std::vector<CGFloat> depths = {0};
        for (int i = 1; i < 12; i++) depths.push_back(r * i / 12);
        depths.push_back(r);
        if (r > 2) depths.push_back(2);
        std::sort(depths.begin(), depths.end());
        depths.erase(std::unique(depths.begin(), depths.end(), [](CGFloat a, CGFloat b) {
            return fabs(a - b) < 0.01;
        }), depths.end());
        std::vector<CGFloat> topY, bottomY, leftX, rightX, radii;
        for (CGFloat depth : depths) {
            topY.push_back(depth);
            bottomY.push_back(size.height - r + depth);
            leftX.push_back(depth);
            rightX.push_back(size.width - r + depth);
            if (depth < r - 0.01) radii.push_back(r - depth);
        }
        std::vector<CGFloat> middleX, middleY;
        for (int i = 0; i <= 7; i++) middleX.push_back(r + (size.width - 2 * r) * i / 7);
        for (int i = 0; i <= 7; i++) middleY.push_back(r + (size.height - 2 * r) * i / 7);
        addGrid(middleX, topY);
        addGrid(middleX, bottomY);
        addGrid(leftX, middleY);
        addGrid(rightX, middleY);
        addGrid(middleX, middleY);
        auto addCorner = [&](CGFloat cx, CGFloat cy, CGFloat start, CGFloat end) {
            std::vector<std::vector<uint32_t>> rings;
            for (CGFloat ringRadius : radii) {
                std::vector<uint32_t> ring;
                for (int i = 0; i <= 12; i++) {
                    CGFloat angle = start + (end - start) * i / 12;
                    ring.push_back(addVertex(cx + ringRadius * cos(angle),
                                             cy + ringRadius * sin(angle)));
                }
                rings.push_back(std::move(ring));
            }
            for (size_t row = 0; row + 1 < rings.size(); row++)
                for (size_t column = 0; column < 12; column++)
                    addFace(rings[row][column], rings[row][column + 1],
                            rings[row + 1][column + 1], rings[row + 1][column]);
            uint32_t center = addVertex(cx, cy, -0.02);
            const std::vector<uint32_t> &inner = rings.back();
            for (int i = 0; i < 12; i += 2)
                addFace(center, inner[i], inner[i + 1], inner[i + 2]);
        };
        addCorner(r, r, M_PI, 1.5 * M_PI);
        addCorner(size.width - r, r, 1.5 * M_PI, 2 * M_PI);
        addCorner(size.width - r, size.height - r, 0, 0.5 * M_PI);
        addCorner(r, size.height - r, 0.5 * M_PI, M_PI);
    }
    if (vertices.empty() || faces.empty()) return;
    @try {
        IMP imp = [meshClass methodForSelector:create];
        id (*makeMesh)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id) =
            (id (*)(id, SEL, NSUInteger, const void *, NSUInteger, const void *, id))imp;
        id mesh = makeMesh(meshClass, create, vertices.size(), vertices.data(),
                           faces.size(), faces.data(), @"none");
        if (mesh) {
            SEL steps = NSSelectorFromString(@"setSubdivisionSteps:");
            if ([mesh respondsToSelector:steps])
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(mesh, steps, 0);
            [backdrop setValue:mesh forKey:@"meshTransform"];
            objc_setAssociatedObject(glass, QBannerGlassMeshKey, signature,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
    } @catch (NSException *exception) {
        // Keep the undistorted live backdrop if the private mesh API differs.
    }
}

