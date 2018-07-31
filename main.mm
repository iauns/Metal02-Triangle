#include <TargetConditionals.h> // For TARGET_OS_IPHONE and TARGET_OS_MAC

#if TARGET_OS_IPHONE  // TARGET_OS_IPHONE must come first.
  #import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
  #import <Cocoa/Cocoa.h>
#else
  #error Unknown Platform
#endif

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>

//------------------------------------------------------------------------------
// Global Variables
//------------------------------------------------------------------------------
// Intentional breaking of encapsulation: we will not be reusing NSView or UIView.
id<MTLDevice>               g_mtlDevice;
id<MTLCommandQueue>         g_mtlCommandQueue;
id<MTLRenderPipelineState>  g_mtlPipelineState;

//------------------------------------------------------------------------------
// Objective-C Interfaces
//------------------------------------------------------------------------------
#if TARGET_OS_IPHONE

  @interface AppDelegate : UIResponder <UIApplicationDelegate>
  @property (strong, nonatomic) UIWindow* window;
  @end

  @interface MetalView : UIView
  @property (nonatomic, assign) CAMetalLayer* metalLayer;
  @property (nonatomic, strong) CADisplayLink* displayLink;
  @end

#elif TARGET_OS_MAC

  @interface AppDelegate : NSObject <NSApplicationDelegate>
  @property (strong, nonatomic) NSWindow* window;
  @end

  @interface MetalView : NSView
  @property (nonatomic, assign) CAMetalLayer* metalLayer;
  @end

#endif // TARGET_OS_IPHONE || TARGET_OS_MAC

//------------------------------------------------------------------------------
// Implementation
//------------------------------------------------------------------------------

const char* g_shaderCode = R"D4LIN4R(
#include <metal_stdlib>

using namespace metal;

struct VertexOutput
{
  float4 position [[position]];
  float4 color;
};

vertex VertexOutput render_vertex(uint vid [[vertex_id]])
{
  VertexOutput vertexOut;
  // Clockwise winding order
  if (vid == 0)
  {
    // Middle top of screen.
    vertexOut.position = float4(0.0, 1.0, 0.0, 1.0);
    vertexOut.color = float4(1.0, 0.3, 0.3, 1.0);
  }
  else if (vid == 1)
  {
    // Bottom right
    vertexOut.position = float4(1.0, -1.0, 0.0, 1.0);
    vertexOut.color = float4(0.3, 1.0, 0.3, 1.0);
  }
  else if (vid == 2)
  {
    // Bottom left
    vertexOut.position = float4(-1.0, -1.0, 0.0, 1.0);
    vertexOut.color = float4(0.3, 0.3, 1.0, 1.0);
  }
  return vertexOut;
}

fragment float4 render_fragment(VertexOutput vertexIn [[stage_in]])
{
  return vertexIn.color;
}
)D4LIN4R";

void doRender()
{
  if (!g_nsView.metalLayer)
  {
    fprintf(stderr, "Warning: No metal layer, skipping render.\n");
    return;
  }

  id<CAMetalDrawable> drawable = [g_nsView.metalLayer nextDrawable];
  id<MTLTexture> texture = drawable.texture;

  MTLRenderPassDescriptor* passDescriptor =
      [MTLRenderPassDescriptor renderPassDescriptor];
  passDescriptor.colorAttachments[0].texture     = texture;
  passDescriptor.colorAttachments[0].loadAction  = MTLLoadActionClear;
  passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
  passDescriptor.colorAttachments[0].clearColor =
      MTLClearColorMake(0.3f, 0.3f, 0.3f, 1.0f);

  id<MTLCommandBuffer> commandBuffer = [g_mtlCommandQueue commandBuffer];

  id<MTLRenderCommandEncoder> commandEncoder =
      [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];

  [commandEncoder setFrontFacingWinding:MTLWindingClockwise];
  [commandEncoder setCullMode:MTLCullModeNone];
  [commandEncoder setRenderPipelineState:g_mtlPipelineState];

  [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                     vertexStart:0
                     vertexCount:3];

  [commandEncoder endEncoding];

  [commandBuffer presentDrawable:drawable];
  [commandBuffer commit];
}

int renderInit()
{
  g_mtlDevice = MTLCreateSystemDefaultDevice();
  if (!g_mtlDevice)
  {
    fprintf(stderr, "System does not support metal.\n");
    return EXIT_FAILURE;
  }

  g_mtlCommandQueue = [g_mtlDevice newCommandQueue];

  //------------------------------------------
  // Shader Compilation and Pipeline Creation
  //------------------------------------------
  NSString* source = [[NSString alloc] initWithUTF8String:g_shaderCode];
  MTLCompileOptions* compileOpts = [[MTLCompileOptions alloc] init];
  compileOpts.languageVersion = MTLLanguageVersion2_0;

  NSError* err = nil;
  id<MTLLibrary> library = [g_mtlDevice newLibraryWithSource:source options:compileOpts error:&err];

  [compileOpts release];
  [source release];

  if (err)
  {
    NSLog(@"%@", err);
    [library release];
    return EXIT_FAILURE;
  }

  // Create pipeline state.
  MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
  pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"render_vertex"];
  pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"render_fragment"];

  [library release];

  pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatInvalid;

  NSError* error = nil;
  g_mtlPipelineState = [g_mtlDevice newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
  if (!g_mtlPipelineState)
  {
    NSLog(@"Failed to create render pipeline state: %@", error);
  }

  return EXIT_SUCCESS;
}

void renderDestroy()
{
  [g_mtlPipelineState release];
  [g_mtlCommandQueue release];
  [g_mtlDevice release];
}

int main(int argc, char *argv[])
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

  if (renderInit() != EXIT_SUCCESS)
  {
    return EXIT_FAILURE;
  }

#if TARGET_OS_IPHONE
  return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
#elif TARGET_OS_MAC
  NSApplication * application = [NSApplication sharedApplication];
  
  AppDelegate * applicationDelegate = [[[AppDelegate alloc] init] autorelease];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp activateIgnoringOtherApps:YES];
  [application setDelegate:applicationDelegate];

  [application run];

  // Will never get here.
  [pool drain];

  return EXIT_SUCCESS;
#endif
}

//------------------------------------------------------------------------------
// iOS UIKit Implementation
//------------------------------------------------------------------------------
#if TARGET_OS_IPHONE
@interface MainViewController : UIViewController
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  self.window.backgroundColor = [UIColor whiteColor];
  
  MainViewController* viewController = [[MainViewController alloc] init];
  self.window.rootViewController = viewController;
  
  [self.window makeKeyAndVisible];
  return YES;
}

@end // AppDelegate

@implementation MainViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self)
  {
    // Custom initialization
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  // Add in our metal view.
  CGRect contentSize = self.view.bounds;
  g_nsView    = [[MetalView alloc]  initWithFrame:contentSize];
    
  g_nsView.bounds = self.view.bounds;
  [self.view addSubview:g_nsView];
}

- (BOOL)prefersStatusBarHidden {
  return YES;
}

@end

@implementation MetalView
- (BOOL)acceptsFirstResponder { return YES; }

+ (Class)layerClass
{
  return [CAMetalLayer class];
}
- (CAMetalLayer *)metalLayer
{
  return (CAMetalLayer *)self.layer;
}
- (instancetype)initWithFrame:(CGRect)frameRect
{
  if ((self = [super initWithFrame:frameRect]))
  {
    self.metalLayer.device = g_mtlDevice;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = true; // Note: setting this will dissallow sampling and reading from texture.
    self.metalLayer.frame = frameRect;

    CGSize drawableSize = self.bounds.size;
    
    // Since drawable size is in pixels, we need to multiply by the scale to move from points to pixels
    CGFloat scale = [UIScreen mainScreen].scale;
    drawableSize.width *= scale;
    drawableSize.height *= scale;
    
    self.metalLayer.drawableSize = drawableSize;
  }
  return self;
}

- (void)dealloc
{
  [_displayLink invalidate];
  renderDestroy();
  [super dealloc];
}

- (void)didMoveToSuperview
{
  [super didMoveToSuperview];
  if (self.superview)
  {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkDidFire:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  }
  else
  {
    [self.displayLink invalidate];
    self.displayLink = nil;
  }
}

- (void)displayLinkDidFire:(CADisplayLink *)displayLink
{
  doRender();
}
@end

//------------------------------------------------------------------------------
// macOS Cocoa Implementation
//------------------------------------------------------------------------------
#elif TARGET_OS_MAC

CVDisplayLinkRef g_displayLink;

static const int k_WindowWidth  = 800;
static const int k_WindowHeight = 600;

static CVReturn displayLinkCallback(
    CVDisplayLinkRef displayLink,
    const CVTimeStamp* now,
    const CVTimeStamp* outputTime,
    CVOptionFlags flagsIn,
    CVOptionFlags* flagsOut,
    void* displayLinkContext)
{
  doRender();
  return kCVReturnSuccess;
}

@interface MyNSWindow : NSWindow
- (BOOL)canBecomeMainWindow;
- (BOOL)canBecomeKeyWindow;
- (BOOL)acceptsFirstResponder;
- (void)keyDown:(NSEvent *)anEvent;
@end

@implementation MyNSWindow
- (BOOL)canBecomeMainWindow { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)anEvent
{
  unsigned short keyCode = [anEvent keyCode];
  printf("Key code: %d\n", keyCode);
  if (keyCode == 53 || keyCode == 49)
  {
    [self close];
  }
}
@end

@implementation AppDelegate
- (id)init
{
  if ( self = [super init] ) { }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSRect contentSize = NSMakeRect(0.0f, 0.0f, k_WindowWidth, k_WindowHeight);
  g_nsView    = [[MetalView alloc]  initWithFrame:contentSize];

  const int style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
  self.window = [[MyNSWindow alloc] initWithContentRect:contentSize
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:YES];
  [self.window setTitle:@"Metal Example"];
  [self.window setOpaque:YES];
  [self.window setContentView:g_nsView];
  [self.window makeMainWindow];
  [self.window makeKeyAndOrderFront:nil];
  [self.window makeFirstResponder:nil];

  [self.window makeKeyAndOrderFront:self];

  [g_nsView awakeFromNib];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)theApplication
{
  return true;
}
@end

@implementation MetalView
+ (id)layerClass
{
  return [CAMetalLayer class];
}

- (CALayer*)makeBackingLayer
{
  CAMetalLayer* backingLayer = [CAMetalLayer layer];
  self.metalLayer = backingLayer;
  return self.metalLayer;
}

- (instancetype)initWithFrame:(CGRect)frameRect
{
  if ((self = [super initWithFrame:frameRect]))
  {
    self.wantsLayer = YES; // Providing Metal layer through makeBackingLayer

    if (!g_mtlDevice)
    {
      fprintf(stderr, "MetalView: ERROR - Metal device has not be created.\n");
    }

    self.metalLayer.device = g_mtlDevice;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  }
  return self;
}

- (void)awakeFromNib
{
  // As the last thing we do, fire up the display link timer for rendering.
  // Create callback for rendering purposes. Need to check thread ids. I
  // presume this CVDisplayLink callback is issued from the CFRunLoop
  // generated by issuing a call to [NSApp run].
  CVDisplayLinkCreateWithActiveCGDisplays(&g_displayLink);
  CVDisplayLinkSetOutputCallback(g_displayLink, &displayLinkCallback, 0);
  CVDisplayLinkSetCurrentCGDisplay(g_displayLink, 0);
  CVDisplayLinkStart(g_displayLink);
}

- (void)dealloc
{
  CVDisplayLinkStop(g_displayLink);
  CVDisplayLinkRelease(g_displayLink);
  renderDestroy();
  [super dealloc];
}
@end

#endif // TARGET_OS_IPHONE / TARGET_OS_MAC
