#import "GLKit/GLKit.h"
#import "OpenGLES/ES2/glext.h"

#import "Render.h"

typedef struct {
    GLKVector3 positionCoord;
    GLKVector2 textureCoord;
} SenceVertex;

@interface Render ()

@property (nonatomic) void (^callback)(void);
@property (nonatomic) NSThread *thread;
@property (nonatomic) NSInteger textureId;
@property (atomic) NSLock *glock;  // The global lock get from BitmapPlugin.

@property (nonatomic) CVPixelBufferRef target;
@property (nonatomic) CVOpenGLESTextureCacheRef textureCache;
@property (nonatomic) CVOpenGLESTextureRef texture;

@property (nonatomic) GLuint depthBuffer;
@property (nonatomic) GLuint frameBuffer;
@property (nonatomic) GLuint vertexBuffer;
@property (nonatomic) SenceVertex *vertices;

@property (atomic) NSLock *lock;  // The lock of paths.
@property (atomic) NSLock *dlock;  // The lock of dispose.
@property (atomic) bool canceled;

@property (nonatomic) EAGLContext *context;
@property (nonatomic) GLuint program;
@property (nonatomic) GLuint vertexShader;
@property (nonatomic) GLuint fragmentShader;

@property (nonatomic) FlutterResult result;
@property (nonatomic) NSString *path;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) int fit;
@property (nonatomic) NSString *bitmap;
@property (nonatomic) bool findCache;

@property (nonatomic) void *colors;  // The raw rgba data of image.

@end

@implementation Render

- (instancetype)initWithCallback:(void (^)(void))callback width:(int)width height:(int)height {
  self = [super init];
  if (self) {
    _callback = callback;
    _width = width;
    _height = height;
    
    _vertices = NULL;
    _colors = NULL;
    _canceled = false;
    
    _target = nil;
    _textureCache = nil;
    _texture = nil;
    
    _lock = [[NSLock alloc] init];
    _dlock = [[NSLock alloc] init];
    
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(render) object:nil];
    [_thread start];
  }
  return self;
}

- (void)setId:(NSInteger)textureId {
  _textureId = textureId;
}

- (void)setLock:(NSLock *)glock {
  _glock = glock;
}

- (void)r:(FlutterResult)result path:(NSString *)path width:(int)width height:(int)height fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache {
  [self.lock lock];
  _result    = result;
  _path      = path;
  _width     = width;
  _height    = height;
  _fit       = fit;
  _bitmap    = bitmap;
  _findCache = findCache;
  [self.lock unlock];
}

- (void)d {
  _canceled = true;
  [self dispose];
}

- (void)render {
  [_dlock lock];  // lock for dispose.
  
  FlutterResult result;
  NSString *path   = NULL;
  int width        = 0;
  int height       = 0;
  int fit          = 0;
  NSString *bitmap = NULL;
  bool findCache   = false;
  
  _colors = malloc(_height * _width * 4);
  
  [_glock lock];  // Need to add global lock to avoid glDrawArrays crash?
  [self doInit];
  glFinish();
  [_glock unlock];

  while (true) {
    CFTimeInterval t1 = CACurrentMediaTime();

    if (_canceled) {
      break;
    }
    
    [_lock lock];
    bool needRender = path != _path || width != _width || height != _height || fit != _fit || bitmap != _bitmap || findCache != _findCache;
    result    = _result;
    path      = _path;
    width     = _width;
    height    = _height;
    fit       = _fit;
    bitmap    = _bitmap;
    findCache = _findCache;
    [_lock unlock];
    
    if (needRender) {
      [self makeBitMap:path width:width height:height fit:fit bitmap:bitmap findCache:findCache];
      if (!_canceled) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _width, _height, 0, GL_RGBA, GL_UNSIGNED_BYTE, _colors);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glFlush();
        _callback();
      }
      result(@(_textureId));  // you must result for once render call.
    }
    
    CFTimeInterval t2 = CACurrentMediaTime();
    CFTimeInterval wait = 0.016 - (t2 - t1);
    if (wait > 0) {
      [NSThread sleepForTimeInterval:wait];
    }
  }
  
  [_dlock unlock];  // unlock for dispose.
}

- (void)doInit {
  _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  [EAGLContext setCurrentContext:_context];
  [self createProgram];
  
  CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_textureCache);

  CFDictionaryRef empty;
  CFMutableDictionaryRef attrs;
  empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
  CVPixelBufferCreate(kCFAllocatorDefault, (size_t) _width, (size_t) _height, kCVPixelFormatType_32BGRA, attrs, &_target);
  CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, _target, NULL, GL_TEXTURE_2D, GL_RGBA, (GLsizei) _width, (GLsizei) _height, GL_BGRA, GL_UNSIGNED_BYTE, 0, &_texture);
  
  CFRelease(empty);
  CFRelease(attrs);
  
  glBindTexture(CVOpenGLESTextureGetTarget(_texture), CVOpenGLESTextureGetName(_texture));
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei) _width, (GLsizei) _height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
  glGenRenderbuffers(1, &_depthBuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, _depthBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, (GLsizei) _width, (GLsizei) _height);
  glGenFramebuffers(1, &_frameBuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(_texture), 0);
  glFramebufferRenderbuffer(GL_RENDERBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthBuffer);
  
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    NSLog(@"Can not glCheckFramebufferStatus");
  }
  
  glViewport(0, 0, (GLsizei) _width, (GLsizei) _height);
  
  glBindTexture(GL_TEXTURE_2D, 0);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);
  
  glUseProgram(_program);
  
  GLuint positionSlot = (GLuint) glGetAttribLocation(_program, "Position");
  GLuint textureSlot = (GLuint) glGetUniformLocation(_program, "Texture");
  GLuint textureCoordsSlot = (GLuint) glGetAttribLocation(_program, "TextureCoords");

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, 0);
  glUniform1i(textureSlot, 0);
  
  glGenBuffers(1, &_vertexBuffer);
  glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
  GLsizeiptr bufferSizeBytes = sizeof(SenceVertex) * 4;
  _vertices = malloc(sizeof(SenceVertex) * 4);
  _vertices[0] = (SenceVertex) {{-1,   1, 0}, {0, 0}};
  _vertices[1] = (SenceVertex) {{-1,  -1, 0}, {0, 1}};
  _vertices[2] = (SenceVertex) {{ 1,   1, 0}, {1, 0}};
  _vertices[3] = (SenceVertex) {{ 1,  -1, 0}, {1, 1}};
  glBufferData(GL_ARRAY_BUFFER, bufferSizeBytes, _vertices, GL_STATIC_DRAW);

  glEnableVertexAttribArray(positionSlot);
  glVertexAttribPointer(positionSlot, 3, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL + offsetof(SenceVertex, positionCoord));

  glEnableVertexAttribArray(textureCoordsSlot);
  glVertexAttribPointer(textureCoordsSlot, 2, GL_FLOAT, GL_FALSE, sizeof(SenceVertex), NULL + offsetof(SenceVertex, textureCoord));
}

- (void)createProgram {
  _vertexShader = [self loadShader:GL_VERTEX_SHADER source:@"glsl"];
  _fragmentShader = [self loadShader:GL_FRAGMENT_SHADER source:@"glsl"];
  
  _program = glCreateProgram();
  glAttachShader(_program, _vertexShader);
  glAttachShader(_program, _fragmentShader);
  
  glLinkProgram(_program);
  GLint ok = 0;
  glGetProgramiv(_program, GL_LINK_STATUS, &ok);
}

- (GLuint)loadShader:(GLenum)type source:(NSString *)source {
  NSBundle *bundle = [NSBundle bundleWithPath: [
      [NSBundle bundleForClass:[self class]].resourcePath
                stringByAppendingPathComponent:@"/BitMap.bundle"]];
  NSString *shaderstr = [NSString
    stringWithContentsOfFile:[bundle pathForResource:source ofType:type == GL_VERTEX_SHADER ? @"vsh" : @"fsh"]
    encoding:NSUTF8StringEncoding
    error:NULL];
  
  GLuint shader = glCreateShader(type);
  const char *shaderutf8 = [shaderstr UTF8String];
  int len = (int) [shaderstr length];
  glShaderSource(shader, 1, &shaderutf8, &len);
  
  glCompileShader(shader);
  GLint ok = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  
  return shader;
}

- (void)makeBitMap:(NSString *)path width:(int)width height:(int)height fit:(int)fit bitmap:(NSString *)bitmap findCache:(bool)findCache {
  if (!findCache) {
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    image = [self resizeCrop:image size:CGSizeMake(_width, _height)];
    [self imageToColor:image];
    NSMutableData *data = [[NSMutableData alloc] init];
    [data appendBytes:_colors length:_height * _width * 4];
    [data writeToFile:bitmap atomically:YES];
  }
  else {
    NSData *reader = [NSData dataWithContentsOfFile:bitmap];
    [reader getBytes:_colors length:_height * _width * 4];
  }
}

- (UIImage *)resizeCrop: (UIImage *)image size:(CGSize)size {
  int width = size.width;
  int height = size.height;
  
  CGImageRef cgImageRef = [image CGImage];
  size_t srcWidth = CGImageGetWidth(cgImageRef);
  size_t srcHeight = CGImageGetHeight(cgImageRef);
  float scale = MAX(width / srcWidth, height / srcHeight);
  int dstWidth = round(srcWidth * scale);
  int dstHeight = round(srcHeight * scale);
  int x = (dstWidth - width) / 2;
  int y = (dstHeight - height) / 2;
  
  UIGraphicsBeginImageContext(CGSizeMake(dstWidth, dstHeight));
  [image drawInRect:CGRectMake(0, 0, dstWidth, dstHeight)];
  UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  
  CGImageRef cgResizedImageRef = [resizedImage CGImage];
  CGImageRef cgCropedImageRef = CGImageCreateWithImageInRect(cgResizedImageRef, CGRectMake(x, y, width, height));
  
  UIImage *cropedImage = [UIImage imageWithCGImage:cgCropedImageRef];

  CGImageRelease(cgCropedImageRef);
  
  return cropedImage;
}

- (void)imageToColor:(UIImage *)image {
  CGImageRef cgImageRef = [image CGImage];
  CGRect rect = CGRectMake(0, 0, _width, _height);

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(_colors, _width, _height, 8, _width * 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGContextTranslateCTM(context, 0, _height);
  CGContextScaleCTM(context, 1.f, -1.f);
  CGColorSpaceRelease(colorSpace);
  CGContextClearRect(context, rect);
  CGContextDrawImage(context, rect, cgImageRef);

  CGContextRelease(context);
}

- (void)dispose {
  [_dlock lock];  // lock for render.
  
  if (_vertices) free(_vertices);
  if (_colors) free(_colors);
  
  glDeleteProgram(_program);
  glDeleteShader(_vertexShader);
  glDeleteShader(_fragmentShader);
  
  [EAGLContext setCurrentContext:_context];
  glFinish();
  glDeleteBuffers(1, &_vertexBuffer);
  glDeleteRenderbuffers(1, &_depthBuffer);
  glDeleteFramebuffers(1, &_frameBuffer);

  if (_texture) {
    CFRelease(_texture);
  }
  if (_target) {
    CFRelease(_target);
  }
  if (_textureCache) {
    CFRelease(_textureCache);
  }
  
  [_dlock unlock];  // unlock for render.
}

#pragma mark - FlutterTexture

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  if (_target) {
    CVBufferRetain(_target);
  }
  return _target;
}

@end
