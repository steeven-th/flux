#import "FLXDevTools+Internal.h"

#include <fcntl.h>
#include <initializer_list>
#include <unistd.h>

// With --remote-debugging-pipe, Chromium reads protocol messages from file descriptor 3 and writes
// its replies to 4, each message ending with a NUL byte. Chromium runs inside this process, so Flux
// holds the other end of both pipes.
namespace {

int g_write_fd = -1;
dispatch_source_t g_read_source = nil;
NSMutableData *g_buffer = nil;
NSMutableDictionary<NSNumber *, void (^)(NSDictionary *, NSString *)> *g_pending = nil;
NSInteger g_next_id = 1;
void (^g_event_handler)(NSString *, NSDictionary *, NSString *) = nil;

void Deliver(NSData *message) {
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:message options:0 error:nil];
  if (![json isKindOfClass:NSDictionary.class]) return;
  NSNumber *messageID = json[@"id"];
  if (![messageID isKindOfClass:NSNumber.class]) {
    NSString *method = json[@"method"];
    if (g_event_handler && [method isKindOfClass:NSString.class]) {
      g_event_handler(method, json[@"params"] ?: @{}, json[@"sessionId"]);
    }
    return;
  }
  void (^completion)(NSDictionary *, NSString *) = g_pending[messageID];
  [g_pending removeObjectForKey:messageID];
  if (!completion) return;
  if (NSDictionary *error = json[@"error"]) {
    completion(nil, [error[@"message"] description] ?: @"error");
  } else {
    completion(json[@"result"] ?: @{}, nil);
  }
}

void ReadAvailable(int fd) {
  char bytes[65536];
  ssize_t count = read(fd, bytes, sizeof bytes);
  if (count <= 0) {
    dispatch_source_cancel(g_read_source);
    return;
  }
  [g_buffer appendBytes:bytes length:(NSUInteger)count];
  NSData *terminator = [NSData dataWithBytes:"" length:1];
  for (;;) {
    NSRange end = [g_buffer rangeOfData:terminator options:0 range:NSMakeRange(0, g_buffer.length)];
    if (end.location == NSNotFound) break;
    Deliver([g_buffer subdataWithRange:NSMakeRange(0, end.location)]);
    [g_buffer replaceBytesInRange:NSMakeRange(0, end.location + 1) withBytes:NULL length:0];
  }
}

}  // namespace

bool FLXDevToolsOpenPipe() {
  if (g_write_fd >= 0) return true;
  // Descriptors 3 and 4 must be free for Chromium to take them.
  if (fcntl(3, F_GETFD) != -1 || fcntl(4, F_GETFD) != -1) return false;

  int to_chromium[2];
  int from_chromium[2];
  if (pipe(to_chromium) != 0) return false;
  if (pipe(from_chromium) != 0) {
    close(to_chromium[0]);
    close(to_chromium[1]);
    return false;
  }
  // pipe() may itself return 3 or 4, so every end first moves above 10.
  int our_write = fcntl(to_chromium[1], F_DUPFD_CLOEXEC, 10);
  int our_read = fcntl(from_chromium[0], F_DUPFD_CLOEXEC, 10);
  int chromium_read = fcntl(to_chromium[0], F_DUPFD, 10);
  int chromium_write = fcntl(from_chromium[1], F_DUPFD, 10);
  for (int fd : {to_chromium[0], to_chromium[1], from_chromium[0], from_chromium[1]}) close(fd);
  dup2(chromium_read, 3);
  dup2(chromium_write, 4);
  close(chromium_read);
  close(chromium_write);

  g_write_fd = our_write;
  g_buffer = [NSMutableData data];
  g_pending = [NSMutableDictionary dictionary];
  g_read_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, our_read, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(g_read_source, ^{
    ReadAvailable(our_read);
  });
  dispatch_source_set_cancel_handler(g_read_source, ^{
    close(our_read);
  });
  dispatch_resume(g_read_source);
  return true;
}

void FLXDevToolsHangUp() {
  if (g_write_fd < 0) return;
  close(g_write_fd);
  g_write_fd = -1;
}

@implementation FLXDevTools

+ (void)reservePipe {
  FLXDevToolsOpenPipe();
}

+ (BOOL)isAvailable {
  return g_write_fd >= 0;
}

+ (void)sendMethod:(NSString *)method
            params:(NSDictionary<NSString *, id> *)params
         sessionID:(NSString *)sessionID
        completion:(void (^)(NSDictionary<NSString *, id> *, NSString *))completion {
  if (g_write_fd < 0) {
    completion(nil, @"DevTools pipe unavailable");
    return;
  }
  NSNumber *messageID = @(g_next_id++);
  NSMutableDictionary *message = [@{@"id": messageID, @"method": method, @"params": params} mutableCopy];
  if (sessionID) message[@"sessionId"] = sessionID;
  NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] mutableCopy];
  [data appendBytes:"" length:1];
  g_pending[messageID] = [completion copy];
  const uint8_t *bytes = (const uint8_t *)data.bytes;
  NSUInteger written = 0;
  while (written < data.length) {
    ssize_t count = write(g_write_fd, bytes + written, data.length - written);
    if (count <= 0) {
      [g_pending removeObjectForKey:messageID];
      completion(nil, @"DevTools pipe write failed");
      return;
    }
    written += (NSUInteger)count;
  }
}

+ (void (^)(NSString *, NSDictionary<NSString *, id> *, NSString *))eventHandler {
  return g_event_handler;
}

+ (void)setEventHandler:(void (^)(NSString *, NSDictionary<NSString *, id> *, NSString *))handler {
  g_event_handler = [handler copy];
}

@end
