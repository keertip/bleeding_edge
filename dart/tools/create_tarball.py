#!/usr/bin/env python
#
# Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#

# Script to build a tarball of the Dart source.
#
# The tarball includes all the source needed to build Dart. This
# includes source in third_party. As part of creating the tarball the
# files used to build Debian packages are copied to a top-level debian
# directory. This makes it easy to build Debian packages from the
# tarball.
#
# For building a Debian package one need to the tarball to follow the
# Debian naming rules upstream tar files.
#
#  $ mv dart-XXX.tar.gz dart_XXX.orig.tar.gz
#  $ tar xf dart_XXX.orig.tar.gz
#  $ cd dart_XXX
#  $ debuild -us -uc

import datetime
import optparse
import sys
import tarfile
import utils

from os import listdir, makedirs
from os.path import join, exists, split, dirname, abspath

HOST_OS = utils.GuessOS()
DART_DIR = abspath(join(__file__, '..', '..'))

# TODO (16582): Remove this when the LICENSE file becomes part of
# all checkouts.
license = [
  'This license applies to all parts of Dart that are not externally',
  'maintained libraries. The external maintained libraries used by',
  'Dart are:',
  '',
  '7-Zip - in third_party/7zip',
  'JSCRE - in runtime/third_party/jscre',
  'Ant - in third_party/apache_ant',
  'args4j - in third_party/args4j',
  'bzip2 - in third_party/bzip2',
  'Commons IO - in third_party/commons-io',
  'Commons Lang in third_party/commons-lang',
  'dromaeo - in samples/third_party/dromaeo',
  'Eclipse - in third_party/eclipse',
  'gsutil - in third_party/gsutil',
  'Guava - in third_party/guava',
  'hamcrest - in third_party/hamcrest',
  'Httplib2 - in samples/third_party/httplib2',
  'JSON - in third_party/json',
  'JUnit - in third_party/junit',
  'Oauth - in samples/third_party/oauth2client',
  'weberknecht - in third_party/weberknecht',
  'fest - in third_party/fest',
  'mockito - in third_party/mockito',
  '',
  'The libraries may have their own licenses; we recommend you read them,',
  'as their terms may differ from the terms below.',
  '',
  'Copyright 2012, the Dart project authors. All rights reserved.',
  'Redistribution and use in source and binary forms, with or without',
  'modification, are permitted provided that the following conditions are',
  'met:',
  '    * Redistributions of source code must retain the above copyright',
  '      notice, this list of conditions and the following disclaimer.',
  '    * Redistributions in binary form must reproduce the above',
  '      copyright notice, this list of conditions and the following',
  '      disclaimer in the documentation and/or other materials provided',
  '      with the distribution.',
  '    * Neither the name of Google Inc. nor the names of its',
  '      contributors may be used to endorse or promote products derived',
  '      from this software without specific prior written permission.',
  'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS',
  '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT',
  'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR',
  'A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT',
  'OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,',
  'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT',
  'LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,',
  'DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY',
  'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT',
  '(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE',
  'OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'
]

# Flags.
verbose = False

# Name of the dart directory when unpacking the tarball.
versiondir = ''

# Ignore Git/SVN files, checked-in binaries, backup files, etc..
ignoredPaths = ['tools/testing/bin'
                'third_party/7zip', 'third_party/android_tools',
                'third_party/clang', 'third_party/d8',
                'third_party/firefox_jsshell']
ignoredDirs = ['.svn', '.git']
ignoredEndings = ['.mk', '.pyc', 'Makefile', '~']

def BuildOptions():
  result = optparse.OptionParser()
  result.add_option("-v", "--verbose",
      help='Verbose output.',
      default=False, action="store_true")
  return result

def Filter(tar_info):
  # Get the name of the file relative to the dart directory. Note the
  # name from the TarInfo does not include a leading slash.
  assert tar_info.name.startswith(DART_DIR[1:])
  original_name = tar_info.name[len(DART_DIR):]
  _, tail = split(original_name)
  if tail in ignoredDirs:
    return None
  for path in ignoredPaths:
    if original_name.startswith(path):
      return None
  for ending in ignoredEndings:
    if original_name.endswith(ending):
      return None
  # Add the dart directory name with version. Place the debian
  # directory one level over the rest which are placed in the
  # directory 'dart'. This enables building the Debian packages
  # out-of-the-box.
  tar_info.name = join(versiondir, 'dart', original_name)
  if verbose:
    print 'Adding %s as %s' % (original_name, tar_info.name)
  return tar_info

def GenerateCopyright(filename):
  license_lines = license
  try:
    # TODO (16582): The LICENSE file is currently not in a normal the
    # dart checkout.
    with open(join(DART_DIR, 'LICENSE')) as lf:
      license_lines = lf.read().splitlines()
  except:
    pass

  with open(filename, 'w') as f:
    f.write('Name: dart\n')
    f.write('Maintainer: Dart Team <misc@dartlang.org>\n')
    f.write('Source: https://code.google.com/p/dart/\n')
    f.write('License:\n')
    for line in license_lines:
      f.write(' %s\n' % line)

def GenerateChangeLog(filename, version):
  with open(filename, 'w') as f:
    f.write('dart (%s-1) UNRELEASED; urgency=low\n' % version)
    f.write('\n')
    f.write('  * Generated file.\n')
    f.write('\n')
    f.write(' -- Dart Team <misc@dartlang.org>  %s\n' %
            datetime.datetime.utcnow().strftime('%a, %d %b %Y %X +0000'))

def GenerateSvnRevision(filename, svn_revision):
  with open(filename, 'w') as f:
    f.write(svn_revision)


def CreateTarball():
  global ignoredPaths  # Used for adding the output directory.
  # Generate the name of the tarfile
  version = utils.GetVersion()
  global versiondir
  versiondir = 'dart-%s' % version
  tarname = '%s.tar.gz' % versiondir
  debian_dir = 'tools/linux_dist_support/debian'
  # Create the tar file in the build directory.
  tardir = join(DART_DIR, utils.GetBuildDir(HOST_OS, HOST_OS))
  # Don't include the build directory in the tarball.
  ignoredPaths.append(tardir)
  if not exists(tardir):
    makedirs(tardir)
  tarfilename = join(tardir, tarname)
  print 'Creating tarball: %s' % tarfilename
  with tarfile.open(tarfilename, mode='w:gz') as tar:
    for f in listdir(DART_DIR):
      tar.add(join(DART_DIR, f), filter=Filter)
    for f in listdir(join(DART_DIR, debian_dir)):
      tar.add(join(DART_DIR, debian_dir, f),
              arcname='%s/debian/%s' % (versiondir, f))

    with utils.TempDir() as temp_dir:
      # Generate and add debian/copyright
      copyright = join(temp_dir, 'copyright')
      GenerateCopyright(copyright)
      tar.add(copyright, arcname='%s/debian/copyright' % versiondir)

      # Generate and add debian/changelog
      change_log = join(temp_dir, 'changelog')
      GenerateChangeLog(change_log, version)
      tar.add(change_log, arcname='%s/debian/changelog' % versiondir)

      # For bleeding_edge add the SVN_REVISION file.
      if utils.GetChannel() == 'be':
        svn_revision = join(temp_dir, 'SVN_REVISION')
        GenerateSvnRevision(svn_revision, utils.GetSVNRevision())
        tar.add(svn_revision, arcname='%s/dart/tools/SVN_REVISION' % versiondir)

def Main():
  if HOST_OS != 'linux':
    print 'Tarball can only be created on linux'
    return -1

  # Parse the options.
  parser = BuildOptions()
  (options, args) = parser.parse_args()
  if options.verbose:
    global verbose
    verbose = True

  CreateTarball()

if __name__ == '__main__':
  sys.exit(Main())
