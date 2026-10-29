#import "FLXDevTools.h"

/// Puts the pipe on file descriptors 3 and 4, before Chromium starts. Returns false if they are taken.
bool FLXDevToolsOpenPipe();

/// Chromium keeps running while a pipe client is attached, so the pipe is closed when quitting.
void FLXDevToolsHangUp();
