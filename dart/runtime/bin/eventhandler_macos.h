// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef BIN_EVENTHANDLER_MACOS_H_
#define BIN_EVENTHANDLER_MACOS_H_

#if !defined(BIN_EVENTHANDLER_H_)
#error Do not include eventhandler_macos.h directly; use eventhandler.h instead.
#endif

#include <unistd.h>
#include <errno.h>
#include <sys/event.h>  // NOLINT
#include <sys/socket.h>

#include "platform/hashmap.h"


namespace dart {
namespace bin {

class InterruptMessage {
 public:
  intptr_t id;
  Dart_Port dart_port;
  int64_t data;
};


class SocketData {
 public:
  explicit SocketData(intptr_t fd)
      : fd_(fd),
        port_(0),
        mask_(0),
        tracked_by_kqueue_(false) {
    ASSERT(fd_ != -1);
  }

  bool HasReadEvent();
  bool HasWriteEvent();

  void ShutdownRead() {
    shutdown(fd_, SHUT_RD);
  }

  void ShutdownWrite() {
    shutdown(fd_, SHUT_WR);
  }

  void Close() {
    port_ = 0;
    mask_ = 0;
    close(fd_);
    fd_ = -1;
  }

  bool IsListeningSocket() { return (mask_ & (1 << kListeningSocket)) != 0; }
  bool IsPipe() { return (mask_ & (1 << kPipe)) != 0; }

  void SetPortAndMask(Dart_Port port, intptr_t mask) {
    ASSERT(fd_ != -1);
    port_ = port;
    mask_ = mask;
  }

  intptr_t fd() { return fd_; }
  Dart_Port port() { return port_; }
  intptr_t mask() { return mask_; }
  bool tracked_by_kqueue() { return tracked_by_kqueue_; }
  void set_tracked_by_kqueue(bool value) {
    tracked_by_kqueue_ = value;
  }

 private:
  intptr_t fd_;
  Dart_Port port_;
  intptr_t mask_;
  bool tracked_by_kqueue_;
};


class EventHandlerImplementation {
 public:
  EventHandlerImplementation();
  ~EventHandlerImplementation();

  // Gets the socket data structure for a given file
  // descriptor. Creates a new one if one is not found.
  SocketData* GetSocketData(intptr_t fd, bool* is_new);
  void Notify(intptr_t id, Dart_Port dart_port, int64_t data);
  void Start(EventHandler* handler);
  void Shutdown();

 private:
  int64_t GetTimeout();
  void HandleEvents(struct kevent* events, int size);
  void HandleTimeout();
  static void EventHandlerEntry(uword args);
  void WakeupHandler(intptr_t id, Dart_Port dart_port, int64_t data);
  void HandleInterruptFd();
  void SetPort(intptr_t fd, Dart_Port dart_port, intptr_t mask);
  intptr_t GetEvents(struct kevent* event, SocketData* sd);
  static void* GetHashmapKeyFromFd(intptr_t fd);
  static uint32_t GetHashmapHashFromFd(intptr_t fd);

  HashMap socket_map_;
  TimeoutQueue timeout_queue_;
  bool shutdown_;
  int interrupt_fds_[2];
  int kqueue_fd_;
};

}  // namespace bin
}  // namespace dart

#endif  // BIN_EVENTHANDLER_MACOS_H_
