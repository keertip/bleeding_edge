/*
 * Copyright (c) 2012, the Dart project authors.
 * 
 * Licensed under the Eclipse Public License v1.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 * 
 * http://www.eclipse.org/legal/epl-v10.html
 * 
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 */
package com.google.dart.engine.internal.element;

import com.google.dart.engine.element.ElementKind;
import com.google.dart.engine.element.ElementVisitor;
import com.google.dart.engine.element.ExportElement;
import com.google.dart.engine.element.LibraryElement;
import com.google.dart.engine.element.NamespaceCombinator;

/**
 * Instances of the class {@code ExportElementImpl} implement an {@link ExportElement}.
 * 
 * @coverage dart.engine.element
 */
public class ExportElementImpl extends ElementImpl implements ExportElement {
  /**
   * The URI that is specified by this directive.
   */
  private String uri;

  /**
   * The library that is exported from this library by this export directive.
   */
  private LibraryElement exportedLibrary;

  /**
   * The combinators that were specified as part of the export directive in the order in which they
   * were specified.
   */
  private NamespaceCombinator[] combinators = NamespaceCombinator.EMPTY_ARRAY;

  /**
   * Initialize a newly created export element.
   */
  public ExportElementImpl() {
    super(null);
  }

  @Override
  public <R> R accept(ElementVisitor<R> visitor) {
    return visitor.visitExportElement(this);
  }

  @Override
  public NamespaceCombinator[] getCombinators() {
    return combinators;
  }

  @Override
  public LibraryElement getExportedLibrary() {
    return exportedLibrary;
  }

  @Override
  public ElementKind getKind() {
    return ElementKind.EXPORT;
  }

  @Override
  public String getUri() {
    return uri;
  }

  /**
   * Set the combinators that were specified as part of the export directive to the given array of
   * combinators.
   * 
   * @param combinators the combinators that were specified as part of the export directive
   */
  public void setCombinators(NamespaceCombinator[] combinators) {
    this.combinators = combinators;
  }

  /**
   * Set the library that is exported from this library by this import directive to the given
   * library.
   * 
   * @param exportedLibrary the library that is exported from this library
   */
  public void setExportedLibrary(LibraryElement exportedLibrary) {
    this.exportedLibrary = exportedLibrary;
  }

  /**
   * Set the URI that is specified by this directive.
   * 
   * @param uri the URI that is specified by this directive.
   */
  public void setUri(String uri) {
    this.uri = uri;
  }

  @Override
  protected void appendTo(StringBuilder builder) {
    builder.append("export ");
    ((LibraryElementImpl) exportedLibrary).appendTo(builder);
  }

  @Override
  protected String getIdentifier() {
    return exportedLibrary.getName();
  }
}
