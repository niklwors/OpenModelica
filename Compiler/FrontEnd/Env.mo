/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Linköping University,
 * Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL).
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Linköping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package Env
" file:        Env.mo
  package:     Env
  description: Environment management

  RCS: $Id$

  An environment is a stack of frames, where each frame contains a
  number of class and variable bindings.
  Each frame consist of:
  - a frame name (corresponding to the class partially instantiated in that frame)
  - a binary tree containing a list of classes
  - a binary tree containing a list of functions (functions are overloaded so serveral
                 function names can exist)
  - a list of unnamed items consisting of import statements

  As an example lets consider the following Modelica code:
  package A
    package B
     import Modelica.SIunits.;
     constant Voltage V=3.3;
     function foo
     end foo;
     model M1
       Real x,y;
     end M1;
     model M2
     end M2;
   end B;
  end A;

  When instantiating M1 we will first create the environment for its surrounding scope
  by a recursive instantiation on A.B giving the environment:
   {
   FRAME(\"A\", {Class:B},{},{},false) ,
   FRAME(\"B\", {Class:M1, Class:M2, Variable:V}, {Type:foo},
     {import Modelica.SIunits.},false)
   }

  Then, the class M1 is instantiated in a new scope/Frame giving the environment:
   {
   FRAME(\"A\", {Class:B},{},{},false) ,
   FRAME(\"B\", {Class:M1, Class:M2, Variable:V}, {Type:foo},
     {Import Modelica.SIunits.},false),
   FRAME(\"M1\", {Variable:x, Variable:y},{},{},false)
   }

  NOTE: The instance hierachy (components and variables) and the class hierachy
  (packages and classes) are combined into the same data structure, enabling a
  uniform lookup mechanism "

// public imports
public import Absyn;
public import ClassInf;
public import DAE;
public import HashTable;
public import SCode;
public import Util;

// protected imports
protected import BaseHashTable;
protected import ComponentReference;
protected import DAEDump;
protected import DAEUtil;
protected import Debug;
protected import Dump;
protected import Error;
protected import ExpressionDump;
protected import Flags;
protected import List;
protected import Print;
protected import Types;
protected import SCodeDump;
protected import FEnv;

public type Ident = String " An identifier is just a string " ;
public type Env = list<Frame> "an environment is a list of frames";
public type StructuralParameters = tuple<HashTable.HashTable,list<list<DAE.ComponentRef>>>;
public type Import = Absyn.Import;
public type CSetsType = list<tuple<list<DAE.ComponentRef>,DAE.ComponentRef>>;

public constant Integer tmpTickIndex = 10;
public constant Integer extendsTickIndex = 11;

public constant Env emptyEnv = {};
public constant String BASE_CLASS_SUFFIX = "$base";
public constant ImportTable emptyImportTable = IMPORT_TABLE(false, {}, {});
public constant ExtendsTable emptyExtendsTable = EXTENDS_TABLE({}, {}, NONE());

public constant String forScopeName="$for loop scope$" "a unique scope used in for equations";
public constant String forIterScopeName="$foriter loop scope$" "a unique scope used in for iterators";
public constant String parForScopeName="$pafor loop scope$" "a unique scope used in parfor loops";
public constant String parForIterScopeName="$parforiter loop scope$" "a unique scope used in parfor iterators";
public constant String matchScopeName="$match scope$" "a unique scope used by match expressions";
public constant String caseScopeName="$case scope$" "a unique scope used by match expressions; to be removed when local decls are deprecated";
public constant list<String> implicitScopeNames={forScopeName,forIterScopeName,parForScopeName,parForIterScopeName,matchScopeName,caseScopeName};

public uniontype Cache
  record CACHE
    Option<array<EnvCache>> envCache "The cache contains of environments from which classes can be found";
    Option<Env> initialEnv "and the initial environment";
    array<DAE.FunctionTree> functions "set of Option<DAE.Function>; NONE() means instantiation started; SOME() means it's finished";
    StructuralParameters evaluatedParams "ht of prefixed crefs and a stack of evaluated but not yet prefix crefs";
    Absyn.Path modelName "name of the model being instantiated";
  end CACHE;
end Cache;

public uniontype EnvCache
  record ENVCACHE "Cache for environments. The cache consists of a tree of environments from which lookup can be performed."
    CacheTree envTree;
  end ENVCACHE;
end EnvCache;

public uniontype CacheTree
  record CACHETREE
    Ident  name;
    Env env;
    list<CacheTree> children;
  end CACHETREE;
end CacheTree;

public uniontype ScopeType
  record FUNCTION_SCOPE end FUNCTION_SCOPE;
  record CLASS_SCOPE end CLASS_SCOPE;
  record PARALLEL_SCOPE end PARALLEL_SCOPE;
end ScopeType;

public uniontype ImportTable
  record IMPORT_TABLE
    // Imports should not be inherited, but removing them from the environment
    // when doing lookup through extends causes problems for the lookup later
    // on, because for example components may have types that depends on
    // imports.  The hidden flag allows the lookup to 'hide' the imports
    // temporarily, without actually removing them.
    Boolean hidden "If true means that the imports are hidden.";
    list<Import> qualifiedImports;
    list<Import> unqualifiedImports;
  end IMPORT_TABLE;
end ImportTable;

public uniontype Redeclaration
  "This uniontype stores a redeclare modifier (which might be derived from an
  element redeclare). The RAW_MODIFIER stores a 'raw' modifier, i.e. the raw
  element stored in the SCode representation. These are processed when they are
  used, i.e. when replacements are done, and converted into PROCESSED_MODIFIERs
  which are environment items ready to be replaced in the environment."

  record RAW_MODIFIER
    SCode.Element modifier;
  end RAW_MODIFIER;

  record PROCESSED_MODIFIER
    Item modifier;
  end PROCESSED_MODIFIER;
end Redeclaration;

public uniontype Extends
  record EXTENDS
    Absyn.Path baseClass;
    list<Redeclaration> redeclareModifiers;
    Integer index;
    Absyn.Info info;
  end EXTENDS;
end Extends;

public uniontype ExtendsTable
  record EXTENDS_TABLE
    list<Extends> baseClasses;
    list<SCode.Element> redeclaredElements;
    Option<SCode.Element> classExtendsInfo;
  end EXTENDS_TABLE;
end ExtendsTable;

public uniontype FrameType
  record NORMAL_SCOPE end NORMAL_SCOPE;
  record ENCAPSULATED_SCOPE end ENCAPSULATED_SCOPE;
  record IMPLICIT_SCOPE "This scope contains one or more iterators; they are made unique by the following index (plus their name)" Integer iterIndex; end IMPLICIT_SCOPE;
end FrameType;

public
uniontype Frame
  record FRAME
    Option<Ident>       name               "Optional class name";
    Option<ScopeType>   scopeType          "Optional scope type";
    FrameType           frameType          "Normal, Encapsulated, Implicit";
    AvlTree             clsAndVars         "List of uniquely named classes and variables";
    AvlTree             types              "List of types, which DOES NOT need to be uniquely named, eg. size may have several types";
    CSetsType           connectionSet      "Current connection set crefs";
    list<SCode.Element> defineUnits        "List of units defined in the frame";
    ExtendsTable        extendsTable       "The Extends table containing all extends with their redeclares";
    ImportTable         importTable        "The Import table";
    Option<Util.StatefulBoolean> isUsed    "Used by FDependency.";
  end FRAME;
end Frame;

public uniontype ClassType
  record USERDEFINED end USERDEFINED;
  record BUILTIN end BUILTIN;
  record CLASS_EXTENDS end CLASS_EXTENDS;
  record BASIC_TYPE end BASIC_TYPE;
end ClassType;

public uniontype InstStatus
"Used to distinguish between different phases of the instantiation of a component
A component is first added to environment untyped. It can thereafter be instantiated to get its type
and finally instantiated to produce the DAE. These three states are indicated by this datatype."

  record VAR_UNTYPED "Untyped variables, initially added to env"
  end VAR_UNTYPED;

  record VAR_TYPED "Typed variables, when instantiation to get type has been performed"
  end VAR_TYPED;

  record VAR_DAE "Typed variables that also have been instantiated to generate dae. Required to distinguish
                  between typed variables without DAE to know when to skip multiply declared dae elements"
  end VAR_DAE;
end InstStatus;

public
uniontype Item
  record VAR
    DAE.Var instantiated "instantiated component" ;
    SCode.Element var "declaration";
    DAE.Mod mod "modification";
    InstStatus instStatus "if it untyped, typed or fully instantiated (dae)";
    Env env "The environment of the instantiated component. Contains e.g. all sub components";
    Option<Util.StatefulBoolean> isUsed "Used by FDependency.";
  end VAR;

  record CLASS
    SCode.Element cls;
    Env env;
    ClassType classType;
  end CLASS;

  record TYPE
    list<DAE.Type> tys "list since several types with the same name can exist in the same scope (overloading)" ;
  end TYPE;

  record ALIAS
    "An alias for another Item, see comment in SCodeFlattenRedeclare package."
    String name;
    Option<Absyn.Path> path;
    Absyn.Info info;
  end ALIAS;

  record REDECLARED_ITEM
    Item item;
    Env declaredEnv;
  end REDECLARED_ITEM;

end Item;

public function emptyCache
"returns an empty cache"
  output Cache cache;
 protected
  Option<array<EnvCache>> envCache;
  array<EnvCache> arr;
  array<DAE.FunctionTree> instFuncs;
  StructuralParameters ht;
algorithm
  //print("EMPTYCACHE\n");
  arr := arrayCreate(1, ENVCACHE(CACHETREE("$global",emptyEnv,{})));
  envCache := Util.if_(Flags.getConfigBool(Flags.ENV_CACHE),SOME(arr),NONE());
  instFuncs := arrayCreate(1, DAEUtil.emptyFuncTree);
  ht := (HashTable.emptyHashTableSized(BaseHashTable.lowBucketSize),{});
  cache := CACHE(envCache,NONE(),instFuncs,ht,Absyn.IDENT("##UNDEFINED##"));
end emptyCache;

// functions for dealing with the environment
public function newEnvironment
"Returns a new environment with only one frame."
  input Option<SCode.Ident> inName;
  output Env outEnv;
protected
  Frame new_frame;
algorithm
  new_frame := newFrame(inName, NONE(), NORMAL_SCOPE());
  outEnv := {new_frame};
end newEnvironment;

public function newFrame
"function: newFrame
  This function creates a new frame, which
  includes setting up the hashtable for the
  frame."
  input Option<Ident> inName;
  input Option<ScopeType> inScopeType;
  input FrameType inFrameType;
  output Frame outFrame;
protected
  AvlTree tys;
  AvlTree clsAndVars;
  ExtendsTable exts;
  ImportTable imps;
  Util.StatefulBoolean is_used;
algorithm
  clsAndVars := avlTreeNew();
  tys        := avlTreeNew();
  exts       := newExtendsTable();
  imps       := newImportTable();
  is_used    := Util.makeStatefulBoolean(false);
  outFrame   := FRAME(inName,inScopeType,inFrameType,clsAndVars,tys,{},{},exts,imps,SOME(is_used));
end newFrame;

public function newImportTable
"Creates a new import table."
  output ImportTable outImports;
algorithm
  outImports := emptyImportTable;
end newImportTable;

public function newExtendsTable
"Creates a new extends table."
  output ExtendsTable outExtends;
algorithm
  outExtends := emptyExtendsTable;
end newExtendsTable;

public function isTyped
"author BZ 2008-06
  This function checks wheter an InstStatus is typed or not.
  Currently used by Inst.updateComponentsInEnv."
  input InstStatus is;
  output Boolean b;
algorithm
  b := matchcontinue(is)
    case(VAR_UNTYPED()) then false;
    case(_) then true;
  end matchcontinue;
end isTyped;

public function openScope
"function: openScope
  Opening a new scope in the environment means adding a new frame on
  top of the stack of frames. If the scope is not the top scope a classname
  of the scope should be provided such that a name for the scope can be
  derived, see nameScope."
  input Env inEnv;
  input SCode.Encapsulated encapsulatedPrefix;
  input Option<Ident> inIdent;
  input Option<ScopeType> inScopeType;
  output Env outEnv;
protected
  Frame f;
  FrameType frameType;
algorithm
  frameType := getFrameType(encapsulatedPrefix);
  f := newFrame(inIdent, inScopeType, frameType);
  outEnv := f :: inEnv;
end openScope;

protected function getFrameType
  "Returns a new FrameType given if the frame should be encapsulated or not."
  input SCode.Encapsulated encapsulatedPrefix;
  output FrameType outType;
algorithm
  outType := match(encapsulatedPrefix)
    case SCode.ENCAPSULATED() then ENCAPSULATED_SCOPE();
    else then NORMAL_SCOPE();
  end match;
end getFrameType;

public function inForLoopScope "returns true if environment has a frame that is a for loop"
  input Env env;
  output Boolean res;
algorithm
  res := matchcontinue(env)
    local String name;

    case(FRAME(name = SOME(name))::_)
      equation
        true = stringEq(name, forScopeName);
      then true;

    case(_) then false;

  end matchcontinue;
end inForLoopScope;

public function inForOrParforIterLoopScope "returns true if environment has a frame that is a for iterator 'loop'"
  input Env env;
  output Boolean res;
algorithm
  res := matchcontinue(env)
    local String name;

    case(FRAME(name = SOME(name))::_)
      equation
        true = stringEq(name, forIterScopeName);
      then true;

    case(FRAME(name = SOME(name))::_)
      equation
        true = stringEq(name, parForIterScopeName);
      then true;

    case(_) then false;
  end matchcontinue;
end inForOrParforIterLoopScope;

public function stripForLoopScope "strips for loop scopes"
  input Env inEnv;
  output Env outEnv;
algorithm
  outEnv := matchcontinue(inEnv)
    local String name; Env env;
    case(FRAME(name = SOME(name))::env)
      equation
        true = stringEq(name, forScopeName);
        env = stripForLoopScope(env);
      then env;
    case(env) then env;
  end matchcontinue;
end stripForLoopScope;

public function getScopeName "function: getScopeName
 Returns the name of a scope, if no name exist, the function fails."
  input Env inEnv;
  output Ident name;
algorithm
  name:= match (inEnv)
    case ((FRAME(name = SOME(name))::_)) then (name);
  end match;
end getScopeName;

public function getScopeNames "function: getScopeName
 Returns the name of a scope, if no name exist, the function fails."
  input Env inEnv;
  output list<Ident> names;
algorithm
  names := matchcontinue (inEnv)
    local String name;

    // empty list
    case ({}) then {};
    // frame with a name
    case ((FRAME(name = SOME(name))::inEnv))
      equation
        names = getScopeNames(inEnv);
      then
        name::names;
    // frame without a name
    case ((FRAME(name = NONE())::inEnv))
      equation
        names = getScopeNames(inEnv);
      then
        "-NONAME-"::names;
  end matchcontinue;
end getScopeNames;

public function updateEnvClasses
"updates the classes of the top frame on the env passed
 as argument to the environment passed as second argument"
  input Env inEnv;
  input Env inClassEnv;
  output Env outEnv;
algorithm
  outEnv := match(inEnv, inClassEnv)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs;

    case(FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs, _)
      equation
        clsAndVars = updateEnvClassesInTree(clsAndVars, inClassEnv);
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

  end match;
end updateEnvClasses;

protected function updateEnvClassesInTree
"Help function to updateEnvClasses"
  input AvlTree tree;
  input Env classEnv;
  output AvlTree outTree;
algorithm
  outTree := matchcontinue(tree,classEnv)
    local
      SCode.Element cl;
      Option<AvlTree> l,r;
      AvlKey k;
      Env env;
      Item item;
      Integer h;
      ClassType ct;

   // Classes
   case(AVLTREENODE(SOME(AVLTREEVALUE(k,CLASS(cl,env,ct))),h,l,r),_)
     equation
      l = updateEnvClassesInTreeOpt(l,classEnv);
      r = updateEnvClassesInTreeOpt(r,classEnv);
     then
       AVLTREENODE(SOME(AVLTREEVALUE(k,CLASS(cl,classEnv,ct))),h,l,r);

   // Other items
   case(AVLTREENODE(SOME(AVLTREEVALUE(k,item)),h,l,r),_)
     equation
      l = updateEnvClassesInTreeOpt(l,classEnv);
      r = updateEnvClassesInTreeOpt(r,classEnv);
     then
       AVLTREENODE(SOME(AVLTREEVALUE(k,item)),h,l,r);

   // nothing
   case(AVLTREENODE(NONE(),h,l,r),_)
     equation
      l = updateEnvClassesInTreeOpt(l,classEnv);
      r = updateEnvClassesInTreeOpt(r,classEnv);
     then
       AVLTREENODE(NONE(),h,l,r);

  end matchcontinue;
end updateEnvClassesInTree;

protected function updateEnvClassesInTreeOpt "Help function to updateEnvClassesInTree"
  input Option<AvlTree> tree;
  input Env classEnv;
  output Option<AvlTree> outTree;
algorithm
  outTree := match(tree,classEnv)
    local AvlTree t;
    case(NONE(),_) then NONE();
    case(SOME(t),_)
      equation
        t = updateEnvClassesInTree(t,classEnv);
      then
        SOME(t);
  end match;
end updateEnvClassesInTreeOpt;

public function extendFrameC
"function: extendFrameC
  This function adds a class definition to the environment."
  input Env inEnv;
  input SCode.Element inClass;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inClass)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs, env;
      SCode.Element c;
      Ident n;
      ClassType ct;
      SCode.ClassDef cdef;

    case (env as FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs, c as SCode.CLASS(name = n))
      equation
        cdef = SCode.getClassDef(c);
        ct = getClassType(cdef);
        clsAndVars = avlTreeAdd(clsAndVars,n,CLASS(c,env,ct));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

    case (_,_)
      equation
        n = SCode.elementName(inClass);
        print("- Env.extendFrameC failed on element: " +& n +& "\n");
      then
        fail();
  end matchcontinue;
end extendFrameC;

public function extendFrameCBuiltin
"function: extendFrameCBuiltin
  This function adds a builtin class definition to the environment."
  input Env inEnv;
  input SCode.Element inClass;
  output Env outEnv;
algorithm
  outEnv := extendFrameCClassType(inEnv,inClass,BUILTIN());
end extendFrameCBuiltin;

public function extendFrameCClassType
"function: extendFrameCClassType
  This function adds a class definition to the environment with the given class type."
  input Env inEnv;
  input SCode.Element inClass;
  input ClassType inClassType;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inClass,inClassType)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs, env;
      SCode.Element c;
      Ident n;
      ClassType ct;
      SCode.ClassDef cdef;

    case (env as FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs, c as SCode.CLASS(name = n), _)
      equation
        clsAndVars = avlTreeAdd(clsAndVars,n,CLASS(c,env,inClassType));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

    case (_,_,_)
      equation
        n = SCode.elementName(inClass);
        print("- Env.extendFrameCClassType failed on element: " +& n +& "\n");
      then
        fail();
  end matchcontinue;
end extendFrameCClassType;


public function updateFrameC "function: updateFrameC
  This function updates a component already added to the environment, but
  that prior to the update did not have any binding. I.e this function is
  called in the second stage of instantiation with declare before use."
  input Env inEnv;
  input SCode.Element inClass;
  input Env inClassEnv;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inClass,inClassEnv)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs, env, frames, classEnv, oldCE;
      SCode.Element e, oldE;
      Ident n;
      ClassType oldCT,clsTy;
      SCode.ClassDef cdef;

    /*
    case (env, e, classEnv)
      equation
        // Debug.fprintln(Flags.INST_TRACE, "Updating class: " +& valueStr(CLASS(e, classEnv)) +& "\nIn env/cenv:" +& printEnvPathStr(env) +& "/" +& printEnvPathStr(classEnv));
      then
        fail();*/

    // empty case

    case ({}, _, _) then {};

    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs,
          e as SCode.CLASS(name = n), classEnv)
      equation
        cdef = SCode.getClassDef(e);
        clsTy = getClassType(cdef);

        CLASS(oldE,oldCE,oldCT) = avlTreeGet(clsAndVars, n);

        clsAndVars = avlTreeAdd(clsAndVars, n, CLASS(e, classEnv, clsTy));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

    // Also check frames above, e.g. when variable is in base class
    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs, e, classEnv)
      equation
        frames = updateFrameC(fs, e, classEnv);
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::frames;

    case (_, e, classEnv)
      equation
        print("- Env.updateFrameC failed on class: " +& SCodeDump.unparseElementStr(e) +& "\n");
      then
        fail();

  end matchcontinue;
end updateFrameC;

public function extendFrameClasses
"function: extendFrameClasses
  Adds all builtin clases in a Program to the environment."
  input Env inEnv;
  input SCode.Program inProgram;
  output Env outEnv;
algorithm
  outEnv := match (inEnv, inProgram)
    local
      Env env;
      SCode.Element c;
      list<SCode.Element> cs;

    case (env, {}) then env;

    case (env, c :: cs)
      equation
        env = extendFrameCBuiltin(env, c);
        env = extendFrameClasses(env, cs);
      then
        env;

  end match;
end extendFrameClasses;

public function getClassType
  "Returns a class's type."
  input SCode.ClassDef inClassDef;
  output ClassType outType;
algorithm
  outType := match(inClassDef)
    // A builtin class.
    case (SCode.PARTS(externalDecl = SOME(SCode.EXTERNALDECL(
        lang = SOME("builtin")))))
      then BUILTIN();
    // A user-defined class (i.e. not builtin).
    else then USERDEFINED();
  end match;
end getClassType;

public function removeComponentsFromFrameV
"function: removeComponentsFromFrameV
  This function removes all components from frame."
  input Env inEnv;
  output Env outEnv;
algorithm
  outEnv := match (inEnv)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs;

    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs)
      equation
        // make an empty component env!
        clsAndVars = avlTreeNew();
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

  end match;
end removeComponentsFromFrameV;

public function extendFrameV "function: extendFrameV
  This function adds a component to the environment."
  input Env inEnv;
  input DAE.Var inVar;
  input SCode.Element inVarEl;
  input DAE.Mod inMod;
  input InstStatus instStatus;
  input Env inCompEnv;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inVar,inVarEl,inMod,instStatus,inCompEnv)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars, tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      InstStatus i;
      DAE.Var v;
      Ident n;
      SCode.Element c;
      Env fs,coenv,remember;
      DAE.Mod m;

    // Environment of component
    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs, v as DAE.TYPES_VAR(name = n),c,m,i,coenv)
      equation
        clsAndVars = avlTreeAdd(clsAndVars, n, VAR(v,c,m,i,coenv,iu));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

    // Variable already added, perhaps from baseclass
    case (FRAME(clsAndVars  = clsAndVars)::fs,v as DAE.TYPES_VAR(name = n),c,m,i,coenv)
      equation
        _ = avlTreeGet(clsAndVars, n);
      then
        inEnv;
  end matchcontinue;
end extendFrameV;

public function updateFrameV "function: updateFrameV
  This function updates a component already added to the environment, but
  that prior to the update did not have any binding. I.e this function is
  called in the second stage of instantiation with declare before use."
  input Env inEnv;
  input DAE.Var inVar;
  input InstStatus instStatus;
  input Env inCompEnv;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inVar,instStatus,inCompEnv)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys,clsAndVars2;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu,iuf;
      InstStatus i;
      Env fs,coenv,frames;
      DAE.Var v;
      Ident n;
      AvlValue var;
      SCode.Element c;
      DAE.Mod m;

    // fully instantiated env of component
    case ({},_,i,_) then {};

    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iuf)::fs, v as DAE.TYPES_VAR(name = n), i, coenv)
      equation
        (var as VAR(_,c,m,_,_,iu)) = avlTreeGet(clsAndVars, n);
        // Debug.fprintln(Flags.INST_TRACE, "Updating variable: " +& valueStr(VAR(v,c,i,env)) +& "\n In current env:" +& printEnvPathStr(inEnv1));
        // Debug.fprintln(Flags.INST_TRACE, "Previous variable: " +& valueStr(var) +& "\nIn current env:" +& printEnvPathStr(inEnv1));
        clsAndVars = avlTreeAdd(clsAndVars, n, VAR(v,c,m,i,coenv,iu));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iuf)::fs;

    // Also check frames above, e.g. when variable is in base class
    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iuf)::fs,v as DAE.TYPES_VAR(name = n), i, coenv)
      equation
        frames = updateFrameV(fs, v, i, coenv);
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iuf)::frames;

    case (_,v as DAE.TYPES_VAR(name = n),_,_)
      equation
        print("- Env.updateFrameV failed on variable: " +&
              n +& "\n" +& Types.printVarStr(v) +& "\n");
      then
        fail();
  end matchcontinue;
end updateFrameV;

public function extendFrameT "function: extendFrameT
  This function adds a type to the environment.  Types in the
  environment are used for looking up constants etc. inside class
  definitions, such as packages.  For each type in the environment,
  there is a class definition with the same name in the
  environment."
  input Env inEnv;
  input Ident inIdent;
  input DAE.Type inType;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inIdent,inType)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs;
      list<DAE.Type> tps;
      Ident n;
      DAE.Type t;

    // Other types with that name already exist, add this type as well
    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs,n,t)
      equation
        TYPE(tps) = avlTreeGet(tys, n);
        tys = avlTreeReplace(tys, n, TYPE(t::tps));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;

    // No other types exists
    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs,n,t)
      equation
        failure(TYPE(_) = avlTreeGet(tys, n));
        tys = avlTreeAdd(tys, n, TYPE({t}));
      then
        FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu)::fs;
  end matchcontinue;
end extendFrameT;

public function extendFrameI
"function: extendFrameI
  Adds an import statement to the environment."
  input Env inEnv;
  input SCode.Element inImport;
  output Env outEnv;
algorithm
  outEnv := matchcontinue (inEnv,inImport)
    local Env env;
    case (_, _)
      equation
        env = FEnv.extendEnvWithImport(inImport, inEnv);
      then
        env;
  end matchcontinue;
end extendFrameI;

public function extendFrameDefunit
"Adds a defineunit to the environment."
  input Env inEnv;
  input SCode.Element defunit;
  output Env outEnv;
algorithm
  outEnv := match (inEnv,defunit)
    local
      Option<Ident> id;
      Option<ScopeType> st;
      FrameType ft;
      AvlTree clsAndVars,tys;
      CSetsType crs;
      list<SCode.Element> du;
      ExtendsTable et;
      ImportTable it;
      Option<Util.StatefulBoolean> iu;
      Env fs;

    case (FRAME(id,st,ft,clsAndVars,tys,crs,du,et,it,iu) :: fs, _)
    then FRAME(id,st,ft,clsAndVars,tys,crs,defunit::du,et,it,iu) :: fs;
  end match;
end extendFrameDefunit;

public function extendFrameForIterator
  "Adds a for loop iterator to the environment."
  input Env env;
  input String name;
  input DAE.Type ty;
  input DAE.Binding binding;
  input SCode.Variability variability;
  input Option<DAE.Const> constOfForIteratorRange;
  output Env outEnv;
algorithm
  outEnv := match(env, name, ty, binding, variability, constOfForIteratorRange)
    local
      Env new_env;

    case (_, _, _, _,_,_)
      equation
        new_env = extendFrameV(
          env,
          DAE.TYPES_VAR(
            name,
            DAE.ATTR(SCode.POTENTIAL(), SCode.NON_PARALLEL(), variability, Absyn.BIDIR(), Absyn.NOT_INNER_OUTER(), SCode.PUBLIC()),
            ty,
            binding,
            constOfForIteratorRange),
          SCode.COMPONENT(
            name,
            SCode.defaultPrefixes,
            SCode.ATTR({}, SCode.POTENTIAL(), SCode.NON_PARALLEL(), SCode.CONST(), Absyn.BIDIR()),
            Absyn.TPATH(Absyn.IDENT(""), NONE()), SCode.NOMOD(),
            NONE(), NONE(), Absyn.dummyInfo),
          DAE.NOMOD(),
          VAR_UNTYPED(),
          {});
      then new_env;

  end match;
end extendFrameForIterator;

public function topFrame "function: topFrame
  Returns the top frame."
  input Env inEnv;
  output Frame outFrame;
algorithm
  outFrame := match (inEnv)
    local
      Frame fr,elt;
      Env lst;
    case ({fr}) then fr;
    case ((elt :: (lst as (_ :: _))))
      equation
        fr = topFrame(lst);
      then
        fr;
  end match;
end topFrame;

public function getClassName
  input Env inEnv;
  output Ident name;
algorithm
   name := match (inEnv)
     local Ident n;
     case FRAME(name = SOME(n))::_ then n;
  end match;
end getClassName;

public function getEnvName
  "Returns the FQ name of the environment, see also getEnvPath"
  input Env inEnv;
  output Absyn.Path outPath;
protected
  Ident id;
  Env rest;
algorithm
  FRAME(name = SOME(id)) :: rest := inEnv;
  outPath := getEnvName2(rest, Absyn.IDENT(id));
end getEnvName;

public function getEnvName2
  input Env inEnv;
  input Absyn.Path inPath;
  output Absyn.Path outPath;
algorithm
  outPath := match(inEnv, inPath)
    local
      Ident id;
      Env rest;

    case (FRAME(name = SOME(id)) :: rest, _)
      then getEnvName2(rest, Absyn.QUALIFIED(id, inPath));

    else inPath;
  end match;
end getEnvName2;

public function getEnvPath "function: getEnvPath
  This function returns all partially instantiated parents as an Absyn.Path
  option I.e. it collects all identifiers of each frame until it reaches
  the topmost unnamed frame. If the environment is only the topmost frame,
  NONE() is returned."
  input Env inEnv;
  output Option<Absyn.Path> outEnvPath;
algorithm
  outEnvPath := matchcontinue(inEnv)
    local
      Absyn.Path path;

    case _
      equation
        path = getEnvName(inEnv);
      then
        SOME(path);

    else NONE();
  end matchcontinue;
end getEnvPath;

public function getEnvPathNoImplicitScope "function: getEnvPath
  This function returns all partially instantiated parents as an Absyn.Path
  option I.e. it collects all identifiers of each frame until it reaches
  the topmost unnamed frame. If the environment is only the topmost frame,
  NONE() is returned."
  input Env inEnv;
  output Option<Absyn.Path> outAbsynPathOption;
algorithm
  outAbsynPathOption := matchcontinue (inEnv)
    local
      Ident id;
      Absyn.Path path,path_1;
      Env rest;
    case ((FRAME(name = SOME(id)) :: rest))
      equation
        true = listMember(id,implicitScopeNames);
      then getEnvPathNoImplicitScope(rest);
    case ((FRAME(name = SOME(id)) :: rest))
      equation
        false = listMember(id,implicitScopeNames);
        SOME(path) = getEnvPathNoImplicitScope(rest);
        path_1 = Absyn.joinPaths(path, Absyn.IDENT(id));
      then
        SOME(path_1);
    case (FRAME(name = SOME(id))::rest)
      equation
        false = listMember(id,implicitScopeNames);
        NONE() = getEnvPathNoImplicitScope(rest);
      then SOME(Absyn.IDENT(id));
    case (_) then NONE();
  end matchcontinue;
end getEnvPathNoImplicitScope;

public function joinEnvPath "function: joinEnvPath
  Used to join an Env with an Absyn.Path (probably an IDENT)"
  input Env inEnv;
  input Absyn.Path inPath;
  output Absyn.Path outPath;
algorithm
  outPath := matchcontinue(inEnv,inPath)
    local
      Absyn.Path envPath;
    case (_,_)
      equation
        SOME(envPath) = getEnvPath(inEnv);
        envPath = Absyn.joinPaths(envPath,inPath);
      then envPath;
    case (_,_)
      equation
        NONE() = getEnvPath(inEnv);
      then inPath;
  end matchcontinue;
end joinEnvPath;

public function getEnvNameStr
  "Returns the FQ name of the environment, see also getEnvPath"
  input Env inEnv;
  output String outString;
algorithm
  outString := matchcontinue(inEnv)
    case (_)
      then
        Absyn.pathString(getEnvName(inEnv));
    else ".";
  end matchcontinue;
end getEnvNameStr;

public function printEnvPathStr "function: printEnvPathStr
 Retrive the environment path as a string, see getEnvPath."
  input Env inEnv;
  output String outString;
algorithm
  outString := matchcontinue (inEnv)
    local
      Absyn.Path path;
      Ident pathstr;
      Env env;
    case (env)
      equation
        SOME(path) = getEnvPath(env);
        pathstr = Absyn.pathString(path);
      then
        pathstr;
    case (env) then "<global scope>";
  end matchcontinue;
end printEnvPathStr;

public function printEnvPath "function: printEnvPath
  Print the environment path to the Print buffer.
  See also getEnvPath"
  input Env inEnv;
algorithm
  _ := matchcontinue (inEnv)
    local
      Absyn.Path path;
      Ident pathstr;
      Env env;
    case (env)
      equation
        SOME(path) = getEnvPath(env);
        pathstr = Absyn.pathString(path);
        Print.printBuf(pathstr);
      then
        ();
    case (env)
      equation
        Print.printBuf("TOPENV");
      then
        ();
  end matchcontinue;
end printEnvPath;

public function printEnvStr "function: printEnvStr
  Print the environment as a string."
  input Env inEnv;
  output String outString;
algorithm
  outString := match (inEnv)
    local
      Ident s1,s2,res;
      Frame fr;
      Env frs;
    case {} then "Empty env\n";
    case (fr :: frs)
      equation
        s1 = printFrameStr(fr);
        s2 = printEnvStr(frs);
        res = stringAppend(s1, s2);
      then
        res;
  end match;
end printEnvStr;

public function printEnv "function: printEnv
  Print the environment to the Print buffer."
  input Env e;
  Ident s;
algorithm
  s := printEnvStr(e);
  Print.printBuf(s);
end printEnv;

public function printEnvConnectionCrefs "prints the connection crefs of the top frame"
  input Env env;
algorithm
  _ := matchcontinue(env)
    local
      list<DAE.ComponentRef> crs;
      CSetsType clst;

    case(env as (FRAME(connectionSet = clst)::_))
      equation
        crs = List.flatten(List.map(clst, Util.tuple21));
        print(printEnvPathStr(env));print(" :   ");
        print(stringDelimitList(List.map(crs,ComponentReference.printComponentRefStr),", "));
        print("\n");
      then
        ();
  end matchcontinue;
end printEnvConnectionCrefs;

protected function printFrameStr "function: printFrameStr
  Print a Frame to a string."
  input Frame inFrame;
  output String outString;
algorithm
  outString := match (inFrame)
    local
      Ident s1,s2,s3,frmTyStr,res,sid;
      Option<Ident> optName;
      AvlTree httypes;
      AvlTree ht;
      list<AvlValue> imps;
      CSetsType crs;
      FrameType frameType;

    case FRAME(name = optName,
               clsAndVars = ht,
               types = httypes,
               connectionSet = crs,
               frameType = frameType)
      equation
        sid = Util.getOptionOrDefault(optName, "unnamed");
        s1 = printAvlTreeStr(ht);
        s2 = printAvlTreeStr(httypes);
        frmTyStr = printFrameTypeStr(frameType);
        res = stringAppendList(
          "FRAME: " :: sid :: " (enc=" :: frmTyStr ::
          ") \nClasses and Vars:\n=============\n" ::
          s1 :: "\nTypes:\n======\n" :: s2 :: "\n" :: {});
      then
        res;
  end match;
end printFrameStr;

protected function printFrameVarsStr "function: printFrameVarsStr
  Print only the variables in a Frame to a string."
  input Frame inFrame;
  output String outString;
algorithm
  outString := matchcontinue (inFrame)
    local
      Ident s1,frmTyStr,res,sid;
      AvlTree httypes;
      AvlTree ht;
      list<AvlValue> imps;
      CSetsType crs;
      FrameType frameType;
      Option<Ident> optName;

    case FRAME(name = optName,
               frameType = frameType,
               clsAndVars = ht,
               types = httypes,
               connectionSet = crs)
      equation
        sid = Util.stringOption(optName);
        s1 = printAvlTreeStr(ht);
        frmTyStr = printFrameTypeStr(frameType);
        res = stringAppendList({"FRAME: ",sid," (frmTy=",frmTyStr,
                                ") \nclasses and vars:\n=============\n",
                                s1,"\n\n\n"});
      then
        res;

    case _ then "";

  end matchcontinue;
end printFrameVarsStr;

protected function printFrameTypeStr
  input FrameType inFrame;
  output String outString;
algorithm
  outString := match(inFrame)
    case NORMAL_SCOPE() then "Normal";
    case ENCAPSULATED_SCOPE() then "Encapsulated";
    case IMPLICIT_SCOPE(iterIndex=_) then "Implicit";
  end match;
end printFrameTypeStr;

protected function printImportsStr "function: printImportsStr
  Print import statements to a string."
  input list<Item> inItemLst;
  output String outString;
algorithm
  outString:=
  matchcontinue (inItemLst)
    local
      Ident s1,s2,res;
      AvlValue e;
      list<AvlValue> rst;
    case {} then "";
    case {e}
      equation
        s1 = printFrameElementStr(("",e));
      then
        s1;
    case ((e :: rst))
      equation
        s1 = printFrameElementStr(("",e));
        s2 = printImportsStr(rst);
        res = stringAppendList({s1,", ",s2});
      then
        res;
  end matchcontinue;
end printImportsStr;

protected function printFrameElementStr "function: printFrameElementStr
  Print frame element to a string"
  input tuple<Ident, Item> inTplIdentItem;
  output String outString;
algorithm
  outString := match (inTplIdentItem)
    local
      Ident s,elt_str,tp_str,var_str,frame_str,bind_str,res,n,lenstr;
      DAE.Var tv;
      SCode.Variability var;
      DAE.Type tp;
      DAE.Binding bind,bnd;
      SCode.Element elt;
      InstStatus i;
      Frame compframe;
      Env env;
      Integer len;
      list<DAE.Type> lst;
      Absyn.Import imp;

    case ((n,VAR(instantiated = (tv as DAE.TYPES_VAR(attributes = DAE.ATTR(variability = var),ty = tp,binding = bind)),var = elt,instStatus = i,env = (compframe :: _))))
      equation
        s = SCodeDump.variabilityString(var);
        elt_str = SCodeDump.printElementStr(elt);
        tp_str = Types.unparseType(tp);
        var_str = Types.unparseVar(tv);
        frame_str = printFrameVarsStr(compframe);
        bind_str = Types.printBindingStr(bind);
        res = stringAppendList(
          {"v:",n," ",s,"(",elt_str,") [",tp_str,"] {",var_str,
          "}, binding:",bind_str});
      then
        res;

    case ((n,VAR(instantiated = (tv as DAE.TYPES_VAR(attributes = DAE.ATTR(variability = var),ty = tp)),var = elt,instStatus = i,env = {})))
      equation
        s = SCodeDump.variabilityString(var);
        elt_str = SCodeDump.printElementStr(elt);
        tp_str = Types.unparseType(tp);
        var_str = Types.unparseVar(tv);
        res = stringAppendList(
          {"v:",n," ",s,"(",elt_str,") [",tp_str,"] {",var_str,
          "}, compframe: []"});
      then
        res;

    case ((n,CLASS(cls = _)))
      equation
        res = stringAppendList({"c:",n,"\n"});
      then
        res;

    case ((n,TYPE(tys = lst)))
      equation
        len = listLength(lst);
        lenstr = intString(len);
        res = stringAppendList({"t:",n," (",lenstr,")\n"});
      then
        res;

    case ((n,_))
      equation
        res = stringAppendList({"oth\n"});
      then
        res;
  end match;
end printFrameElementStr;

public function getCachedInitialEnv "get the initial environment from the cache"
  input Cache cache;
  output Env env;
algorithm
  env := match(cache)
    case (CACHE(initialEnv=SOME(env))) then env;
  end match;
end getCachedInitialEnv;

public function setCachedInitialEnv "set the initial environment in the cache"
  input Cache inCache;
  input Env env;
  output Cache outCache;
algorithm
  outCache := match(inCache,env)
    local
      Option<array<EnvCache>> envCache;
      array<DAE.FunctionTree> ef;
      StructuralParameters ht;
      Absyn.Path p;

    case (CACHE(envCache,_,ef,ht,p),_)
      then CACHE(envCache,SOME(env),ef,ht,p);
  end match;
end setCachedInitialEnv;

public function setCachedFunctionTree
  input Cache inCache;
  input DAE.FunctionTree inFunctions;
  output Cache outCache;
protected
  Option<array<EnvCache>> envCache;
  Option<Env> env;
  array<DAE.FunctionTree> ef;
  StructuralParameters ht;
  Absyn.Path p;
algorithm
  CACHE(envCache, env, _, ht, p) := inCache;
  ef := arrayCreate(1, inFunctions);
  outCache := CACHE(envCache, env, ef, ht, p);
end setCachedFunctionTree;

public function cacheGet "Get an environment from the cache."
  input Absyn.Path scope;
  input Absyn.Path path;
  input Cache cache;
  output Env env;
algorithm
  env:= match (scope,path,cache)
    local
      CacheTree tree;
      array<EnvCache> arr;
   case (_,_,CACHE(envCache=SOME(arr)))
      equation
        ENVCACHE(tree) = arr[1];
        env = cacheGetEnv(scope,path,tree);
        //print("got cached env for ");print(Absyn.pathString(path)); print("\n");
      then env;
  end match;
end cacheGet;

public function cacheAdd "Add an environment to the cache."
  input Absyn.Path fullpath "Fully qualified path to the environment";
  input Cache inCache ;
  input Env env "environment";
  output Cache outCache;
algorithm
  outCache := matchcontinue(fullpath,inCache,env)
  local CacheTree tree;
    array<EnvCache> arr;

    case (_,CACHE(envCache=NONE()),_) then inCache;

    case (_,CACHE(envCache=SOME(arr)),_)
      equation
        ENVCACHE(tree)=arr[1];
        // print(" about to Adding ");print(Absyn.pathString(fullpath));print(" to cache:\n");
        tree = cacheAddEnv(fullpath,tree,env);

        //print("Adding ");print(Absyn.pathString(fullpath));print(" to cache\n");
        //print(printCacheStr(CACHE(SOME(ENVCACHE(tree)),ie)));
        arr = arrayUpdate(arr,1,ENVCACHE(tree));
      then inCache /*CACHE(SOME(arr),ie,ef)*/;
    case (_,_,_)
      equation
        print("cacheAdd failed\n");
      then fail();
  end matchcontinue;
end cacheAdd;

// moved from Inst as is more natural to be here!
public function addCachedEnv
"function: addCachedEnv
  add a new environment in the cache obtaining a new cache"
  input Cache inCache;
  input String id;
  input Env env;
  output Cache outCache;
algorithm
  outCache := matchcontinue(inCache,id,env)
    local
      Absyn.Path path;

    // +d=noCache
    case (_,_,_)
      equation
        true = Flags.isSet(Flags.NO_CACHE);
      then
        inCache;

    case (CACHE(envCache=NONE()),_,_) then inCache;

    case (_,_,_)
      equation
        SOME(path) = getEnvPath(env);
        outCache = cacheAdd(path,inCache,env);
      then outCache;

    case(_,_,_)
      equation
        // this should be placed in the global environment
        // how do we do that??
        true = Flags.isSet(Flags.ENV);
        Debug.traceln("<<<< Env.addCachedEnv - failed to add env to cache for: " +& printEnvPathStr(env) +& " [" +& id +& "]");
      then inCache;

  end matchcontinue;
end addCachedEnv;

protected function cacheGetEnv "get an environment from the tree cache."
  input Absyn.Path scope;
  input Absyn.Path path;
  input CacheTree tree;
  output Env env;
algorithm
  env := match(scope,path,tree)
  local
      Absyn.Path path2;

      // Search only current scope. Since scopes higher up might not be cached, we cannot search upwards.
    case (path2,_,_)
      equation
        env = cacheGetEnv2(path2,path,tree);
        //print("found ");print(Absyn.pathString(path));print(" in cache at scope");
        //print(Absyn.pathString(path2));print("  pathEnv:"+&printEnvPathStr(env)+&"\n");
      then env;
  end match;
end cacheGetEnv;

protected function cacheGetEnv2 "Help function to cacheGetEnv. Searches in one scope by
  first looking up the scope and then search from there."
  input Absyn.Path scope;
  input Absyn.Path path;
  input CacheTree tree;
  output Env env;
algorithm
  env := matchcontinue(scope,path,tree)
    local
      Env env2;
      Ident id1,id2;
      list<CacheTree> children,children2;
      Absyn.Path path2;

    //  Simple name found in children, search for model from this scope.
    case (Absyn.IDENT(id1),_,CACHETREE(_,_,CACHETREE(id2,env2,children2)::_))
      equation
        true = stringEq(id1, id2);
        //print("found (1) ");print(id); print("\n");
        env = cacheGetEnv3(path,children2);
      then
        env;

    //  Simple name. try next.
    case (Absyn.IDENT(id1),_,CACHETREE(id2,env2,_::children))
      equation
        //print("try next ");print(id);print("\n");
        env = cacheGetEnv2(scope,path,CACHETREE(id2,env2,children));
      then
        env;

    // for qualified name, found first matching identifier in child
     case (Absyn.QUALIFIED(id1,path2),_,CACHETREE(_,_,CACHETREE(id2,env2,children2)::_))
       equation
         true = stringEq(id1, id2);
         //print("found qualified (1) ");print(id);print("\n");
         env = cacheGetEnv2(path2,path,CACHETREE(id2,env2,children2));
       then env;

   // for qualified name, try next.
   /*
   case (Absyn.QUALIFIED(id, path2), path, CACHETREE(id2, env2, _ :: children))
     equation
       env = cacheGetEnv2(Absyn.QUALIFIED(id, path2), path, CACHETREE(id2, env2, children));
     then env;*/
  end matchcontinue;
end cacheGetEnv2;

protected function cacheGetEnv3 "Help function to cacheGetEnv2, searches down in tree for env."
  input Absyn.Path inPath;
  input list<CacheTree> inChildren;
  output Env env;
algorithm
  env := match (inPath,inChildren)
    local
      Ident id1, id2;
      Absyn.Path path1,path2,path;
      list<CacheTree> children1,children2,children;
      Boolean b;

    // found matching simple name
    case (Absyn.IDENT(id1),CACHETREE(id2,env,_)::children)
      then Debug.bcallret2(not stringEq(id1, id2), cacheGetEnv3, inPath, children, env);

    // found matching qualified name
    case (path2 as Absyn.QUALIFIED(id1,path1),CACHETREE(id2,_,children1)::children2)
      equation
        b = stringEq(id1, id2);
        path = Util.if_(b,path1,path2);
        children = Util.if_(b,children1,children2);
      then cacheGetEnv3(path,children);
  end match;
end cacheGetEnv3;

public function cacheAddEnv "Add an environment to the cache"
  input Absyn.Path fullpath "Fully qualified path to the environment";
  input CacheTree tree ;
  input Env env "environment";
  output CacheTree outTree;
algorithm
  outTree := matchcontinue(fullpath,tree,env)
    local
      Ident id1,globalID,id2;
      Absyn.Path path;
      Env globalEnv,oldEnv;
      list<CacheTree> children,children2;
      CacheTree child;

    // simple names already added
    case (Absyn.IDENT(id1),(CACHETREE(globalID,globalEnv,CACHETREE(id2,oldEnv,children)::children2)),_)
      equation
        // print(id);print(" already added\n");
        true = stringEq(id1, id2);
        // shouldn't we replace it?
        // Debug.fprintln(Flags.ENV, ">>>> Env.cacheAdd - already in cache: " +& printEnvPathStr(env));
      then tree;

    // simple names try next
    case (Absyn.IDENT(id1),CACHETREE(globalID,globalEnv,child::children),_)
      equation
        CACHETREE(globalID,globalEnv,children) = cacheAddEnv(Absyn.IDENT(id1),CACHETREE(globalID,globalEnv,children),env);
      then CACHETREE(globalID,globalEnv,child::children);

    // Simple names, not found
    case (Absyn.IDENT(id1),CACHETREE(globalID,globalEnv,{}),_)
      equation
        // Debug.fprintln(Flags.ENV, ">>>> Env.cacheAdd - add to cache: " +& printEnvPathStr(env));
      then CACHETREE(globalID,globalEnv,{CACHETREE(id1,env,{})});

    // Qualified names.
    case (path as Absyn.QUALIFIED(_,_),CACHETREE(globalID,globalEnv,children),_)
      equation
        children=cacheAddEnv2(path,children,env);
      then CACHETREE(globalID,globalEnv,children);

    // failure
    case (path,_,_)
      equation
        print("cacheAddEnv path=");print(Absyn.pathString(path));print(" failed\n");
      then fail();
  end matchcontinue;
end cacheAddEnv;

protected function cacheAddEnv2
  input Absyn.Path inPath;
  input list<CacheTree> inChildren;
  input Env env;
  output list<CacheTree> outChildren;
algorithm
  outChildren := matchcontinue(inPath,inChildren,env)
    local
      Ident id1,id2;
      list<CacheTree> children,children2;
      CacheTree child;
      Env env2;
      Absyn.Path path;

    // qualified name, found matching
    case(Absyn.QUALIFIED(id1,path),CACHETREE(id2,env2,children2)::children,_)
      equation
        true = stringEq(id1, id2);
        children2 = cacheAddEnv2(path,children2,env);
      then CACHETREE(id2,env2,children2)::children;

    // simple name, found matching
    case (Absyn.IDENT(id1),CACHETREE(id2,env2,children2)::children,_)
      equation
        true = stringEq(id1, id2);
        // Debug.fprintln(Flags.ENV, ">>>> Env.cacheAdd - already in cache: " +& printEnvPathStr(env));
        //print("single name, found matching\n");
      then CACHETREE(id2,env2,children2)::children;

    // try next
    case(path,child::children,_)
      equation
        //print("try next\n");
        children = cacheAddEnv2(path,children,env);
      then child::children;

    // qualified name no child found, create one.
    case (Absyn.QUALIFIED(id1,path),{},_)
      equation
        children = cacheAddEnv2(path,{},env);
        // Debug.fprintln(Flags.ENV, ">>>> Env.cacheAdd - add to cache: " +& printEnvPathStr(env));
        //print("qualified name no child found, create one.\n");
      then {CACHETREE(id1,emptyEnv,children)};

    // simple name no child found, create one.
    case (Absyn.IDENT(id1),{},_)
      equation
        // print("simple name no child found, create one.\n");
        // Debug.fprintln(Flags.ENV, ">>>> Env.cacheAdd - add to cache: " +& printEnvPathStr(env));
      then {CACHETREE(id1,env,{})};

    case (_,_,_) equation print("cacheAddEnv2 failed\n"); then fail();
  end matchcontinue;
end cacheAddEnv2;

public function printCacheStr
  input Cache cache;
  output String str;
algorithm
  str := matchcontinue(cache)
    local
      CacheTree tree;
      array<EnvCache> arr;
      array<DAE.FunctionTree> ef;
      String s,s2;

    // some cache present
    case CACHE(envCache=SOME(arr),functions=ef)
      equation
        ENVCACHE(tree) = arr[1];
        s = printCacheTreeStr(tree,1);
        str = stringAppendList({"Cache:\n",s,"\n"});
        s2 = DAEDump.dumpFunctionNamesStr(arrayGet(ef,1));
        str = str +& "\nInstantiated funcs: " +& s2 +&"\n";
      then str;
    // empty cache
    else "EMPTY CACHE\n";
  end matchcontinue;
end printCacheStr;

protected function printCacheTreeStr
  input CacheTree tree;
  input Integer indent;
  output String str;
algorithm
  str:= matchcontinue(tree,indent)
    local
      Ident id;
      list<CacheTree> children;
      String s,s1;

    case (CACHETREE(id,_,children),indent)
      equation
        s = stringDelimitList(List.map1(children,printCacheTreeStr,indent+1),"\n");
        s1 = stringAppendList(List.fill(" ",indent));
        str = stringAppendList({s1,id,"\n",s});
      then str;
  end matchcontinue;
end printCacheTreeStr;

protected function dummyDump "
  Author: BZ, 2009-05
  Debug function, print subscripts."
  input list<DAE.Subscript> subs;
  output String str;
algorithm
  str := matchcontinue(subs)
    local DAE.Subscript s;
    case(subs)
      equation
        str = " subs: " +& stringDelimitList(List.map(subs,ExpressionDump.printSubscriptStr),", ") +& "\n";
        print(str);
      then
        str;
  end matchcontinue;
end dummyDump;

protected function integer2Subscript "
@author adrpo
 given an integer transform it into an DAE.Subscript"
  input  Integer       index;
  output DAE.Subscript subscript;
algorithm
 subscript := DAE.INDEX(DAE.ICONST(index));
end integer2Subscript;

/* AVL impementation */
public type AvlKey = String;
public type AvlValue = Item;

public function keyStr "prints a key to a string"
input AvlKey k;
output String str;
algorithm
  str := k;
end keyStr;

protected function printElement
  input SCode.Element el;
  output String str;
algorithm
  str := match(el)
    case (_) then "[el:" +& SCodeDump.unparseElementStr(el) +& "], ";
  end match;
end printElement;

protected function printInstStatus
  input InstStatus instStatus;
  output String str;
algorithm
  str := match(instStatus)
    case (VAR_UNTYPED()) then "inst: var untyped";
    case (VAR_TYPED())   then "inst: var typed";
    case (VAR_DAE())     then "inst: var dae";
  end match;
end printInstStatus;

public function valueStr "prints a Value to a string"
  input AvlValue v;
  output String str;
algorithm
  str := match(v)
    local
      String name; DAE.Type tp; Absyn.Import imp;
      SCode.ConnectorType ct;
      SCode.Parallelism parallelism;
      SCode.Variability variability "variability";
      Absyn.Direction direction "direction";
      Absyn.InnerOuter innerOuter "inner, outer,  inner outer or unspecified";
      SCode.Element el;
      InstStatus instStatus;
      String s1, s2, s3, s4, s5;
      DAE.Binding binding;
      SCode.Element e;
      Env env;


    case(VAR(instantiated=DAE.TYPES_VAR(name=name,attributes=DAE.ATTR(ct, parallelism, variability, direction, innerOuter, _),ty=tp,binding=binding),
             var = el, instStatus=instStatus, env = env))
      equation
        s1 = SCodeDump.connectorTypeStr(ct);
        s1 = Util.if_(stringEq(s1, ""), "", s1 +& ", ");
        s2 = SCodeDump.parallelismString(parallelism);
        s2 = Util.if_(stringEq(s2, ""), "", s2 +& ", ");
        s3 = SCodeDump.variabilityString(variability);
        s3 = Util.if_(stringEq(s3, ""), "", s3 +& ", ");
        s4 = Dump.unparseDirectionSymbolStr(direction);
        s4 = Util.if_(stringEq(s4, ""), "", s4 +& ", ");
        s5 = SCodeDump.innerouterString(innerOuter);
        s5 = Util.if_(stringEq(s5, ""), "", s5 +& ", ");

        str = "var:    " +& name +& " " +& Types.unparseType(tp) +& "("
        +& Types.printTypeStr(tp) +& ") binding: " +& Types.printBindingStr(binding) +& " attr: " +& s1 +& s2 +& s3 +& s4 +& s5 +&
        printElement(el) +& printInstStatus(instStatus) +& " env: " +& printEnvPathStr(env);
      then str;

    case(CLASS(cls = e as SCode.CLASS(name=name), env = env))
      equation
        str = "class: " +& SCodeDump.shortElementStr(e) +& " env: " +& printEnvPathStr(env);
      then str;

    case(TYPE(tp::_))
      equation
        str = "type:   " +& Types.unparseType(tp);
      then str;

  end match;
end valueStr;

/* Generic Code below */
public
uniontype AvlTree "The binary tree data structure
 "
  record AVLTREENODE
    Option<AvlTreeValue> value "Value" ;
    Integer height "heigth of tree, used for balancing";
    Option<AvlTree> left "left subtree" ;
    Option<AvlTree> right "right subtree" ;
  end AVLTREENODE;

end AvlTree;

public
uniontype AvlTreeValue "Each node in the binary tree can have a value associated with it."
  record AVLTREEVALUE
    AvlKey key "Key" ;
    AvlValue value "Value" ;
  end AVLTREEVALUE;

end AvlTreeValue;

public function avlTreeNew "Return an empty tree"
  output AvlTree tree;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  tree := AVLTREENODE(NONE(),0,NONE(),NONE());
end avlTreeNew;

public function avlTreeAdd
  "Help function to avlTreeAdd."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match (inAvlTree,inKey,inValue)
    local
      AvlKey key,rkey;
      AvlValue value;

    // empty tree
    case (AVLTREENODE(value = NONE(),left = NONE(),right = NONE()),key,value)
      then AVLTREENODE(SOME(AVLTREEVALUE(key,value)),1,NONE(),NONE());

    case (AVLTREENODE(value = SOME(AVLTREEVALUE(key=rkey))),key,value)
      then balance(avlTreeAdd2(inAvlTree,stringCompare(key,rkey),key,value));

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Env.avlTreeAdd failed"});
      then fail();
  end match;
end avlTreeAdd;

public function avlTreeAdd2
  "Help function to avlTreeAdd."
  input AvlTree inAvlTree;
  input Integer keyComp "0=get value from current node, 1=search right subtree, -1=search left subtree";
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match (inAvlTree,keyComp,inKey,inValue)
    local
      AvlKey key,rkey;
      AvlValue value;
      Option<AvlTree> left,right;
      Integer h;
      AvlTree t_1,t;
      Option<AvlTreeValue> oval;
      Absyn.Info info;

    /*/ Don't allow replacing of nodes.
    case (_, 0, key, _)
      equation
        info = FEnv.getItemInfo(inValue);
        Error.addSourceMessage(Error.DOUBLE_DECLARATION_OF_ELEMENTS,
          {inKey}, info);
      then
        fail();*/

    // replace this node
    case (AVLTREENODE(value = SOME(AVLTREEVALUE(key=rkey)),height=h,left = left,right = right),0,key,value)
      equation
        // inactive for now, but we should check if we don't replace a class with a var or vice-versa!
        // checkValueReplacementCompatible(rval, value);
      then
        AVLTREENODE(SOME(AVLTREEVALUE(rkey,value)),h,left,right);

    // insert to right
    case (AVLTREENODE(value = oval,height=h,left = left,right = right),1,key,value)
      equation
        t = createEmptyAvlIfNone(right);
        t_1 = avlTreeAdd(t, key, value);
      then
        AVLTREENODE(oval,h,left,SOME(t_1));

    // insert to left subtree
    case (AVLTREENODE(value = oval,height=h,left = left ,right = right),-1,key,value)
      equation
        t = createEmptyAvlIfNone(left);
        t_1 = avlTreeAdd(t, key, value);
      then
        AVLTREENODE(oval,h,SOME(t_1),right);

  end match;
end avlTreeAdd2;

protected function checkValueReplacementCompatible
"@author: adrpo 2010-10-07
  This function checks if what we replace in the environment
  is compatible with the value we want to replace with.
  VAR<->VAR OK
  CLASS<->CLASS OK
  TYPE<->TYPE OK
  All the other replacements will output a warning!"
  input AvlValue val1;
  input AvlValue val2;
algorithm
  _ := match(val1, val2)
    local
      Absyn.Info aInfo;
      String n1, n2;

    // var can replace var
    case (VAR(instantiated = _), VAR(instantiated = _)) then ();
    // class can replace class
    case (CLASS(cls = _),     CLASS(cls = _)) then ();
    // type can replace type
    case (TYPE(tys = _),       TYPE(tys = _)) then ();
    // anything else is an error!
    case (val1, val2)
      equation
        (n1, n2, aInfo) = getNamesAndInfoFromVal(val1, val2);
        Error.addSourceMessage(Error.COMPONENT_NAME_SAME_AS_TYPE_NAME, {n1,n2}, aInfo);
      then
        ();
  end match;
end checkValueReplacementCompatible;

protected function getNamesAndInfoFromVal
  input AvlValue val1;
  input AvlValue val2;
  output String name1;
  output String name2;
  output Absyn.Info info;
algorithm
  (name1, name2, info) := matchcontinue(val1, val2)
    local
      Absyn.Info aInfo;
      String n1, n2, n;
      Env env;

    // var should not be replaced by class!
    case (VAR(var = SCode.COMPONENT(name = n1, info = aInfo)),
          CLASS(cls = SCode.CLASS(name = n2, info = _), env = env))
      equation
         n = printEnvPathStr(env);
         n2 = n +& "." +& n2;
      then
        (n1, n2, aInfo);

    // class should not be replaced by var!
    case (CLASS(cls = _), VAR(instantiated = _))
      equation
        // call ourselfs reversed
        (n1, n2, aInfo) = getNamesAndInfoFromVal(val2, val1);
      then
        (n1, n2, aInfo);

    // anything else that might happen??
    case (val1, val2)
      equation
        n1 = valueStr(val1);
        n2 = valueStr(val2);
      then
        (n1, n2, Absyn.dummyInfo);
  end matchcontinue;
end getNamesAndInfoFromVal;

protected function createEmptyAvlIfNone "Help function to AvlTreeAdd2"
  input Option<AvlTree> t;
  output AvlTree outT;
algorithm
  outT := match (t)
    case(NONE()) then AVLTREENODE(NONE(),0,NONE(),NONE());
    case(SOME(outT)) then outT;
  end match;
end createEmptyAvlIfNone;

protected function nodeValue "return the node value"
  input AvlTree bt;
  output AvlValue v;
algorithm
  v := match (bt)
    case(AVLTREENODE(value=SOME(AVLTREEVALUE(_,v)))) then v;
  end match;
end nodeValue;

protected function balance "Balances a AvlTree"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (inBt)
    local Integer d; AvlTree bt;
    case (bt)
      equation
        d = differenceInHeight(bt);
        bt = doBalance(d,bt);
      then bt;
  end match;
end balance;

protected function doBalance "perform balance if difference is > 1 or < -1"
  input Integer difference;
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (difference,inBt)
    local AvlTree bt;
    case(-1,bt) then computeHeight(bt);
    case(0,bt) then computeHeight(bt);
    case(1,bt) then computeHeight(bt);
      /* d < -1 or d > 1 */
    case(_,bt)
      equation
        bt = doBalance2(difference < 0,bt);
      then bt;
  end match;
end doBalance;

protected function doBalance2 "help function to doBalance"
  input Boolean differenceIsNegative;
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := match (differenceIsNegative,inBt)
    local AvlTree bt;
    case (true,bt)
      equation
        bt = doBalance3(bt);
        bt = rotateLeft(bt);
      then bt;
    case (false,bt)
      equation
        bt = doBalance4(bt);
        bt = rotateRight(bt);
      then bt;
  end match;
end doBalance2;

protected function doBalance3 "help function to doBalance2"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := matchcontinue(inBt)
    local
      AvlTree rr,bt;
    case(bt)
      equation
        true = differenceInHeight(getOption(rightNode(bt))) > 0;
        rr = rotateRight(getOption(rightNode(bt)));
        bt = setRight(bt,SOME(rr));
      then bt;
    else inBt;
  end matchcontinue;
end doBalance3;

protected function doBalance4 "help function to doBalance2"
  input AvlTree inBt;
  output AvlTree outBt;
algorithm
  outBt := matchcontinue(inBt)
    local
      AvlTree rl,bt;
    case (bt)
      equation
        true = differenceInHeight(getOption(leftNode(bt))) < 0;
        rl = rotateLeft(getOption(leftNode(bt)));
        bt = setLeft(bt,SOME(rl));
      then bt;
    else inBt;
  end matchcontinue;
end doBalance4;

protected function setRight "set right treenode"
  input AvlTree node;
  input Option<AvlTree> right;
  output AvlTree outNode;
algorithm
  outNode := match (node,right)
   local Option<AvlTreeValue> value;
    Option<AvlTree> l,r;
    Integer height;
    case(AVLTREENODE(value,height,l,r),_) then AVLTREENODE(value,height,l,right);
  end match;
end setRight;

protected function setLeft "set left treenode"
  input AvlTree node;
  input Option<AvlTree> left;
  output AvlTree outNode;
algorithm
  outNode := match (node,left)
  local Option<AvlTreeValue> value;
    Option<AvlTree> l,r;
    Integer height;
    case(AVLTREENODE(value,height,l,r),_) then AVLTREENODE(value,height,left,r);
  end match;
end setLeft;

protected function leftNode "Retrieve the left subnode"
  input AvlTree node;
  output Option<AvlTree> subNode;
algorithm
  subNode := match(node)
    case(AVLTREENODE(left = subNode)) then subNode;
  end match;
end leftNode;

protected function rightNode "Retrieve the right subnode"
  input AvlTree node;
  output Option<AvlTree> subNode;
algorithm
  subNode := match(node)
    case(AVLTREENODE(right = subNode)) then subNode;
  end match;
end rightNode;

protected function exchangeLeft "help function to balance"
  input AvlTree inNode;
  input AvlTree inParent;
  output AvlTree outParent "updated parent";
algorithm
  outParent := match(inNode,inParent)
    local
      AvlTree bt,node,parent;

    case(node,parent) equation
      parent = setRight(parent,leftNode(node));
      parent = balance(parent);
      node = setLeft(node,SOME(parent));
      bt = balance(node);
    then bt;
  end match;
end exchangeLeft;

protected function exchangeRight "help function to balance"
  input AvlTree inNode;
  input AvlTree inParent;
  output AvlTree outParent "updated parent";
algorithm
  outParent := match(inNode,inParent)
  local AvlTree bt,node,parent;
    case(node,parent) equation
      parent = setLeft(parent,rightNode(node));
      parent = balance(parent);
      node = setRight(node,SOME(parent));
      bt = balance(node);
    then bt;
  end match;
end exchangeRight;

protected function rotateLeft "help function to balance"
input AvlTree node;
output AvlTree outNode "updated node";
algorithm
  outNode := exchangeLeft(getOption(rightNode(node)),node);
end rotateLeft;

protected function getOption "Retrieve the value of an option"
  replaceable type T subtypeof Any;
  input Option<T> opt;
  output T val;
algorithm
  val := match(opt)
    case(SOME(val)) then val;
  end match;
end getOption;

protected function rotateRight "help function to balance"
input AvlTree node;
output AvlTree outNode "updated node";
algorithm
  outNode := exchangeRight(getOption(leftNode(node)),node);
end rotateRight;

protected function differenceInHeight "help function to balance, calculates the difference in height
between left and right child"
  input AvlTree node;
  output Integer diff;
algorithm
  diff := match (node)
    local
      Integer lh,rh;
      Option<AvlTree> l,r;
    case(AVLTREENODE(left=l,right=r))
      equation
        lh = getHeight(l);
        rh = getHeight(r);
      then lh - rh;
  end match;
end differenceInHeight;

public function avlTreeGet
  "Get a value from the binary tree given a key."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  output AvlValue outValue;
algorithm
  outValue := match (inAvlTree,inKey)
    local
      AvlKey rkey,key;
    case (AVLTREENODE(value = SOME(AVLTREEVALUE(key=rkey))),key)
      then avlTreeGet2(inAvlTree,stringCompare(key,rkey),key);
  end match;
end avlTreeGet;

protected function avlTreeGet2
  "Get a value from the binary tree given a key."
  input AvlTree inAvlTree;
  input Integer keyComp "0=get value from current node, 1=search right subtree, -1=search left subtree";
  input AvlKey inKey;
  output AvlValue outValue;
algorithm
  outValue := match (inAvlTree,keyComp,inKey)
    local
      AvlKey key;
      AvlValue rval;
      AvlTree left,right;

    // hash func Search to the right
    case (AVLTREENODE(value = SOME(AVLTREEVALUE(value=rval))),0,key)
      then rval;

    // search to the right
    case (AVLTREENODE(right = SOME(right)),1,key)
      then avlTreeGet(right, key);

    // search to the left
    case (AVLTREENODE(left = SOME(left)),-1,key)
      then avlTreeGet(left, key);
  end match;
end avlTreeGet2;

protected function getOptionStr "function getOptionStr
  Retrieve the string from a string option.
  If NONE() return empty string."
  input Option<Type_a> inTypeAOption;
  input FuncTypeType_aToString inFuncTypeTypeAToString;
  output String outString;
  replaceable type Type_a subtypeof Any;
  partial function FuncTypeType_aToString
    input Type_a inTypeA;
    output String outString;
  end FuncTypeType_aToString;
algorithm
  outString:=
  match (inTypeAOption,inFuncTypeTypeAToString)
    local
      String str;
      Type_a a;
      FuncTypeType_aToString r;
    case (SOME(a),r)
      equation
        str = r(a);
      then
        str;
    case (NONE(),_) then "";
  end match;
end getOptionStr;

protected function printAvlTreeStr "
  Prints the avl tree to a string"
  input AvlTree inAvlTree;
  output String outString;
algorithm
  outString:=
  match (inAvlTree)
    local
      AvlKey rkey;
      String s2,s3,res;
      AvlValue rval;
      Option<AvlTree> l,r;
      Integer h;

    case (AVLTREENODE(value = SOME(AVLTREEVALUE(rkey,rval)),height = h,left = l,right = r))
      equation
        s2 = getOptionStr(l, printAvlTreeStr);
        s3 = getOptionStr(r, printAvlTreeStr);
        res = "\n" +& valueStr(rval) +& ",  " +& Util.if_(stringEq(s2, ""), "", s2 +& ", ") +& s3;
      then
        res;
    case (AVLTREENODE(value = NONE(),left = l,right = r))
      equation
        s2 = getOptionStr(l, printAvlTreeStr);
        s3 = getOptionStr(r, printAvlTreeStr);
        res = Util.if_(stringEq(s2, ""), "", s2 +& ", ") +& s3;
      then
        res;
  end match;
end printAvlTreeStr;

protected function computeHeight "compute the heigth of the AvlTree and store in the node info"
  input AvlTree bt;
  output AvlTree outBt;
algorithm
  outBt := match(bt)
    local
      Option<AvlTree> l,r;
      Option<AvlTreeValue> v;
      Integer hl,hr,height;
    case(AVLTREENODE(value=v as SOME(_),left=l,right=r))
      equation
        hl = getHeight(l);
        hr = getHeight(r);
        height = intMax(hl,hr) + 1;
      then AVLTREENODE(v,height,l,r);
  end match;
end computeHeight;

protected function getHeight "Retrieve the height of a node"
  input Option<AvlTree> bt;
  output Integer height;
algorithm
  height := match (bt)
    case(NONE()) then 0;
    case(SOME(AVLTREENODE(height = height))) then height;
  end match;
end getHeight;

public function isTopScope "Returns true if we are in the top-most scope"
  input Env env;
  output Boolean isTop;
algorithm
  isTop := matchcontinue env
    case {FRAME(name = NONE())} then true;
    case _ then false;
  end matchcontinue;
end isTopScope;

public function getVariablesFromEnv
"@author: adrpo
  returns the a list with all the variables in the given environment"
  input Env inEnv;
  output list<String> variables;
algorithm
  variables := match (inEnv)
    local
      list<Ident> lst1;
      Frame fr;
      Env frs;
    // empty case
    case {} then {};
    // some environment
    case (fr :: frs)
      equation
        lst1 = getVariablesFromFrame(fr);
        // adrpo: TODO! FIXME! CHECK if we really don't need this!
        // lst2 = getVariablesFromEnv(frs);
        // lst = listAppend(lst1, lst2);
      then
        lst1;
  end match;
end getVariablesFromEnv;

protected function getVariablesFromFrame
"@author: adrpo
  returns all variables in the frame as a list of strings."
  input Frame inFrame;
  output list<String> variables;
algorithm
  variables := match (inFrame)
    local
      list<Ident> lst;
      AvlTree ht;

    case FRAME(clsAndVars = ht)
      equation
        lst = getVariablesFromAvlTree(ht);
      then
        lst;
  end match;
end getVariablesFromFrame;

protected function getVariablesFromAvlTree
"@author: adrpo
  returns variables from the avl tree as a list of strings"
  input AvlTree inAvlTree;
  output list<String> variables;
algorithm
  variables := match (inAvlTree)
    local
      AvlKey rkey;
      list<String> lst0, lst1, lst2, lst;
      AvlValue rval;
      Option<AvlTree> l,r;
      Integer h;

    case (AVLTREENODE(value = SOME(AVLTREEVALUE(rkey,rval)),height = h,left = l,right = r))
      equation
        lst0 = getVariablesFromAvlValue(rval);
        lst1 = getVariablesFromOptionAvlTree(l);
        lst2 = getVariablesFromOptionAvlTree(r);
        lst = listAppend(lst1, lst2);
        lst = listAppend(lst0, lst);
      then
        lst;

    case (AVLTREENODE(value = NONE(),left = l,right = r))
      equation
        lst1 = getVariablesFromOptionAvlTree(l);
        lst2 = getVariablesFromOptionAvlTree(r);
        lst = listAppend(lst1, lst2);
      then
        lst;
  end match;
end getVariablesFromAvlTree;

protected function getVariablesFromOptionAvlTree
"@author: adrpo
  returns the variables from the given optional tree as a list of strings.
  if the tree is none then the function returns an empty list"
  input Option<AvlTree> inAvlTreeOpt;
  output list<String> variables;
algorithm
  variables := match (inAvlTreeOpt)
    local
      AvlTree avl;
    // handle nothingness
    case (NONE()) then {};
    // we have some value
    case (SOME(avl)) then getVariablesFromAvlTree(avl);
  end match;
end getVariablesFromOptionAvlTree;

public function getVariablesFromAvlValue
"@author:adrpo
  returns a list with one variable or an empty list"
  input AvlValue v;
  output list<String> variables;
algorithm
  variables := matchcontinue(v)
    local
      String name;
    case(VAR(instantiated=DAE.TYPES_VAR(name=name))) then {name};
    case(_) then {};
  end matchcontinue;
end getVariablesFromAvlValue;

public function inFunctionScope
  input Env inEnv;
  output Boolean inFunction;
algorithm
  inFunction := matchcontinue(inEnv)
    local
      list<Frame> fl;
    case ({}) then false;
    case (FRAME(scopeType = SOME(FUNCTION_SCOPE())) :: _) then true;
    case (FRAME(scopeType = SOME(CLASS_SCOPE())) :: _) then false;
    case (_ :: fl) then inFunctionScope(fl);
  end matchcontinue;
end inFunctionScope;

public function classInfToScopeType
  input ClassInf.State inState;
  output Option<ScopeType> outType;
algorithm
  outType := matchcontinue(inState)
    case ClassInf.FUNCTION(path = _) then SOME(FUNCTION_SCOPE());
    case _ then SOME(CLASS_SCOPE());
  end matchcontinue;
end classInfToScopeType;

public function restrictionToScopeType
  input SCode.Restriction inRestriction;
  output Option<ScopeType> outType;
algorithm
  outType := matchcontinue(inRestriction)
    case SCode.R_FUNCTION(SCode.FR_PARALLEL_FUNCTION()) then SOME(PARALLEL_SCOPE());
    case SCode.R_FUNCTION(SCode.FR_KERNEL_FUNCTION()) then SOME(PARALLEL_SCOPE());
    case SCode.R_FUNCTION(_) then SOME(FUNCTION_SCOPE());
    case _ then SOME(CLASS_SCOPE());
  end matchcontinue;
end restrictionToScopeType;

public function getFunctionTree
"Selector function"
  input Cache cache;
  output DAE.FunctionTree ft;
protected
  array<DAE.FunctionTree> ef;
algorithm
  CACHE(functions = ef) := cache;
  ft := arrayGet(ef, 1);
end getFunctionTree;

public function addCachedInstFuncGuard
"adds the FQ path to the set of instantiated functions as NONE().
This guards against recursive functions."
  input Cache cache;
  input Absyn.Path func "fully qualified function name";
  output Cache outCache;
algorithm
  outCache := matchcontinue(cache,func)
    local
      Option<array<EnvCache>> envCache;
      array<DAE.FunctionTree> ef;
      Option<Env> ienv;
      StructuralParameters ht;
      Absyn.Path p;
      /* Don't overwrite SOME() with NONE() */
    case (_, _)
      equation
        checkCachedInstFuncGuard(cache, func);
      then cache;

    case (CACHE(envCache,ienv,ef,ht,p),Absyn.FULLYQUALIFIED(_))
      equation
        ef = arrayUpdate(ef,1,DAEUtil.avlTreeAdd(arrayGet(ef, 1),func,NONE()));
      then CACHE(envCache,ienv,ef,ht,p);
    // Non-FQ paths mean aliased functions; do not add these to the cache
    case (_,_) then (cache);
  end matchcontinue;
end addCachedInstFuncGuard;

public function addDaeFunction
"adds the list<DAE.Function> to the set of instantiated functions"
  input Cache inCache;
  input list<DAE.Function> funcs "fully qualified function name";
  output Cache outCache;
algorithm
  outCache := match(inCache,funcs)
    local
      Option<array<EnvCache>> envCache;
      array<DAE.FunctionTree> ef;
      Option<Env> ienv;
      StructuralParameters ht;
      Absyn.Path p;
    case (CACHE(envCache,ienv,ef,ht,p),_)
      equation
        ef = arrayUpdate(ef,1,DAEUtil.addDaeFunction(funcs, arrayGet(ef, 1)));
      then CACHE(envCache,ienv,ef,ht,p);
  end match;
end addDaeFunction;

public function addDaeExtFunction
"adds the external functions in list<DAE.Function> to the set of instantiated functions"
  input Cache inCache;
  input list<DAE.Function> funcs "fully qualified function name";
  output Cache outCache;
algorithm
  outCache := match(inCache,funcs)
    local
      Option<array<EnvCache>> envCache;
      array<DAE.FunctionTree> ef;
      Option<Env> ienv;
      StructuralParameters ht;
      Absyn.Path p;
    case (CACHE(envCache,ienv,ef,ht,p),_)
      equation
        ef = arrayUpdate(ef,1,DAEUtil.addDaeExtFunction(funcs, arrayGet(ef,1)));
      then CACHE(envCache,ienv,ef,ht,p);
  end match;
end addDaeExtFunction;

public function getCachedInstFunc
"returns the function in the set"
  input Cache inCache;
  input Absyn.Path path;
  output DAE.Function func;
algorithm
  func := match(inCache,path)
    local
      array<DAE.FunctionTree> ef;
    case(CACHE(functions=ef),_)
      equation
        SOME(func) = DAEUtil.avlTreeGet(arrayGet(ef,1),path);
      then func;
  end match;
end getCachedInstFunc;

public function checkCachedInstFuncGuard
"succeeds if the FQ function is in the set of functions"
  input Cache inCache;
  input Absyn.Path path;
algorithm
  _ := match(inCache,path)
    local
      array<DAE.FunctionTree> ef;
    case(CACHE(functions=ef),_) equation
      _ = DAEUtil.avlTreeGet(arrayGet(ef,1),path);
    then ();
  end match;
end checkCachedInstFuncGuard;

public function printAvlTreeStrPP
  input AvlTree inTree;
  output String outString;
algorithm
  outString := printAvlTreeStrPP2(SOME(inTree), "");
end printAvlTreeStrPP;

protected function printAvlTreeStrPP2
  input Option<AvlTree> inTree;
  input String inIndent;
  output String outString;
algorithm
  outString := match(inTree, inIndent)
    local
      AvlKey rkey;
      Option<AvlTree> l, r;
      String s1, s2, res, indent;

    case (NONE(), _) then "";

    case (SOME(AVLTREENODE(value = SOME(AVLTREEVALUE(key = rkey)), left = l, right = r)), _)
      equation
        indent = inIndent +& "  ";
        s1 = printAvlTreeStrPP2(l, indent);
        s2 = printAvlTreeStrPP2(r, indent);
        res = "\n" +& inIndent +& rkey +& s1 +& s2;
      then
        res;

    case (SOME(AVLTREENODE(value = NONE(), left = l, right = r)), _)
      equation
        indent = inIndent +& "  ";
        s1 = printAvlTreeStrPP2(l, indent);
        s2 = printAvlTreeStrPP2(r, indent);
        res = "\n" +& s1 +& s2;
      then
        res;
  end match;
end printAvlTreeStrPP2;

public function addEvaluatedCref
  input Cache cache;
  input SCode.Variability var;
  input DAE.ComponentRef cr;
  output Cache ocache;
algorithm
  ocache := match (cache,var,cr)
    local
      String str;
      Option<array<EnvCache>> envCache;
      Option<Env> initialEnv;
      array<DAE.FunctionTree> functions;
      HashTable.HashTable ht;
      list<list<DAE.ComponentRef>> st;
      list<DAE.ComponentRef> crs;
      Absyn.Path p;
    case (CACHE(envCache,initialEnv,functions,(ht,crs::st),p),SCode.PARAM(),_)
      equation
        // str = ComponentReference.printComponentRefStr(cr);
      then CACHE(envCache,initialEnv,functions,(ht,(cr::crs)::st),p);
    else cache;
  end match;
end addEvaluatedCref;

public function getEvaluatedParams
  input Cache cache;
  output HashTable.HashTable ht;
algorithm
  CACHE(evaluatedParams=(ht,_)) := cache;
end getEvaluatedParams;

public function printNumStructuralParameters
  input Cache cache;
protected
  list<DAE.ComponentRef> crs;
algorithm
  CACHE(evaluatedParams=(_,crs::_)) := cache;
  print("printNumStructuralParameters: " +& intString(listLength(crs)) +& "\n");
end printNumStructuralParameters;

public function setCacheClassName
  input Cache inCache;
  input Absyn.Path p;
  output Cache outCache;
algorithm
  outCache := match(inCache,p)
    local
      Option<array<EnvCache>> envCache;
      array<DAE.FunctionTree> ef;
      StructuralParameters ht;
      Option<Env> ienv;

    case (CACHE(envCache,ienv,ef,ht,_),_)
      then CACHE(envCache,ienv,ef,ht,p);
  end match;
end setCacheClassName;

public function avlTreeReplace
  "Replaces the value of an already existing node in the tree with a new value."
  input AvlTree inAvlTree;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match(inAvlTree, inKey, inValue)
    local
      AvlKey key, rkey;
      AvlValue value;

    case (AVLTREENODE(value = SOME(AVLTREEVALUE(key = rkey))), key, value)
      then avlTreeReplace2(inAvlTree, stringCompare(key, rkey), key, value);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Env.avlTreeReplace failed"});
      then fail();

  end match;
end avlTreeReplace;

protected function avlTreeReplace2
  "Helper function to avlTreeReplace."
  input AvlTree inAvlTree;
  input Integer inKeyComp;
  input AvlKey inKey;
  input AvlValue inValue;
  output AvlTree outAvlTree;
algorithm
  outAvlTree := match(inAvlTree, inKeyComp, inKey, inValue)
    local
      AvlKey key;
      AvlValue value;
      Option<AvlTree> left, right;
      Integer h;
      AvlTree t;
      Option<AvlTreeValue> oval;

    // Replace this node.
    case (AVLTREENODE(value = SOME(_), height = h, left = left, right = right),
        0, key, value)
      then AVLTREENODE(SOME(AVLTREEVALUE(key, value)), h, left, right);

    // Insert into right subtree.
    case (AVLTREENODE(value = oval, height = h, left = left, right = right),
        1, key, value)
      equation
        t = createEmptyAvlIfNone(right);
        t = avlTreeReplace(t, key, value);
      then
        AVLTREENODE(oval, h, left, SOME(t));

    // Insert into left subtree.
    case (AVLTREENODE(value = oval, height = h, left = left, right = right),
        -1, key, value)
      equation
        t = createEmptyAvlIfNone(left);
        t = avlTreeReplace(t, key, value);
      then
        AVLTREENODE(oval, h, SOME(t), right);
  end match;
end avlTreeReplace2;

public function getClassesInFrame
  input Frame fr;
  output list<SCode.Element> elts;
protected
  AvlTree ht;
  list<AvlTreeValue> vals;
algorithm
  FRAME(clsAndVars=ht) := fr;
  vals := getAvlTreeItems(SOME(ht)::{},{});
  elts := List.fold(vals,getClassesFromItem,{});
end getClassesInFrame;

protected function getClassesFromItem
  input AvlTreeValue v;
  input list<SCode.Element> acc;
  output list<SCode.Element> res;
algorithm
  res := match (v,acc)
    local
      SCode.Element c;
    case (AVLTREEVALUE(value=CLASS(cls=c)),_) then c::acc;
    else acc;
  end match;
end getClassesFromItem;

protected function getAvlTreeItems
  input list<Option<AvlTree>> tree;
  input list<AvlTreeValue> acc;
  output list<AvlTreeValue> res;
algorithm
  res := match (tree,acc)
    local
      Option<AvlTreeValue> value;
      Option<AvlTree> left,right;
      list<Option<AvlTree>> rest;
    case ({},_) then acc;
    case (SOME(AVLTREENODE(value=value,left=left,right=right))::rest,_)
      then getAvlTreeItems(left::right::rest,List.consOption(value,acc));
    case (NONE()::rest,_) then getAvlTreeItems(rest,acc);
  end match;
end getAvlTreeItems;

end Env;

