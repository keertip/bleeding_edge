// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of dart_backend;

// TODO(ahe): This class is simply wrong.  This backend should use
// elements when it can, not AST nodes.  Perhaps a [Map<Element,
// TreeElements>] is what is needed.
class ElementAst {
  final Node ast;
  final TreeElements treeElements;

  ElementAst(this.ast, this.treeElements);

  ElementAst.forClassLike(this.ast)
      : this.treeElements = new TreeElementMapping(null);
}

// TODO(ahe): This class should not subclass [TreeElementMapping], if
// anything, it should implement TreeElements.
class AggregatedTreeElements extends TreeElementMapping {
  final List<TreeElements> treeElements;

  AggregatedTreeElements() : treeElements = <TreeElements>[], super(null);

  Element operator[](Node node) {
    final result = super[node];
    return result != null ? result : getFirstNotNullResult((e) => e[node]);
  }

  Selector getSelector(Send send) {
    final result = super.getSelector(send);
    return result != null ?
        result : getFirstNotNullResult((e) => e.getSelector(send));
  }

  DartType getType(Node node) {
    final result = super.getType(node);
    return result != null ?
        result : getFirstNotNullResult((e) => e.getType(node));
  }

  getFirstNotNullResult(f(TreeElements element)) {
    for (final element in treeElements) {
      final result = f(element);
      if (result != null) return result;
    }

    return null;
  }
}

class VariableListAst extends ElementAst {
  VariableListAst(ast) : super(ast, new AggregatedTreeElements());

  add(VariableElement element, TreeElements treeElements) {
    AggregatedTreeElements e = this.treeElements;
    e[element.cachedNode] = element;
    e.treeElements.add(treeElements);
  }
}

class DartBackend extends Backend {
  final List<CompilerTask> tasks;
  final bool forceStripTypes;
  final bool stripAsserts;
  // TODO(antonm): make available from command-line options.
  final bool outputAst = false;
  final Map<Node, String> renames;
  final Map<LibraryElement, String> imports;
  final Map<ClassNode, List<Node>> memberNodes;
  Map<Element, LibraryElement> reexportingLibraries;

  // TODO(zarah) Maybe change this to a command-line option.
  // Right now, it is set by the tests.
  bool useMirrorHelperLibrary = false;

  /// Initialized if the useMirrorHelperLibrary field is set.
  MirrorRenamer mirrorRenamer;

  /// Initialized when dart:mirrors is loaded if the useMirrorHelperLibrary
  /// field is set.
  LibraryElement mirrorHelperLibrary;
  /// Initialized when dart:mirrors is loaded if the useMirrorHelperLibrary
  /// field is set.
  FunctionElement mirrorHelperGetNameFunction;
  /// Initialized when dart:mirrors is loaded if the useMirrorHelperLibrary
  /// field is set.
  Element mirrorHelperSymbolsMap;

  Map<Element, TreeElements> get resolvedElements =>
      compiler.enqueuer.resolution.resolvedElements;

  /**
   * Tells whether it is safe to remove type declarations from variables,
   * functions parameters. It becomes not safe if:
   * 1) TypeError is used somewhere in the code,
   * 2) The code has typedefs in right hand side of IS checks,
   * 3) The code has classes which extend typedefs, have type arguments typedefs
   *    or type variable bounds typedefs.
   * These restrictions can be less strict.
   */
  bool isSafeToRemoveTypeDeclarations(
      Map<ClassElement, Set<Element>> classMembers) {
    Set<DartType> processedTypes = new Set<DartType>();
    List<DartType> workQueue = new List<DartType>();
    workQueue.addAll(
        classMembers.keys.map((classElement) => classElement.thisType));
    workQueue.addAll(compiler.resolverWorld.isChecks);
    Element typeErrorElement =
        compiler.coreLibrary.find('TypeError');
    DartType typeErrorType = typeErrorElement.computeType(compiler);
    if (workQueue.indexOf(typeErrorType) != -1) {
      return false;
    }

    while (!workQueue.isEmpty) {
      DartType type = workQueue.removeLast();
      if (processedTypes.contains(type)) continue;
      processedTypes.add(type);
      if (type is FunctionType) return false;
      if (type is TypedefType) return false;
      if (type is InterfaceType) {
        InterfaceType interfaceType = type;
        // Check all type arguments.
        workQueue.addAll(interfaceType.typeArguments.toList());
        ClassElement element = type.element;
        // Check all supertypes.
        if (element.allSupertypes != null) {
          workQueue.addAll(element.allSupertypes.toList());
        }
      }
    }
    return true;
  }

  DartBackend(Compiler compiler, List<String> strips)
      : tasks = <CompilerTask>[],
        renames = new Map<Node, String>(),
        imports = new Map<LibraryElement, String>(),
        memberNodes = new Map<ClassNode, List<Node>>(),
        reexportingLibraries = <Element, LibraryElement>{},
        forceStripTypes = strips.indexOf('types') != -1,
        stripAsserts = strips.indexOf('asserts') != -1,
        super(compiler);

  bool classNeedsRti(ClassElement cls) => false;
  bool methodNeedsRti(FunctionElement function) => false;

  void enqueueHelpers(ResolutionEnqueuer world, TreeElements elements) {
    // Right now resolver doesn't always resolve interfaces needed
    // for literals, so force them. TODO(antonm): fix in the resolver.
    final LITERAL_TYPE_NAMES = const [
      'Map', 'List', 'num', 'int', 'double', 'bool'
    ];
    final coreLibrary = compiler.coreLibrary;
    for (final name in LITERAL_TYPE_NAMES) {
      ClassElement classElement = coreLibrary.findLocal(name);
      classElement.ensureResolved(compiler);
    }
    // Enqueue the methods that the VM might invoke on user objects because
    // we don't trust the resolution to always get these included.
    world.registerInvocation(
        new Selector.call("toString", null, 0));
    world.registerInvokedGetter(
        new Selector.getter("hashCode", null));
    world.registerInvocation(
        new Selector.binaryOperator("=="));
    world.registerInvocation(
        new Selector.call("compareTo", null, 1));
  }

  void codegen(CodegenWorkItem work) { }

  bool isUserLibrary(LibraryElement lib) {
    final INTERNAL_HELPERS = [
      compiler.jsHelperLibrary,
      compiler.interceptorsLibrary,
    ];
    return INTERNAL_HELPERS.indexOf(lib) == -1 && !lib.isPlatformLibrary;
  }

  void assembleProgram() {
    // Conservatively traverse all platform libraries and collect member names.
    // TODO(antonm): ideally we should only collect names of used members,
    // however as of today there are problems with names of some core library
    // interfaces, most probably for interfaces of literals.
    final fixedMemberNames = new Set<String>();
    for (final library in compiler.libraries.values) {
      if (!library.isPlatformLibrary) continue;
      library.implementation.forEachLocalMember((Element element) {
        if (element.isClass()) {
          ClassElement classElement = element;
          // Make sure we parsed the class to initialize its local members.
          // TODO(smok): Figure out if there is a better way to fill local
          // members.
          element.parseNode(compiler);
          classElement.forEachLocalMember((member) {
            final name = member.name;
            // Skip operator names.
            if (!name.startsWith(r'operator$')) {
              // Fetch name of named constructors and factories if any,
              // otherwise store regular name.
              // TODO(antonm): better way to analyze the name.
              fixedMemberNames.add(name.split(r'$').last);
            }
          });
        }
        // Even class names are added due to a delicate problem we have:
        // if one imports dart:core with a prefix, we cannot tell prefix.name
        // from dynamic invocation (alas!).  So we'd better err on preserving
        // those names.
        fixedMemberNames.add(element.name);
      });
      for (Element export in library.exports) {
        if (!library.isInternalLibrary &&
            export.getLibrary().isInternalLibrary) {
          // If an element of an internal library is reexported by a platform
          // library, we have to import the reexporting library instead of the
          // internal library, because the internal library is an
          // implementation detail of dart2js.
          reexportingLibraries[export] = library;
        }
      }
    }
    // As of now names of named optionals are not renamed. Therefore add all
    // field names used as named optionals into [fixedMemberNames].
    for (final element in resolvedElements.keys) {
      if (!element.isConstructor()) continue;
      Link<Element> optionalParameters =
          element.computeSignature(compiler).optionalParameters;
      for (final optional in optionalParameters) {
        if (optional.kind != ElementKind.FIELD_PARAMETER) continue;
        fixedMemberNames.add(optional.name);
      }
    }
    // The VM will automatically invoke the call method of objects
    // that are invoked as functions. Make sure to not rename that.
    fixedMemberNames.add('call');
    // TODO(antonm): TypeError.srcType and TypeError.dstType are defined in
    // runtime/lib/error.dart. Overall, all DartVM specific libs should be
    // accounted for.
    fixedMemberNames.add('srcType');
    fixedMemberNames.add('dstType');

    if (useMirrorHelperLibrary && compiler.mirrorsLibrary != null) {
        mirrorRenamer = new MirrorRenamer(compiler, this);
    } else {
      useMirrorHelperLibrary = false;
    }

    /**
     * Tells whether we should output given element. Corelib classes like
     * Object should not be in the resulting code.
     */
    bool shouldOutput(Element element) {
      return (element.kind != ElementKind.VOID
          && isUserLibrary(element.getLibrary())
          && !element.isSynthesized
          && element is !AbstractFieldElement)
          || element.getLibrary() == mirrorHelperLibrary;
    }

    final elementAsts = new Map<Element, ElementAst>();

    parse(element) => element.parseNode(compiler);

    Set<Element> topLevelElements = new Set<Element>();
    Map<ClassElement, Set<Element>> classMembers =
        new Map<ClassElement, Set<Element>>();

    // Build all top level elements to emit and necessary class members.
    var newTypedefElementCallback, newClassElementCallback;

    processElement(element, elementAst) {
      new ReferencedElementCollector(
          compiler,
          element, elementAst.treeElements,
          newTypedefElementCallback, newClassElementCallback).collect();
      elementAsts[element] = elementAst;
    }

    addTopLevel(element, elementAst) {
      if (topLevelElements.contains(element)) return;
      topLevelElements.add(element);
      processElement(element, elementAst);
    }

    addClass(classElement) {
      addTopLevel(classElement,
                  new ElementAst.forClassLike(parse(classElement)));
      classMembers.putIfAbsent(classElement, () => new Set());
    }

    newTypedefElementCallback = (TypedefElement element) {
      if (!shouldOutput(element)) return;
      addTopLevel(element,
                  new ElementAst.forClassLike(parse(element)));
    };
    newClassElementCallback = (ClassElement classElement) {
      if (!shouldOutput(classElement)) return;
      addClass(classElement);
    };

    compiler.resolverWorld.instantiatedClasses.forEach(
        (ClassElement classElement) {
      if (shouldOutput(classElement)) addClass(classElement);
    });
    resolvedElements.forEach((element, treeElements) {
      if (!shouldOutput(element) || treeElements == null) return;
      var elementAst = new ElementAst(parse(element), treeElements);
      if (element.isField()) {
        final list = (element as VariableElement).variables;
        elementAst = elementAsts.putIfAbsent(
            list, () => new VariableListAst(parse(list)));
        (elementAst as VariableListAst).add(element, treeElements);
        element = list;
      }

      if (element.isMember()) {
        ClassElement enclosingClass = element.getEnclosingClass();
        assert(enclosingClass.isClass());
        assert(enclosingClass.isTopLevel());
        assert(shouldOutput(enclosingClass));
        addClass(enclosingClass);
        classMembers[enclosingClass].add(element);
        processElement(element, elementAst);
      } else {
        if (element.isTopLevel()) {
          addTopLevel(element, elementAst);
        }
      }
    });

    // Add synthesized constructors to classes with no resolved constructors,
    // but which originally had any constructor.  That should prevent
    // those classes from being instantiable with default constructor.
    Identifier synthesizedIdentifier = new Identifier(
        new StringToken.fromString(IDENTIFIER_INFO, '', -1));

    NextClassElement:
    for (ClassElement classElement in classMembers.keys) {
      for (Element member in classMembers[classElement]) {
        if (member.isConstructor()) continue NextClassElement;
      }
      if (classElement.constructors.isEmpty) continue NextClassElement;

      // TODO(antonm): check with AAR team if there is better approach.
      // As an idea: provide template as a Dart code---class C { C.name(); }---
      // and then overwrite necessary parts.
      var classNode = classElement.parseNode(compiler);
      SynthesizedConstructorElementX constructor =
          new SynthesizedConstructorElementX(
              classElement.name, null, classElement, false);
      constructor.type = new FunctionType(
          constructor,
          compiler.types.voidType,
          const Link<DartType>(),
          const Link<DartType>(),
          const Link<String>(),
          const Link<DartType>()
          );
      constructor.cachedNode = new FunctionExpression(
          new Send(classNode.name, synthesizedIdentifier),
          new NodeList(new StringToken.fromString(OPEN_PAREN_INFO, '(', -1),
                       const Link<Node>(),
                       new StringToken.fromString(CLOSE_PAREN_INFO, ')', -1)),
          new EmptyStatement(
              new StringToken.fromString(SEMICOLON_INFO, ';', -1)),
          null, Modifiers.EMPTY, null, null);

      if (!constructor.isSynthesized) {
        classMembers[classElement].add(constructor);
      }
      elementAsts[constructor] =
          new ElementAst(constructor.cachedNode, new TreeElementMapping(null));
    }

    // Create all necessary placeholders.
    PlaceholderCollector collector =
        new PlaceholderCollector(compiler, fixedMemberNames, elementAsts);
    // Add synthesizedIdentifier to set of unresolved names to rename it to
    // some unused identifier.
    collector.unresolvedNodes.add(synthesizedIdentifier);
    makePlaceholders(element) {
      bool oldUseHelper = useMirrorHelperLibrary;
      useMirrorHelperLibrary = (useMirrorHelperLibrary
                               && element.getLibrary() != mirrorHelperLibrary);
      collector.collect(element);
      useMirrorHelperLibrary = oldUseHelper;

      if (element.isClass()) {
        classMembers[element].forEach(makePlaceholders);
      }
    }
    topLevelElements.forEach(makePlaceholders);
    // Create renames.
    bool shouldCutDeclarationTypes = forceStripTypes
        || (compiler.enableMinification
            && isSafeToRemoveTypeDeclarations(classMembers));
    renamePlaceholders(
        compiler, collector, renames, imports,
        fixedMemberNames, reexportingLibraries,
        shouldCutDeclarationTypes,
        uniqueGlobalNaming: useMirrorHelperLibrary);

    // Sort elements.
    final sortedTopLevels = sortElements(topLevelElements);
    final sortedClassMembers = new Map<ClassElement, List<Element>>();
    classMembers.forEach((classElement, members) {
      sortedClassMembers[classElement] = sortElements(members);
    });

    if (outputAst) {
      // TODO(antonm): Ideally XML should be a separate backend.
      // TODO(antonm): obey renames and minification, at least as an option.
      StringBuffer sb = new StringBuffer();
      outputElement(element) { sb.write(parse(element).toDebugString()); }

      // Emit XML for AST instead of the program.
      for (final topLevel in sortedTopLevels) {
        if (topLevel.isClass()) {
          // TODO(antonm): add some class info.
          sortedClassMembers[topLevel].forEach(outputElement);
        } else {
          outputElement(topLevel);
        }
      }
      compiler.assembledCode = '<Program>\n$sb</Program>\n';
      return;
    }

    final topLevelNodes = <Node>[];
    for (final element in sortedTopLevels) {
      topLevelNodes.add(elementAsts[element].ast);
      if (element.isClass() && !element.isMixinApplication) {
        final members = <Node>[];
        for (final member in sortedClassMembers[element]) {
          members.add(elementAsts[member].ast);
        }
        memberNodes[elementAsts[element].ast] = members;
      }
    }

    if (useMirrorHelperLibrary) {
      mirrorRenamer.addRenames(renames, topLevelNodes, collector);
    }

    final unparser = new EmitterUnparser(renames);
    emitCode(unparser, imports, topLevelNodes, memberNodes);
    compiler.assembledCode = unparser.result;

    // Output verbose info about size ratio of resulting bundle to all
    // referenced non-platform sources.
    logResultBundleSizeInfo(topLevelElements);
  }

  void logResultBundleSizeInfo(Set<Element> topLevelElements) {
    Iterable<LibraryElement> referencedLibraries =
        compiler.libraries.values.where(isUserLibrary);
    // Sum total size of scripts in each referenced library.
    int nonPlatformSize = 0;
    for (LibraryElement lib in referencedLibraries) {
      for (CompilationUnitElement compilationUnit in lib.compilationUnits) {
        nonPlatformSize += compilationUnit.script.file.length;
      }
    }
    int percentage = compiler.assembledCode.length * 100 ~/ nonPlatformSize;
    log('Total used non-platform files size: ${nonPlatformSize} bytes, '
        'bundle size: ${compiler.assembledCode.length} bytes (${percentage}%)');
  }

  log(String message) => compiler.log('[DartBackend] $message');

  Future onLibraryLoaded(LibraryElement library, Uri uri) {
    if (useMirrorHelperLibrary && library == compiler.mirrorsLibrary) {
      return compiler.scanBuiltinLibrary(
          MirrorRenamer.MIRROR_HELPER_LIBRARY_NAME).
          then((LibraryElement element) {
        mirrorHelperLibrary = element;
        mirrorHelperGetNameFunction = mirrorHelperLibrary.find(
            MirrorRenamer.MIRROR_HELPER_GET_NAME_FUNCTION);
        mirrorHelperSymbolsMap = mirrorHelperLibrary.find(
            MirrorRenamer.MIRROR_HELPER_SYMBOLS_MAP_NAME);
      });
    }
    return new Future.value();
  }

  void registerStaticSend(Element element, Node node) {
    if (useMirrorHelperLibrary) {
      mirrorRenamer.registerStaticSend(element, node);
    }
  }

  void registerMirrorHelperElement(Element element, Node node) {
    if (mirrorHelperLibrary != null
        && element.getLibrary() == mirrorHelperLibrary) {
      mirrorRenamer.registerHelperElement(element, node);
    }
  }

  void registerStaticUse(Element element, Enqueuer enqueuer) {
    if (useMirrorHelperLibrary &&
        element == compiler.mirrorSystemGetNameFunction) {
      enqueuer.addToWorkList(mirrorHelperGetNameFunction);
    }
  }
}

class EmitterUnparser extends Unparser {
  final Map<Node, String> renames;

  EmitterUnparser(this.renames);

  visit(Node node) {
    if (node != null && renames.containsKey(node)) {
      sb.write(renames[node]);
    } else {
      super.visit(node);
    }
  }

  unparseSendReceiver(Send node, {bool spacesNeeded: false}) {
    // TODO(smok): Remove ugly hack for library prefices.
    if (node.receiver != null && renames[node.receiver] == '') return;
    super.unparseSendReceiver(node, spacesNeeded: spacesNeeded);
  }

  unparseFunctionName(Node name) {
    if (name != null && renames.containsKey(name)) {
      sb.write(renames[name]);
    } else {
      super.unparseFunctionName(name);
    }
  }
}


/**
 * Some elements are not recorded by resolver now,
 * for example, typedefs or classes which are only
 * used in signatures, as/is operators or in super clauses
 * (just to name a few).  Retraverse AST to pick those up.
 */
class ReferencedElementCollector extends Visitor {
  final Compiler compiler;
  final Element rootElement;
  final TreeElements treeElements;
  final newTypedefElementCallback;
  final newClassElementCallback;

  ReferencedElementCollector(this.compiler,
                             Element rootElement,
                             this.treeElements,
                             this.newTypedefElementCallback,
                             this.newClassElementCallback)
      : this.rootElement =
          rootElement is VariableElement ? rootElement.variables : rootElement;

  visitNode(Node node) {
    node.visitChildren(this);
  }

  visitTypeAnnotation(TypeAnnotation typeAnnotation) {
    // We call [resolveReturnType] to allow having 'void'.
    final type = compiler.resolveReturnType(rootElement, typeAnnotation);
    Element typeElement = type.element;
    if (typeElement.isTypedef()) newTypedefElementCallback(typeElement);
    if (typeElement.isClass()) newClassElementCallback(typeElement);
    typeAnnotation.visitChildren(this);
  }

  void collect() {
    compiler.withCurrentElement(rootElement, () {
      rootElement.parseNode(compiler).accept(this);
    });
  }
}

Comparator compareBy(f) => (x, y) => f(x).compareTo(f(y));

List sorted(Iterable l, comparison) {
  final result = new List.from(l);
  result.sort(comparison);
  return result;
}

compareElements(e0, e1) {
  int result = compareBy((e) => e.getLibrary().canonicalUri.toString())(e0, e1);
  if (result != 0) return result;
  return compareBy((e) => e.position().charOffset)(e0, e1);
}

List<Element> sortElements(Iterable<Element> elements) =>
    sorted(elements, compareElements);
