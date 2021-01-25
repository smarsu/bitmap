#import <Flutter/Flutter.h>

@interface Render : NSObject<FlutterTexture>

- (instancetype)initWithCallback:(void (^)(void))callback width:(int)width height:(int)height;

- (void)r:(FlutterResult)result path:(NSString *)path width:(int)width height:(int)height fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache;

- (void)d;

- (void)setId:(NSInteger)textureId;

- (void)setLock:(NSLock *)glock;

@end
