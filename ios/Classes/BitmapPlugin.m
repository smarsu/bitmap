#import "BitmapPlugin.h"
#import "Render.h"

@interface BitmapPlugin ()

@property (nonatomic) NSObject<FlutterTextureRegistry> *textures;
@property (nonatomic) NSMutableDictionary<NSNumber *, Render *> *renders;
@property (nonatomic) NSLock *glock;  // The global lock to lock all sub texture threads.

@end

@implementation BitmapPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel
      methodChannelWithName:@"bitmap"
      binaryMessenger:[registrar messenger]];
  BitmapPlugin *instance = [[BitmapPlugin alloc] initWithTexture:[registrar textures]];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"r" isEqualToString:call.method]) {  // render
    NSNumber *textureId = call.arguments[@"textureId"];
    NSString *path = call.arguments[@"path"];
    int width = [call.arguments[@"width"] intValue];
    int height = [call.arguments[@"height"] intValue];
    int fit = [call.arguments[@"fit"] intValue];
    NSString *bitmap = call.arguments[@"bitmap"];
    bool findCache = [call.arguments[@"findCache"] boolValue];
        
    if ([textureId intValue] == -1) {
      NSInteger __block id = 0;  // Register TextureId
      Render *render = [[Render alloc] initWithCallback:^() {
        [self.textures textureFrameAvailable:id];
      } width:width height:height];
      id = (NSInteger) [_textures registerTexture:render];
      [render setId:id];
      [render setLock:_glock];
      [render r:result path:path width:width height:height fit:fit bitmap:bitmap findCache:findCache];
      _renders[@(id)] = render;
    }
    else {
      Render *render = _renders[textureId];
      [render r:result path:path width:width height:height fit:fit bitmap:bitmap findCache:findCache];
    }
  }
  else if ([@"dl" isEqualToString:call.method]) {  // dispose list
    NSArray<NSNumber *> *textureIds = call.arguments[@"textureIds"];
    for (NSNumber *textureId in textureIds) {
      Render *render = _renders[textureId];
      [render d];
      [_renders removeObjectForKey:textureId];
      [_textures unregisterTexture:[textureId longValue]];
    }
    result(nil);
  }
}

- (instancetype)initWithTexture:(NSObject<FlutterTextureRegistry> *)textures {
  self = [super init];
  if (self) {
    _textures = textures;
    _renders = [[NSMutableDictionary alloc] init];
    _glock = [[NSLock alloc] init];
  }
  return self;
}

@end
