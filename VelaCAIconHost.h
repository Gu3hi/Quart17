// Vendored from Vela (C:/db/prysm/shared/PCAIconHost.inc) so Quart17 plays Vela's animated
// media icons exactly as Vela does. Keep in sync with Vela; the host expects PFResource/PFSafePlist.

// Owned package layers: never take a view or layer from the system CC hierarchy.
@interface NSObject (VelaCAPackage)
+ (id)packageWithContentsOfURL:(NSURL *)url type:(NSString *)type options:(NSDictionary *)options error:(NSError **)error;
- (id)rootLayer;
- (id)initWithLayer:(CALayer *)layer;
- (void)setState:(id)state ofLayer:(CALayer *)layer;
- (void)setState:(id)state ofLayer:(CALayer *)layer transitionSpeed:(float)speed;
- (void)cancelTimers;
@end

@interface PCAMLValidator : NSObject <NSXMLParserDelegate>
@property(nonatomic,copy) NSString *directory;
@property(nonatomic) NSUInteger elements;
@property(nonatomic) BOOL valid;
@end
@implementation PCAMLValidator
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)name attributes:(NSDictionary<NSString *,NSString *> *)attributes {
    if(++_elements>20000){_valid=NO;[parser abortParsing];return;}
    for(NSString *key in @[@"src",@"url",@"href"]){NSString *reference=attributes[key];if(reference && !PFResource(_directory,reference)){_valid=NO;[parser abortParsing];return;}}
}
@end
static BOOL PCAValidDocument(NSString *path) {
    NSDictionary *index=PFSafePlist(PFResource(path,@"index.xml"));if(![index[@"rootDocument"] isEqual:@"main.caml"])return NO;
    NSString *file=PFResource(path,@"main.caml");NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
    if(!attrs || [attrs fileSize]>4194304)return NO;NSData *data=[NSData dataWithContentsOfFile:file];if(!data)return NO;
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];if(!text || [text containsString:@"<!DOCTYPE"] || [text containsString:@"<!ENTITY"])return NO;
    NSXMLParser *parser=[[NSXMLParser alloc] initWithData:data];parser.shouldResolveExternalEntities=NO;
    PCAMLValidator *validator=[PCAMLValidator new];validator.directory=path;validator.valid=YES;parser.delegate=validator;
    return [parser parse] && validator.valid;
}

static BOOL PCASignature(id object,SEL selector,NSUInteger arguments,char result) {
    NSMethodSignature *s=[object methodSignatureForSelector:selector];
    if(s.numberOfArguments!=arguments || s.methodReturnType[0]!=result)return NO;
    for(NSUInteger i=2;i<arguments;i++)if([s getArgumentTypeAtIndex:i][0]!='@' && !(i==5 && [s getArgumentTypeAtIndex:i][0]=='^'))return NO;
    return YES;
}
// renderInContext omits some 3D-transformed shape layers. Measure their actual
// paths in the owned tree instead, including shapes authored with zero bounds.
static CGRect PCAInkBounds(CALayer *layer,CALayer *canvas,NSUInteger *budget) {
    if(!*budget || layer.hidden || layer.opacity<.02)return CGRectNull;--*budget;
    CGRect ink=CGRectNull,local=CGRectNull;
    if([layer isKindOfClass:CAShapeLayer.class]){CAShapeLayer *shape=(CAShapeLayer *)layer;
        if(shape.path && ((shape.fillColor && CGColorGetAlpha(shape.fillColor)>.02) || (shape.strokeColor && CGColorGetAlpha(shape.strokeColor)>.02))){local=CGPathGetPathBoundingBox(shape.path);if(shape.strokeColor && CGColorGetAlpha(shape.strokeColor)>.02)local=CGRectInset(local,-shape.lineWidth/2,-shape.lineWidth/2);}
    }
    if((layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor)>.02) || layer.contents ||
       (layer.borderWidth>0 && layer.borderColor && CGColorGetAlpha(layer.borderColor)>.02))local=CGRectUnion(local,layer.bounds);
    if(!CGRectIsNull(local) && !CGRectIsEmpty(local)){CGRect box=[layer convertRect:local toLayer:canvas];if(isfinite(box.origin.x) && isfinite(box.origin.y) && isfinite(box.size.width) && isfinite(box.size.height))ink=box;}
    for(CALayer *child in layer.sublayers)ink=CGRectUnion(ink,PCAInkBounds(child,canvas,budget));
    if(layer.masksToBounds && !CGRectIsNull(ink))ink=CGRectIntersection(ink,[layer convertRect:layer.bounds toLayer:canvas]);
    return ink;
}
// Replicated rays and emitters draw outside the layer tree, so their ink cannot
// be measured. Those packages must keep the authored canvas as the scale basis.
static BOOL PCAHasLayerEffects(CALayer *layer,NSUInteger *budget) {
    if(!budget || !*budget)return YES;--*budget;
    if([layer isKindOfClass:NSClassFromString(@"CAReplicatorLayer")] || [layer isKindOfClass:NSClassFromString(@"CAEmitterLayer")])return YES;
    for(CALayer *child in layer.sublayers)if(PCAHasLayerEffects(child,budget))return YES;
    return NO;
}
@interface PCAIconHost : UIView
@property(nonatomic,strong) id package,controller;
@property(nonatomic,strong) CALayer *root;
@property(nonatomic,strong) CALayer *placement;
@property(nonatomic) CGRect visibleBounds;
@property(nonatomic) BOOL flipsVertically;
@property(nonatomic) BOOL templateForeground,mirrorsHorizontally,nativeSystem,masksForeground;
@property(nonatomic,strong) NSHashTable *solidLayers,*liftedLayers;
@property(nonatomic,strong) NSArray *foregrounds;
@property(nonatomic,strong) UIColor *foregroundInk;
@property(nonatomic) CGFloat foregroundLevel;
@property(nonatomic) BOOL paused;
@property(nonatomic,copy) NSString *path,*stateName;
@property(nonatomic,strong) NSDictionary *states;
- (BOOL)loadPath:(NSString *)path;
- (BOOL)applyStates:(NSArray *)names animated:(BOOL)animated;
- (void)updateForeground;
- (void)stop;
- (void)pause;
- (void)resume;
- (void)playTap;
@end
@implementation PCAIconHost
- (void)setMasksForeground:(BOOL)masked {
    _masksForeground=masked;
    if(_placement){
        if(masked){[_placement removeFromSuperlayer];if(self.layer.mask!=_placement)self.layer.mask=_placement;}
        else {if(self.layer.mask==_placement)self.layer.mask=nil;if(_placement.superlayer!=self.layer)[self.layer addSublayer:_placement];}
    }
    self.backgroundColor=masked && _placement?[self.tintColor resolvedColorWithTraitCollection:self.traitCollection]:UIColor.clearColor;
}
- (BOOL)loadPath:(NSString *)path {
    if([path isEqual:_path])return _root!=nil;
    [self stop];self.layer.mask=nil;self.backgroundColor=UIColor.clearColor;[_placement removeFromSuperlayer];_placement=nil;_root=nil;_package=nil;_controller=nil;_states=nil;_stateName=nil;_path=path;
    if(!PCAValidDocument(path))return NO;
    Class cls=NSClassFromString(@"CAPackage"),controllerClass=NSClassFromString(@"CAStateController");
    if(!PCASignature(cls,@selector(packageWithContentsOfURL:type:options:error:),6,'@') ||
       !PCASignature([controllerClass alloc],@selector(initWithLayer:),3,'@'))return NO;
    @try {
        id package=[cls packageWithContentsOfURL:[NSURL fileURLWithPath:path isDirectory:YES] type:@"com.apple.coreanimation-bundle" options:nil error:nil];
        if(!PCASignature(package,@selector(rootLayer),2,'@'))return NO;
        CALayer *root=[package rootLayer];if(![root isKindOfClass:CALayer.class])return NO;
        id controller=[[controllerClass alloc] initWithLayer:root];
        if(!PCASignature(controller,@selector(setState:ofLayer:),4,'v'))return NO;
        id states=[root valueForKey:@"states"];if(![states isKindOfClass:NSArray.class])return NO;
        NSMutableDictionary *map=[NSMutableDictionary new];for(id state in states){id name=[state valueForKey:@"name"];if([name isKindOfClass:NSString.class])map[name]=state;}
        if(!map.count || !isfinite(root.bounds.size.width) || !isfinite(root.bounds.size.height) || root.bounds.size.width<=0 || root.bounds.size.height<=0 || root.bounds.size.width>4096 || root.bounds.size.height>4096)return NO;
        _package=package;_controller=controller;_root=root;_states=map;
        _flipsVertically=![PFSafePlist(PFResource(path,@"index.xml"))[@"geometryFlipped"] boolValue];
        NSMethodSignature *flipped=[package methodSignatureForSelector:NSSelectorFromString(@"isGeometryFlipped")];
        if(flipped.numberOfArguments==2 && flipped.methodReturnLength==sizeof(BOOL) && (flipped.methodReturnType[0]=='B' || flipped.methodReturnType[0]=='c')){
            NSInvocation *invocation=[NSInvocation invocationWithMethodSignature:flipped];invocation.target=package;invocation.selector=NSSelectorFromString(@"isGeometryFlipped");[invocation invoke];BOOL value=NO;[invocation getReturnValue:&value];_flipsVertically=value;
        }
        _placement=[CALayer layer];_placement.bounds=root.bounds;[_placement addSublayer:root];
        // Native canvases carry generous transparent padding. Scaling by the
        // authored canvas makes padded glyphs (Wi-Fi, Bluetooth, bell, moon...)
        // render smaller than trimmed ones at the same box size. Measure the
        // resting state instead: unioning every state lets a large glow shrink
        // the glyph that is actually on screen. Packages whose ink cannot be
        // measured from the layer tree keep the authored canvas.
        _solidLayers=[NSHashTable weakObjectsHashTable];
        NSUInteger effectBudget=8192;
        BOOL measurable=!PCAHasLayerEffects(root,&effectBudget);
        CGRect ink=CGRectNull;
        if(_nativeSystem){
            if(measurable){NSUInteger budget=4096;ink=PCAInkBounds(root,_placement,&budget);}
        }else for(NSString *name in [@[@""] arrayByAddingObjectsFromArray:[map.allKeys sortedArrayUsingSelector:@selector(compare:)]] ){
            [self applyStates:@[name] animated:NO];[self stop];
            NSUInteger budget=4096;ink=CGRectUnion(ink,PCAInkBounds(root,_placement,&budget));
        }
        [self stop];
        // State probes mutate their layer tree. Display a fresh package so an
        // empty base state cannot inherit properties left by a measured state.
        package=[cls packageWithContentsOfURL:[NSURL fileURLWithPath:path isDirectory:YES] type:@"com.apple.coreanimation-bundle" options:nil error:nil];
        root=[package rootLayer];if(![root isKindOfClass:CALayer.class])return NO;
        _package=package;_root=root;_controller=[[controllerClass alloc] initWithLayer:root];_stateName=nil;
        map=[NSMutableDictionary new];for(id state in [root valueForKey:@"states"]){NSString *name=[state valueForKey:@"name"];if([name isKindOfClass:NSString.class])map[name]=state;}_states=map;
        _foregrounds=nil;_solidLayers=[NSHashTable weakObjectsHashTable];_liftedLayers=[NSHashTable weakObjectsHashTable];_placement=[CALayer layer];[_placement addSublayer:root];
        if(_nativeSystem && !CGRectIsNull(ink)){
            // Keep the measurement inside the authored canvas, then re-centre it on
            // the canvas. Scaling the ink rectangle in place moved asymmetric glyphs
            // off centre; the canvas centre is the reference the system authored.
            ink=CGRectIntersection(ink,root.bounds);
            CGFloat canvasW=root.bounds.size.width,canvasH=root.bounds.size.height;
            if(CGRectIsNull(ink) || ink.size.width<canvasW*.2 || ink.size.height<canvasH*.2)ink=CGRectNull;
            else {
                CGFloat margin=MAX(1,MIN(ink.size.width,ink.size.height)*.04);
                CGFloat width=MIN(ink.size.width+margin*2,canvasW),height=MIN(ink.size.height+margin*2,canvasH);
                CGPoint centre=CGPointMake(CGRectGetMidX(root.bounds),CGRectGetMidY(root.bounds));
                ink=CGRectMake(centre.x-width/2,centre.y-height/2,width,height);
            }
        }
        _visibleBounds=CGRectIsNull(ink)?root.bounds:ink;self.clipsToBounds=NO;[self setMasksForeground:_masksForeground];[self setNeedsLayout];return YES;
    } @catch(NSException *exception){return NO;}
}
- (BOOL)applyStates:(NSArray *)names animated:(BOOL)animated {
    NSString *name=nil;for(NSString *candidate in names)if(_states[candidate] || candidate.length==0){name=candidate;break;}
    if(!name)return NO;if([name isEqual:_stateName])return YES;
    @try {
        [CATransaction begin];[CATransaction setDisableActions:!animated];
        [self restoreForeground];
        NSMethodSignature *speed=[_controller methodSignatureForSelector:@selector(setState:ofLayer:transitionSpeed:)];
        if(speed.numberOfArguments==5 && speed.methodReturnType[0]=='v' && [speed getArgumentTypeAtIndex:2][0]=='@' && [speed getArgumentTypeAtIndex:3][0]=='@' && [speed getArgumentTypeAtIndex:4][0]=='f')
            [_controller setState:name.length?_states[name]:nil ofLayer:_root transitionSpeed:animated?1:0];
        else [_controller setState:name.length?_states[name]:nil ofLayer:_root];
        _foregrounds=nil;[self updateForeground];[CATransaction commit];_stateName=name;return YES;
    } @catch(NSException *exception){[CATransaction commit];return NO;}
}
- (void)layoutSubviews {
    [super layoutSubviews];if(!_root)return;CGSize s=_visibleBounds.size;
    CGFloat scale=MIN(self.bounds.size.width/s.width,self.bounds.size.height/s.height);
    [CATransaction begin];[CATransaction setDisableActions:YES];_placement.bounds=_visibleBounds;
    // CAPackage reports the flip needed to display its authored canvas in UIKit.
    _placement.transform=CATransform3DMakeScale(_mirrorsHorizontally?-scale:scale,_flipsVertically?-scale:scale,1);_placement.position=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));[CATransaction commit];
}
- (void)restoreForeground {
    for(NSDictionary *item in _foregrounds)[self setInkColor:(__bridge CGColorRef)item[@"color"] item:item];
}
- (void)setInkColor:(CGColorRef)color item:(NSDictionary *)item {
    CALayer *layer=item[@"layer"];NSString *key=item[@"key"];
    if([key isEqual:@"backgroundColor"])layer.backgroundColor=color;
    else if([key isEqual:@"borderColor"])layer.borderColor=color;
    else if([key isEqual:@"fillColor"])((CAShapeLayer *)layer).fillColor=color;
    else if([key isEqual:@"strokeColor"])((CAShapeLayer *)layer).strokeColor=color;
}
- (void)updateForeground {
    if(!_templateForeground && !_nativeSystem){[self restoreForeground];return;}
    UIColor *ink=[self.tintColor resolvedColorWithTraitCollection:self.traitCollection];
    // Native state transitions can write RGB after tinting; a template mask keeps the entire animation in one ink.
    if(_masksForeground)self.backgroundColor=ink;
    if(_foregrounds && [_foregroundInk isEqual:ink])return;
    if(!_foregrounds){NSMutableArray *colors=[NSMutableArray new],*layers=[NSMutableArray new],*alphas=[NSMutableArray new],*masks=[NSMutableArray new],*partial=[NSMutableArray new];
        if(_root){[layers addObject:_root];[alphas addObject:@1.0];[masks addObject:@NO];}
        CGFloat peak=0,brightnessPeak=0;
        for(NSUInteger i=0;i<layers.count && i<4096;i++){
            CALayer *layer=layers[i];CGFloat parent=[alphas[i] doubleValue];
            // A package often carries several variants (wifi-dark / wifi-dark-static
            // / wifi-light) stacked with opacity 0. The hidden variants still hold
            // fully opaque shapes, so comparing raw layer opacity picked their 1.0
            // as the peak and left the visible 0.6 shape untouched. Track the
            // effective opacity down the tree instead.
            BOOL hidden=layer.hidden;CGFloat own=hidden?0:layer.opacity,effective=parent*own;
            BOOL mask=[masks[i] boolValue];
            @try {if([@[@"destIn",@"destOut",@"sourceIn",@"sourceOut"] containsObject:[layer.compositingFilter valueForKey:@"name"]?:@""])mask=YES;}@catch(NSException *exception){}
            NSArray *children=layer.sublayers;
            if(children)for(CALayer *child in children){[layers addObject:child];[alphas addObject:@(effective)];[masks addObject:@(mask)];}
            // Only the native path skips invisible variants; theme packages keep
            // the previous walk so their authored layers are untouched.
            if(_nativeSystem && effective<=.05)continue;
            if(parent>=.95 && own>.05 && own<.95)[partial addObject:layer];
            // Only real ink may set the peak. A CAML canvas usually carries
            // <backgroundColor opacity="0">, which CA still hands back as a
            // non-nil colour with alpha 0. Counting it made the root count as a
            // fully opaque layer, so peak stayed 1.0 and the 0.6 glyphs of
            // WiFi/Bluetooth were never lifted — they kept rendering as a
            // washed-out grey tint.
            BOOL fill=(layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor)>.02);
            if([layer isKindOfClass:CAShapeLayer.class]){CAShapeLayer *shape=(CAShapeLayer *)layer;
                fill=fill || (shape.fillColor && CGColorGetAlpha(shape.fillColor)>.02) || (shape.strokeColor && CGColorGetAlpha(shape.strokeColor)>.02);}
            if(effective>peak && fill)peak=effective;
            if(_nativeSystem && layer.compositingFilter){
                @try {id name=[layer.compositingFilter valueForKey:@"name"];
                    // plusD/plusL brighten against the CC backdrop. Prysm owns the
                    // backdrop, so drop the filter and compensate the layer alpha;
                    // otherwise neutral glyphs stay at 60% and look transparent.
                    // WiFi.ca is the only package we render that uses this filter:
                    // its three arcs are authored at opacity 0.6 and only read as
                    // solid white because of the additive blend, so the opacity has
                    // to come back here. Faded-out states (below 0.3) keep theirs.
                    if([@[@"plusD",@"plusL"] containsObject:name]){layer.compositingFilter=nil;if(effective>=.3)layer.opacity=1;if(_solidLayers)[_solidLayers addObject:layer];}
                }@catch(NSException *exception){}
            }
            NSUInteger firstColor=colors.count;
            if(![layer isKindOfClass:CATransformLayer.class]){
                if(layer.backgroundColor)[colors addObject:@{@"layer":layer,@"key":@"backgroundColor",@"color":(__bridge id)layer.backgroundColor}];
                if(layer.borderWidth>0 && layer.borderColor)[colors addObject:@{@"layer":layer,@"key":@"borderColor",@"color":(__bridge id)layer.borderColor}];
            }
            if([layer isKindOfClass:CAShapeLayer.class]){CAShapeLayer *shape=(CAShapeLayer *)layer;
                if(shape.fillColor)[colors addObject:@{@"layer":shape,@"key":@"fillColor",@"color":(__bridge id)shape.fillColor}];
                if(shape.strokeColor)[colors addObject:@{@"layer":shape,@"key":@"strokeColor",@"color":(__bridge id)shape.strokeColor}];
            }
            if(!_nativeSystem && effective>.05 && !mask && (![layer isKindOfClass:CAShapeLayer.class] || ((CAShapeLayer *)layer).path))
                for(NSUInteger j=firstColor;j<colors.count;j++){CGFloat r,g,b,a;UIColor *color=[UIColor colorWithCGColor:(__bridge CGColorRef)colors[j][@"color"]];
                    if([color getRed:&r green:&g blue:&b alpha:&a] && a>.02 && MAX(r,MAX(g,b))-MIN(r,MIN(g,b))<=.08)brightnessPeak=MAX(brightnessPeak,MAX(.25,MAX(r,MAX(g,b))));
                }
        }
        // Authored glyphs rely on the additive filter and a 0.6 layer opacity to
        // read as solid over the CC backdrop. Without that backdrop, lift the peak
        // to opaque while keeping the relative hierarchy inside the glyph.
        if(_nativeSystem && peak>.05 && peak<.95)for(CALayer *layer in partial){layer.opacity=MIN(1,layer.opacity/peak);if(_liftedLayers)[_liftedLayers addObject:layer];}
        _foregroundLevel=MAX(.25,brightnessPeak);_foregrounds=colors;
    }
    _foregroundInk=ink;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(NSDictionary *item in _foregrounds){UIColor *original=[UIColor colorWithCGColor:(__bridge CGColorRef)item[@"color"]];CGFloat r,g,b,a;
        if(![original getRed:&r green:&g blue:&b alpha:&a] || (MAX(r,MAX(g,b))-MIN(r,MIN(g,b))>.08 && !(_nativeSystem && _templateForeground)))continue;
        // A layer whose opacity had to be lifted is part of a glyph that was
        // authored translucent; its colour must go solid with it, otherwise the
        // mark still reads as a washed-out tint over the tile.
        BOOL solid=_nativeSystem && ([_solidLayers containsObject:item[@"layer"]] || [_liftedLayers containsObject:item[@"layer"]]);
        // Normalize the visible palette, not its masks or hidden state variants.
        CGFloat alpha=_nativeSystem?(solid?1:a):a*MIN(1,MAX(.25,MAX(r,MAX(g,b)))/_foregroundLevel);
        CGColorRef color=[ink colorWithAlphaComponent:alpha].CGColor;
        [self setInkColor:color item:item];
    }[CATransaction commit];
}
- (void)tintColorDidChange {[super tintColorDidChange];[self updateForeground];}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous])[self updateForeground];
}
- (void)playTap {
    if(_states[@"State 1"] && _states[@"State 2"])[self applyStates:@[[_stateName isEqual:@"State 2"]?@"State 1":@"State 2"] animated:YES];
    else if(_states[@"ffwd0 shape"] && _states[@"ffwd3 shape"])[self applyStates:@[[_stateName isEqual:@"ffwd3 shape"]?@"ffwd0 shape":@"ffwd3 shape"] animated:YES];
}
- (void)stop {
    [self resume];
    if(PCASignature(_controller,@selector(cancelTimers),2,'v'))[_controller cancelTimers];
    NSMutableArray *layers=[NSMutableArray array];if(_root)[layers addObject:_root];
    for(NSUInteger i=0;i<layers.count && i<4096;i++){CALayer *layer=layers[i];[layer removeAllAnimations];[layers addObjectsFromArray:layer.sublayers?:@[]];}
}
- (void)pause {
    if(_paused || !_root)return;
    CFTimeInterval time=[_root convertTime:CACurrentMediaTime() fromLayer:nil];
    _root.speed=0;_root.timeOffset=time;_paused=YES;
}
- (void)resume {
    if(!_paused || !_root)return;
    CFTimeInterval time=_root.timeOffset;_root.speed=1;_root.timeOffset=0;_root.beginTime=0;
    _root.beginTime=[_root convertTime:CACurrentMediaTime() fromLayer:nil]-time;_paused=NO;
}
- (void)dealloc {[self stop];}
@end
