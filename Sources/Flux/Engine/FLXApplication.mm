#import "FLXApplication.h"

namespace {

BOOL (^g_key_down_handler)(NSEvent *) = nil;
id g_monitor = nil;

}  // namespace

@implementation FLXApplication

+ (BOOL (^)(NSEvent *))keyDownHandler {
  return g_key_down_handler;
}

+ (void)setKeyDownHandler:(BOOL (^)(NSEvent *))handler {
  g_key_down_handler = [handler copy];
  if (g_monitor) return;
  g_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown
                                                    handler:^NSEvent *(NSEvent *event) {
    if (event.type == NSEventTypeKeyDown) {
      return g_key_down_handler && g_key_down_handler(event) ? nil : event;
    }
    return event;
  }];
}

@end
