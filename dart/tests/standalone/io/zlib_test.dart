// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

void testZLibDeflate() {
  test(int level, List<int> expected) {
    var port = new ReceivePort();
    var data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    var controller = new StreamController(sync: true);
    controller.stream.transform(new ZLibDeflater(gzip: false, level: level))
        .fold([], (buffer, data) {
          buffer.addAll(data);
          return buffer;
        })
        .then((data) {
          Expect.listEquals(expected, data);
          port.close();
        });
    controller.add(data);
    controller.close();
  }
  test(6, [120, 156, 99, 96, 100, 98, 102, 97, 101, 99, 231, 224, 4, 0, 0, 175,
           0, 46]);
}


void testZLibDeflateEmpty() {
  var port = new ReceivePort();
  var controller = new StreamController(sync: true);
  controller.stream.transform(new ZLibDeflater(gzip: false, level: 6))
      .fold([], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      })
      .then((data) {
        Expect.listEquals([120, 156, 3, 0, 0, 0, 0, 1], data);
        port.close();
      });
  controller.close();
}


void testZLibDeflateGZip() {
  var port = new ReceivePort();
  var data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  var controller = new StreamController(sync: true);
  controller.stream.transform(new ZLibDeflater())
      .fold([], (buffer, data) {
        buffer.addAll(data);
        return buffer;
      })
      .then((data) {
        Expect.equals(30, data.length);
        Expect.listEquals([99, 96, 100, 98, 102, 97, 101, 99, 231, 224, 4, 0,
                           70, 215, 108, 69, 10, 0, 0, 0],
                          // Skip header, as it can change.
                          data.sublist(10));
        port.close();
      });
  controller.add(data);
  controller.close();
}

void testZLibDeflateInvalidLevel() {
  test2(gzip, level) {
    var port = new ReceivePort();
    try {
      new ZLibDeflater(gzip: gzip, level: level);
    } catch (e) {
      port.close();
    }
  }
  test(level) {
    test2(false, level);
    test2(true, level);
    test2(9, level);
  }
  test(-2);
  test(-20);
  test(10);
  test(42);
  test(null);
  test("9");
}

void testZLibInflate() {
  test2(bool gzip, int level) {
    var port = new ReceivePort();
    var data = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
    var controller = new StreamController(sync: true);
    controller.stream
      .transform(new ZLibDeflater(gzip: gzip, level: level))
      .transform(new ZLibInflater())
        .fold([], (buffer, data) {
          buffer.addAll(data);
          return buffer;
        })
        .then((inflated) {
          Expect.listEquals(data, inflated);
          port.close();
        });
    controller.add(data);
    controller.close();
  }
  void test(int level) {
    test2(false, level);
    test2(true, level);
  }
  for (int i = -1; i < 10; i++) {
    test(i);
  }
}

void main() {
  testZLibDeflate();
  testZLibDeflateEmpty();
  testZLibDeflateGZip();
  testZLibDeflateInvalidLevel();
  testZLibInflate();
}
