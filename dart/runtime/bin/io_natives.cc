// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "bin/io_natives.h"

#include <stdlib.h>
#include <string.h>

#include "bin/builtin.h"
#include "bin/dartutils.h"
#include "include/dart_api.h"
#include "platform/assert.h"


namespace dart {
namespace bin {

// Lists the native functions implementing advanced dart:io classes.
// Some classes, like File and Directory, list their implementations in
// builtin_natives.cc instead.
#define IO_NATIVE_LIST(V)                                                      \
  V(Crypto_GetRandomBytes, 1)                                                  \
  V(EventHandler_Start, 1)                                                     \
  V(EventHandler_SendData, 4)                                                  \
  V(Filter_CreateZLibDeflate, 3)                                               \
  V(Filter_CreateZLibInflate, 1)                                               \
  V(Filter_End, 1)                                                             \
  V(Filter_Process, 2)                                                         \
  V(Filter_Processed, 3)                                                       \
  V(InternetAddress_Fixed, 1)                                                  \
  V(Platform_NumberOfProcessors, 0)                                            \
  V(Platform_OperatingSystem, 0)                                               \
  V(Platform_PathSeparator, 0)                                                 \
  V(Platform_LocalHostname, 0)                                                 \
  V(Platform_ExecutableName, 0)                                                \
  V(Platform_Environment, 0)                                                   \
  V(Platform_ExecutableArguments, 0)                                           \
  V(Platform_PackageRoot, 0)                                                   \
  V(Platform_GetVersion, 0)                                                    \
  V(Process_Start, 10)                                                         \
  V(Process_Wait, 5)                                                           \
  V(Process_Kill, 3)                                                           \
  V(Process_SetExitCode, 1)                                                    \
  V(Process_Exit, 1)                                                           \
  V(Process_Sleep, 1)                                                          \
  V(Process_Pid, 1)                                                            \
  V(SecureSocket_Connect, 9)                                                   \
  V(SecureSocket_Destroy, 1)                                                   \
  V(SecureSocket_Handshake, 1)                                                 \
  V(SecureSocket_Init, 1)                                                      \
  V(SecureSocket_PeerCertificate, 1)                                           \
  V(SecureSocket_RegisterBadCertificateCallback, 2)                            \
  V(SecureSocket_RegisterHandshakeCompleteCallback, 2)                         \
  V(SecureSocket_Renegotiate, 4)                                               \
  V(SecureSocket_InitializeLibrary, 3)                                         \
  V(SecureSocket_NewServicePort, 0)                                            \
  V(SecureSocket_FilterPointer, 1)                                             \
  V(ServerSocket_CreateBindListen, 5)                                          \
  V(ServerSocket_Accept, 2)                                                    \
  V(Socket_CreateConnect, 3)                                                   \
  V(Socket_Available, 1)                                                       \
  V(Socket_Read, 2)                                                            \
  V(Socket_WriteList, 4)                                                       \
  V(Socket_GetPort, 1)                                                         \
  V(Socket_GetRemotePeer, 1)                                                   \
  V(Socket_GetError, 1)                                                        \
  V(Socket_GetStdioHandle, 2)                                                  \
  V(Socket_NewServicePort, 0)                                                  \
  V(Socket_GetType, 1)                                                         \
  V(Socket_SetOption, 3)                                                       \
  V(Stdin_ReadByte, 1)                                                         \
  V(Stdin_SetEchoMode, 2)                                                      \
  V(Stdin_SetLineMode, 2)                                                      \
  V(StringToSystemEncoding, 1)                                                 \
  V(SystemEncodingToString, 1)


IO_NATIVE_LIST(DECLARE_FUNCTION);

static struct NativeEntries {
  const char* name_;
  Dart_NativeFunction function_;
  int argument_count_;
} IOEntries[] = {
  IO_NATIVE_LIST(REGISTER_FUNCTION)
};


Dart_NativeFunction IONativeLookup(Dart_Handle name,
                                   int argument_count) {
  const char* function_name = NULL;
  Dart_Handle result = Dart_StringToCString(name, &function_name);
  DART_CHECK_VALID(result);
  ASSERT(function_name != NULL);
  int num_entries = sizeof(IOEntries) / sizeof(struct NativeEntries);
  for (int i = 0; i < num_entries; i++) {
    struct NativeEntries* entry = &(IOEntries[i]);
    if (!strcmp(function_name, entry->name_) &&
        (entry->argument_count_ == argument_count)) {
      return reinterpret_cast<Dart_NativeFunction>(entry->function_);
    }
  }
  return NULL;
}

}  // namespace bin
}  // namespace dart
