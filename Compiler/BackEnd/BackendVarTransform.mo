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

encapsulated package BackendVarTransform
" file:        BackendVarTransform.mo
  package:     BackendVarTransform
  description: BackendVarTransform contains a Binary Tree representation of variable replacements.

  RCS: $Id$

  This module contain a Binary tree representation of variable replacements
  along with some functions for performing replacements of variables in equations"

public import BackendDAE;
public import DAE;
public import HashTable2;
public import HashTable3;

protected import Absyn;
protected import BaseHashTable;
protected import BaseHashSet;
protected import BackendDAEUtil;
protected import BackendEquation;
protected import ClassInf;
protected import ComponentReference;
protected import DAEUtil;
protected import Debug;
protected import Expression;
protected import ExpressionDump;
protected import ExpressionSimplify;
protected import Flags;
protected import HashSet;
protected import List;
protected import Util;

public
uniontype VariableReplacements
"VariableReplacements consists of a mapping between variables and expressions, the first binary tree of this type.
 To eliminate a variable from an equation system a replacement rule varname->expression is added to this
 datatype.
 To be able to update these replacement rules incrementally a backward lookup mechanism is also required.
 For instance, having a rule a->b and adding a rule b->c requires to find the first rule a->b and update it to
 a->c. This is what the second binary tree is used for."
  record REPLACEMENTS
    HashTable2.HashTable hashTable "src -> dst, used for replacing. src is variable, dst is expression.";
    HashTable3.HashTable invHashTable "dst -> list of sources. dst is a variable, sources are variables.";
    HashTable2.HashTable extendhashTable "src -> noting, used for extend arrays and records.";
    list<DAE.Ident> iterationVars "this are the implicit declerate iteration variables for for and range expressions";
    Option<HashTable2.HashTable> derConst "this is used if states are constant to replace der(state) with 0.0";
  end REPLACEMENTS;

end VariableReplacements;

public function emptyReplacements "function: emptyReplacements

  Returns an empty set of replacement rules
"
  output VariableReplacements outVariableReplacements;
algorithm
  outVariableReplacements:=
  match ()
      local HashTable2.HashTable ht,eht;
        HashTable3.HashTable invHt;
    case ()
      equation
        ht = HashTable2.emptyHashTable();
        eht = HashTable2.emptyHashTable();
        invHt = HashTable3.emptyHashTable();
      then
        REPLACEMENTS(ht,invHt,eht,{},NONE());
  end match;
end emptyReplacements;

public function emptyReplacementsSized "function: emptyReplacements
  Returns an empty set of replacement rules, giving a size of hashtables to allocate"
  input Integer size;
  output VariableReplacements outVariableReplacements;
algorithm
  outVariableReplacements := match (size)
      local HashTable2.HashTable ht,eht;
        HashTable3.HashTable invHt;
    case _
      equation
        ht = HashTable2.emptyHashTableSized(size);
        invHt = HashTable3.emptyHashTableSized(size);
        eht = HashTable2.emptyHashTableSized(size);
      then
        REPLACEMENTS(ht,invHt,eht,{},NONE());
  end match;
end emptyReplacementsSized;

public function addReplacements
  input VariableReplacements iRepl;
  input list<DAE.ComponentRef> inSrcs;
  input list<DAE.Exp> inDsts;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output VariableReplacements outRepl;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
   outRepl := match(iRepl,inSrcs,inDsts,inFuncTypeExpExpToBooleanOption)
     local
       DAE.ComponentRef cr;
       list<DAE.ComponentRef> crlst;
       DAE.Exp exp;
       VariableReplacements repl;
       list<DAE.Exp> explst;
     case (_,{},{},_) then iRepl;
     case (_,cr::crlst,exp::explst,_)
       equation
         repl = addReplacement(iRepl,cr,exp,inFuncTypeExpExpToBooleanOption);
       then
         addReplacements(repl,crlst,explst,inFuncTypeExpExpToBooleanOption);
   end match;
end addReplacements;

public function addReplacement "function: addReplacement

  Adds a replacement rule to the set of replacement rules given as argument.
  If a replacement rule a->b already exists and we add a new rule b->c then
  the rule a->b is updated to a->c. This is done using the make_transitive
  function.
"
  input VariableReplacements repl;
  input DAE.ComponentRef inSrc;
  input DAE.Exp inDst;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output VariableReplacements outRepl;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  outRepl:=
  matchcontinue (repl,inSrc,inDst,inFuncTypeExpExpToBooleanOption)
    local
      DAE.ComponentRef src,src_1;
      DAE.Exp dst,dst_1;
      HashTable2.HashTable ht,ht_1,eht,eht_1;
      HashTable3.HashTable invHt,invHt_1;
      list<DAE.Ident> iv;
      String s;
      Option<HashTable2.HashTable> derConst;
    // PA: Commented out this, since it will only slow things down without adding any functionality.
    // Once match is available as a complement to matchcontinue, this case could be useful again.
    //case ((repl as REPLACEMENTS(ht,invHt)),src,dst) /* source dest */
     // equation
     //   olddst = BaseHashTable.get(src, ht) "if rule a->b exists, fail" ;
     // then
     //   fail();

    case (_,src,dst,_)
      equation
        (REPLACEMENTS(ht,invHt,eht,iv,derConst),src_1,dst_1) = makeTransitive(repl, src, dst, inFuncTypeExpExpToBooleanOption);
        /*s1 = ComponentReference.printComponentRefStr(src);
        s2 = ExpressionDump.printExpStr(dst);
        s3 = ComponentReference.printComponentRefStr(src_1);
        s4 = ExpressionDump.printExpStr(dst_1);
        s = stringAppendList(
          {"add_replacement(",s1,", ",s2,") -> add_replacement(",s3,
          ", ",s4,")\n"});
          print(s);
        Debug.fprint(Flags.ADD_REPL, s);*/
        ht_1 = BaseHashTable.add((src_1, dst_1),ht);
        invHt_1 = addReplacementInv(invHt, src_1, dst_1);
        eht_1 = addExtendReplacement(eht,src_1,NONE());
      then
        REPLACEMENTS(ht_1,invHt_1,eht_1,iv,derConst);
    case (_,_,_,_)
      equation
        s = ComponentReference.printComponentRefStr(inSrc);
        print("-BackendVarTransform.addReplacement failed for " +& s);
      then
        fail();
  end matchcontinue;
end addReplacement;

protected function addReplacementNoTransitive "Similar to addReplacement but
does not make transitive replacement rules.
"
  input VariableReplacements repl;
  input DAE.ComponentRef inSrc;
  input DAE.Exp inDst;
  output VariableReplacements outRepl;
algorithm
  outRepl:=
  matchcontinue (repl,inSrc,inDst)
    local
      DAE.ComponentRef src;
      DAE.Exp dst,olddst;
      HashTable2.HashTable ht,ht_1,eht,eht_1;
      HashTable3.HashTable invHt,invHt_1;
      list<DAE.Ident> iv;
      Option<HashTable2.HashTable> derConst;
    case ((REPLACEMENTS(hashTable=ht)),src,dst) /* source dest */
      equation
        olddst = BaseHashTable.get(src,ht) "if rule a->b exists, fail" ;
      then
        fail();
    case ((REPLACEMENTS(ht,invHt,eht,iv,derConst)),src,dst)
      equation
        ht_1 = BaseHashTable.add((src, dst),ht);
        invHt_1 = addReplacementInv(invHt, src, dst);
        eht_1 = addExtendReplacement(eht,src,NONE());
      then
        REPLACEMENTS(ht_1,invHt_1,eht_1,iv,derConst);
    case (_,_,_)
      equation
        print("-add_replacement failed for " +& ComponentReference.printComponentRefStr(inSrc) +& " = " +& ExpressionDump.printExpStr(inDst) +& "\n");
      then
        fail();
  end matchcontinue;
end addReplacementNoTransitive;

protected function addReplacementInv "function: addReplacementInv

  Helper function to addReplacement
  Adds the inverse rule of a replacement to the second binary tree
  of VariableReplacements.
"
  input HashTable3.HashTable invHt;
  input DAE.ComponentRef src;
  input DAE.Exp dst;
  output HashTable3.HashTable outInvHt;
algorithm
  outInvHt:=
  match (invHt,src,dst)
    local
      HashTable3.HashTable invHt_1;
      HashSet.HashSet set;
      list<DAE.ComponentRef> dests;
    case (_,_,_) equation
      ((_,set)) = Expression.traverseExpTopDown(dst, traversingCrefFinder, HashSet.emptyHashSet());
      dests = BaseHashSet.hashSetList(set);
      invHt_1 = List.fold1r(dests,addReplacementInv2,src,invHt);
      then
        invHt_1;
  end match;
end addReplacementInv;

protected function traversingCrefFinder "
Author: Frenkel 2012-12"
  input tuple<DAE.Exp, HashSet.HashSet > inExp;
  output tuple<DAE.Exp, Boolean, HashSet.HashSet > outExp;
algorithm
  outExp := matchcontinue(inExp)
    local
      DAE.Exp e;
      DAE.ComponentRef cr;
      HashSet.HashSet set;
    case((e as DAE.CREF(DAE.CREF_IDENT(ident = "time",subscriptLst = {}),_), set))
      then ((e,false,set));
    case((e as DAE.CREF(componentRef = cr), set))
      equation
        set = BaseHashSet.add(cr,set);
      then ((e,false,set));
    case((e,set)) then ((e,true,set));
  end matchcontinue;
end traversingCrefFinder;


protected function addReplacementInv2 "function: addReplacementInv2

  Helper function to addReplacementInv
  Adds the inverse rule for one of the variables of a replacement to the second binary tree
  of VariableReplacements.
  Since a replacement is on the form var -> expression of vars(v1,v2,...,vn) the inverse binary tree
  contains rules for v1 -> var, v2 -> var, ...., vn -> var so that any of the variables of the expression
  will update the rule.
"
  input HashTable3.HashTable invHt;
  input DAE.ComponentRef dst;
  input DAE.ComponentRef src;
  output HashTable3.HashTable outInvHt;
algorithm
  outInvHt:=
  matchcontinue (invHt,dst,src)
    local
      HashTable3.HashTable invHt_1;
      list<DAE.ComponentRef> srcs;
    case (_,_,_)
      equation
        failure(_ = BaseHashTable.get(dst,invHt)) "No previous elt for dst -> src" ;
        invHt_1 = BaseHashTable.add((dst, {src}),invHt);
      then
        invHt_1;
    case (_,_,_)
      equation
        srcs = BaseHashTable.get(dst,invHt) "previous elt for dst -> src, append.." ;
        srcs = src::srcs;
        invHt_1 = BaseHashTable.add((dst, srcs),invHt);
      then
        invHt_1;
  end matchcontinue;
end addReplacementInv2;

protected function makeTransitive "function: makeTransitive

  This function takes a set of replacement rules and a new replacement rule
  in the form of two ComponentRef:s and makes sure the new replacement rule
  is replaced with the transitive value.
  For example, if we have the rule a->b and a new rule c->a it is changed to c->b.
  Also, if we have a rule a->b and a new rule b->c then the -old- rule a->b is changed
  to a->c.
  For arbitrary expressions: if we have a rule ax-> expr(b1,..,bn) and a new rule c->expr(a1,ax,..,an)
  it is changed to c-> expr(a1,expr(b1,...,bn),..,an).
  And similary for a rule ax -> expr(b1,bx,..,bn) and a new rule bx->expr(c1,..,cn) then old rule is changed to
  ax -> expr(b1,expr(c1,..,cn),..,bn).
"
  input VariableReplacements repl;
  input DAE.ComponentRef src;
  input DAE.Exp dst;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output VariableReplacements outRepl;
  output DAE.ComponentRef outSrc;
  output DAE.Exp outDst;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outRepl,outSrc,outDst):=
  match (repl,src,dst,inFuncTypeExpExpToBooleanOption)
    local
      VariableReplacements repl_1,repl_2;
      DAE.ComponentRef src_1,src_2;
      DAE.Exp dst_1,dst_2,dst_3;

    case (_,_,_,_)
      equation
        (repl_1,src_1,dst_1) = makeTransitive1(repl, src, dst,inFuncTypeExpExpToBooleanOption);
        (repl_2,src_2,dst_2) = makeTransitive2(repl_1, src_1, dst_1,inFuncTypeExpExpToBooleanOption);
        (dst_3,_) = ExpressionSimplify.simplify1(dst_2) "to remove e.g. --a";
      then
        (repl_2,src_2,dst_3);
  end match;
end makeTransitive;

protected function makeTransitive1 "function: makeTransitive1

  helper function to makeTransitive
"
  input VariableReplacements repl;
  input DAE.ComponentRef src;
  input DAE.Exp dst;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output VariableReplacements outRepl;
  output DAE.ComponentRef outSrc;
  output DAE.Exp outDst;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outRepl,outSrc,outDst):=
  matchcontinue (repl,src,dst,inFuncTypeExpExpToBooleanOption)
    local
      list<DAE.ComponentRef> lst;
      VariableReplacements repl_1,singleRepl;
      HashTable3.HashTable invHt;
      // old rule a->expr(b1,..,bn) must be updated to a->expr(c_exp,...,bn) when new rule b1->c_exp
      // is introduced
    case ((REPLACEMENTS(invHashTable=invHt)),_,_,_)
      equation
        lst = BaseHashTable.get(src, invHt);
        singleRepl = addReplacementNoTransitive(emptyReplacementsSized(53),src,dst);
        repl_1 = makeTransitive12(lst,repl,singleRepl,inFuncTypeExpExpToBooleanOption,HashSet.emptyHashSet());
      then
        (repl_1,src,dst);
    else then (repl,src,dst);
  end matchcontinue;
end makeTransitive1;

protected function makeTransitive12 "Helper function to makeTransitive1
For each old rule a->expr(b1,..,bn) update dest by applying the new rule passed as argument
in singleRepl."
  input list<DAE.ComponentRef> lst;
  input VariableReplacements repl;
  input VariableReplacements singleRepl "contain one replacement rule: the rule to be added";
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input HashSet.HashSet inSet "to avoid touble work";
  output VariableReplacements outRepl;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  outRepl := matchcontinue(lst,repl,singleRepl,inFuncTypeExpExpToBooleanOption,inSet)
    local
      DAE.Exp crDst;
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crs;
      VariableReplacements repl1;
      HashTable2.HashTable ht;
      HashSet.HashSet set;
    case({},_,_,_,_) then repl;
    case(cr::crs,REPLACEMENTS(hashTable=ht),_,_,_)
      equation
        false = BaseHashSet.has(cr,inSet);
        set = BaseHashSet.add(cr,inSet);
        crDst = BaseHashTable.get(cr,ht);
        (crDst,_) = replaceExp(crDst,singleRepl,inFuncTypeExpExpToBooleanOption);
        repl1 = addReplacementNoTransitive(repl,cr,crDst) "add updated old rule";
      then
        makeTransitive12(crs,repl1,singleRepl,inFuncTypeExpExpToBooleanOption,set);
    case(_::crs,_,_,_,_)
      then
        makeTransitive12(crs,repl,singleRepl,inFuncTypeExpExpToBooleanOption,inSet);
  end matchcontinue;
end makeTransitive12;

protected function makeTransitive2 "function: makeTransitive2

  Helper function to makeTransitive
"
  input VariableReplacements repl;
  input DAE.ComponentRef src;
  input DAE.Exp dst;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output VariableReplacements outRepl;
  output DAE.ComponentRef outSrc;
  output DAE.Exp outDst;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outRepl,outSrc,outDst):=
  matchcontinue (repl,src,dst,inFuncTypeExpExpToBooleanOption)
    local
      DAE.Exp dst_1;
      // for rule a->b1+..+bn, replace all b1 to bn's in the expression;
    case (_,_,_,_)
      equation
        (dst_1,_) = replaceExp(dst,repl,inFuncTypeExpExpToBooleanOption);
      then
        (repl,src,dst_1);
        // replace Exp failed, keep old rule.
    case (_,_,_,_) then (repl,src,dst);  /* dst has no own replacement, return */
  end matchcontinue;
end makeTransitive2;

protected function addExtendReplacement
"function: addExtendReplacement
  author: Frenkel TUD 2011-04
  checks if the parents of cref from type array or record
  and add a rule to extend them."
  input HashTable2.HashTable extendrepl;
  input DAE.ComponentRef cr;
  input Option<DAE.ComponentRef> preCr;
  output HashTable2.HashTable outExtendrepl;
algorithm
  outExtendrepl:=
  matchcontinue (extendrepl,cr,preCr)
    local
      HashTable2.HashTable erepl,erepl1;
      DAE.ComponentRef subcr,precr,precr1,pcr,precrn,precrn1;
      DAE.Ident ident;
      DAE.Type ty;
      list<DAE.Subscript> subscriptLst;
      list<DAE.Var> varLst;
      list<DAE.ComponentRef> crefs;
      String s;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty as DAE.T_ARRAY(ty=_)),NONE())
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        failure(_ = BaseHashTable.get(precr,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr, DAE.RCONST(0.0)),extendrepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty as DAE.T_ARRAY(ty=_)),SOME(pcr))
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        precr1 = ComponentReference.joinCrefs(pcr,precr);
        failure(_ = BaseHashTable.get(precr1,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr1, DAE.RCONST(0.0)),extendrepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty as DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(_),varLst=varLst)),NONE())
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        failure(_ = BaseHashTable.get(precr,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr, DAE.RCONST(0.0)),extendrepl);
        // Create a list of crefs from names
        crefs =  List.map(varLst,ComponentReference.creffromVar);
        erepl = List.fold1r(crefs,addExtendReplacement,SOME(precr),erepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty as DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(_),varLst=varLst),subscriptLst=subscriptLst),SOME(pcr))
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        precr1 = ComponentReference.joinCrefs(pcr,cr);
        failure(_ = BaseHashTable.get(precr1,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr1, DAE.RCONST(0.0)),extendrepl);
        // Create a list of crefs from names
        crefs =  List.map(varLst,ComponentReference.creffromVar);
        erepl = List.fold1r(crefs,addExtendReplacement,SOME(precr1),erepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty,subscriptLst=_::_),NONE())
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        failure(_ = BaseHashTable.get(precr,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr, DAE.RCONST(0.0)),extendrepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=ident,identType=ty,subscriptLst=_::_),SOME(pcr))
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        precr1 = ComponentReference.joinCrefs(pcr,precr);
        failure(_ = BaseHashTable.get(precr1,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr1, DAE.RCONST(0.0)),extendrepl);
      then erepl;
    case (_,DAE.CREF_IDENT(ident=_),_)
      then
        extendrepl;
    case (_,DAE.CREF_QUAL(ident=ident,identType=ty,subscriptLst=subscriptLst,componentRef=subcr),NONE())
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        failure(_ = BaseHashTable.get(precr,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr, DAE.RCONST(0.0)),extendrepl);
        precrn = ComponentReference.makeCrefIdent(ident,ty,subscriptLst);
        erepl1 = addExtendReplacement(erepl,subcr,SOME(precrn));
      then erepl1;
    case (_,DAE.CREF_QUAL(ident=ident,identType=ty,subscriptLst=subscriptLst,componentRef=subcr),SOME(pcr))
      equation
        precr = ComponentReference.makeCrefIdent(ident,ty,{});
        precr1 = ComponentReference.joinCrefs(pcr,precr);
        failure(_ = BaseHashTable.get(precr1,extendrepl));
        // update Replacements
        erepl = BaseHashTable.add((precr1, DAE.RCONST(0.0)),extendrepl);
        precrn = ComponentReference.makeCrefIdent(ident,ty,subscriptLst);
        precrn1 = ComponentReference.joinCrefs(pcr,precrn);
        erepl1 = addExtendReplacement(erepl,subcr,SOME(precrn1));
      then erepl1;
    // all other
    case (_,DAE.CREF_QUAL(ident=ident,identType=ty,subscriptLst=subscriptLst,componentRef=subcr),NONE())
      equation
        precrn = ComponentReference.makeCrefIdent(ident,ty,subscriptLst);
        erepl = addExtendReplacement(extendrepl,subcr,SOME(precrn));
      then erepl;
    case (_,DAE.CREF_QUAL(ident=ident,identType=ty,subscriptLst=subscriptLst,componentRef=subcr),SOME(pcr))
      equation
        precrn = ComponentReference.makeCrefIdent(ident,ty,subscriptLst);
        precrn1 = ComponentReference.joinCrefs(pcr,precrn);
        erepl = addExtendReplacement(extendrepl,subcr,SOME(precrn1));
      then erepl;
    case (_,_,_)
      equation
        s = ComponentReference.printComponentRefStr(cr);
        Debug.fprintln(Flags.FAILTRACE, "- BackendVarTransform.addExtendReplacement failed for " +& s);
      then extendrepl;
  end matchcontinue;
end addExtendReplacement;

protected function addIterationVar
"function addRiterationVar
  add a var to the iterationVars"
  input VariableReplacements repl;
  input DAE.Ident inVar;
  output VariableReplacements outRepl;
algorithm
  outRepl:=
  match (repl,inVar)
    local
      HashTable2.HashTable ht,eht;
      HashTable3.HashTable invHt;
      list<DAE.Ident> iv;
      Option<HashTable2.HashTable> derConst;
    case (REPLACEMENTS(ht,invHt,eht,iv,derConst),_)
      then
        REPLACEMENTS(ht,invHt,eht,inVar::iv,derConst);
  end match;
end addIterationVar;

protected function removeIterationVar
"function removeiterationVar
  remove the first equal var from the iterationVars"
  input VariableReplacements repl;
  input DAE.Ident inVar;
  output VariableReplacements outRepl;
algorithm
  outRepl:=
  match (repl,inVar)
    local
      HashTable2.HashTable ht,eht;
      HashTable3.HashTable invHt;
      list<DAE.Ident> iv;
      Option<HashTable2.HashTable> derConst;
    case (REPLACEMENTS(ht,invHt,eht,iv,derConst),_)
      equation
        iv = removeFirstOnTrue(iv,stringEq,inVar,{});
      then
        REPLACEMENTS(ht,invHt,eht,iv,derConst);
  end match;
end removeIterationVar;

protected function isIterationVar
"function isIterationVar
  remove true if it is an iteration var"
  input VariableReplacements repl;
  input DAE.Ident inVar;
  output Boolean is;
algorithm
  is:=
  match (repl,inVar)
    local
      list<DAE.Ident> iv;
    case (REPLACEMENTS(iterationVars=iv),_)
      then
        listMember(inVar, iv);
  end match;
end isIterationVar;

protected function removeFirstOnTrue
  input list<ArgType1> iLst;
  input CompFunc func;
  input ArgType2 value;
  input list<ArgType1> iAcc;
  output list<ArgType1> oAcc;
  partial function CompFunc
    input ArgType1 inElement;
    input ArgType2 value;
    output Boolean outIsEqual;
  end CompFunc;
  replaceable type ArgType1 subtypeof Any;
  replaceable type ArgType2 subtypeof Any;
algorithm
  oAcc := matchcontinue(iLst,func,value,iAcc)
    local
      ArgType1 arg;
      list<ArgType1> arglst;

    case ({},_,_,_) then listReverse(iAcc);
    case (arg::arglst,_,_,_)
      equation
        true = func(arg,value);
      then
        listAppend(listReverse(iAcc),arglst);
    case (arg::arglst,_,_,_)
      then
        removeFirstOnTrue(arglst,func,value,arg::iAcc);
  end matchcontinue;
end removeFirstOnTrue;

public function addDerConstRepl
"function addDerConstRepl
  add a var to the derConst replacements, replace der(const) with 0.0"
  input DAE.ComponentRef inComponentRef;
  input DAE.Exp inExp;
  input VariableReplacements repl;
  output VariableReplacements outRepl;
algorithm
  outRepl:= match (inComponentRef,inExp,repl)
    local
      HashTable2.HashTable ht,eht;
      HashTable3.HashTable invHt;
      list<DAE.Ident> iv;
      HashTable2.HashTable derConst;
    case (_,_,REPLACEMENTS(ht,invHt,eht,iv,NONE()))
      equation
        derConst = HashTable2.emptyHashTable();
        derConst = BaseHashTable.add((inComponentRef,inExp),derConst);
      then
        REPLACEMENTS(ht,invHt,eht,iv,SOME(derConst));
    case (_,_,REPLACEMENTS(ht,invHt,eht,iv,SOME(derConst)))
      equation
        derConst = BaseHashTable.add((inComponentRef,inExp),derConst);
      then
        REPLACEMENTS(ht,invHt,eht,iv,SOME(derConst));
  end match;
end addDerConstRepl;

public function getReplacement "function: getReplacement

  Retrives a replacement variable given a set of replacement rules and a
  source variable.
"
  input VariableReplacements inVariableReplacements;
  input DAE.ComponentRef inComponentRef;
  output DAE.Exp outComponentRef;
algorithm
  outComponentRef:=
  match (inVariableReplacements,inComponentRef)
    local
      DAE.ComponentRef src;
      DAE.Exp dst;
      HashTable2.HashTable ht;
    case (REPLACEMENTS(hashTable=ht),src)
      equation
        dst = BaseHashTable.get(src,ht);
      then
        dst;
  end match;
end getReplacement;

public function getAllReplacements "
Author BZ 2009-04
Extract all crefs -> exp to two separate lists.
"
input VariableReplacements inVariableReplacements;
output list<DAE.ComponentRef> crefs;
output list<DAE.Exp> dsts;
algorithm (crefs,dsts) := match (inVariableReplacements)
    local
      HashTable2.HashTable ht;
      list<tuple<DAE.ComponentRef,DAE.Exp>> tplLst;
    case (REPLACEMENTS(hashTable = ht))
      equation
        tplLst = BaseHashTable.hashTableList(ht);
        crefs = List.map(tplLst,Util.tuple21);
        dsts = List.map(tplLst,Util.tuple22);
      then
        (crefs,dsts);
  end match;
end getAllReplacements;

public function getExtendReplacement "function: getExtendReplacement

  Retrives a replacement variable given a set of replacement rules and a
  source variable.
"
  input VariableReplacements inVariableReplacements;
  input DAE.ComponentRef inComponentRef;
  output DAE.Exp outComponentRef;
algorithm
  outComponentRef:=
  match (inVariableReplacements,inComponentRef)
    local
      DAE.ComponentRef src, src_1;
      DAE.Exp dst;
      HashTable2.HashTable ht;
    case (REPLACEMENTS(extendhashTable=ht),src)
      equation
        src_1 = ComponentReference.crefStripLastSubs(src);
        dst = BaseHashTable.get(src_1,ht);
      then
        dst;
  end match;
end getExtendReplacement;

protected function avoidDoubleHashLookup "
Author BZ 200X-XX modified 2008-06
When adding replacement rules, we might not have the correct type availible at the moment.
Then DAE.T_UNKNOWN_DEFAULT is used, so when replacing exp and finding DAE.T_UNKNOWN_DEFAULT, we use the
type of the expression to be replaced instead.
TODO: find out why array residual functions containing arrays as xloc[] does not work,
      doing that will allow us to use this function for all crefs."
  input DAE.Exp inExp;
  input DAE.Type inType;
  output DAE.Exp outExp;
algorithm  outExp := matchcontinue(inExp,inType)
  local DAE.ComponentRef cr;
  case(DAE.CREF(cr,DAE.T_UNKNOWN(source = _)),_) then Expression.makeCrefExp(cr,inType);
  case (_,_) then inExp;
  end matchcontinue;
end avoidDoubleHashLookup;


public function replacementEmpty
  input VariableReplacements repl;
  output Boolean empty;
algorithm
  empty := match(repl)
    local
      HashTable2.HashTable ht,derConst;
    case REPLACEMENTS(hashTable = ht,derConst=NONE())
      then
        intLt(BaseHashTable.hashTableCurrentSize(ht),1);
    case REPLACEMENTS(derConst=SOME(_)) then false;
  end match;
end replacementEmpty;

public function replacementCurrentSize
  input VariableReplacements repl;
  output Integer size;
protected
  HashTable2.HashTable ht;
algorithm
  REPLACEMENTS(hashTable = ht) := repl;
  size := BaseHashTable.hashTableCurrentSize(ht);
end replacementCurrentSize;

/*********************************************************/
/* replace Expression with condition function */
/*********************************************************/

public function replaceExp "function: replaceExp
  Takes a set of replacement rules and an expression and a function
  giving a boolean value for an expression.
  The function replaces all variables in the expression using
  the replacement rules, if the boolean value is true children of the
  expression is visited (including the expression itself). If it is false,
  no replacemet is performed."
  input DAE.Exp inExp;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output DAE.Exp outExp;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outExp,replacementPerformed) :=
  matchcontinue (inExp,inVariableReplacements,inFuncTypeExpExpToBooleanOption)
    local
      DAE.ComponentRef cr;
      DAE.Exp e,e1_1,e2_1,e1,e2,e3_1,e3;
      DAE.Type t,tp,ety;
      VariableReplacements repl;
      Option<FuncTypeExp_ExpToBoolean> cond;
      DAE.Operator op;
      list<DAE.Exp> expl_1,expl;
      Absyn.Path path;
      Boolean c,c1,c2,c3;
      Integer b,i;
      Absyn.CodeNode a;
      list<list<DAE.Exp>> bexpl_1,bexpl;
      Integer index_;
      Option<tuple<DAE.Exp,Integer,Integer>> isExpisASUB;
      DAE.ReductionInfo reductionInfo;
      DAE.ReductionIterators iters;
      DAE.CallAttributes attr;
      DAE.Ident ident;
      HashTable2.HashTable derConst;

      // Note: Most of these functions check if a subexpression did a replacement.
      // If it did not, we do not create a new copy of the expression (to save some memory).
    case (e as DAE.CREF(componentRef = DAE.CREF_IDENT(ident=ident)),repl,cond)
      equation
        true = isIterationVar(repl, ident);
      then
        (e,false);
    case ((e as DAE.CREF(componentRef = cr,ty = t)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (cr,_) = replaceCrefSubs(cr,repl,cond);
        e1 = getExtendReplacement(repl, cr);
        ((e2,(_,true))) = BackendDAEUtil.extendArrExp((e,(NONE(),false)));
        (e3,_) = replaceExp(e2,repl,cond);
      then
        (e3,true);
    case ((e as DAE.CREF(componentRef = cr,ty = t)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (cr,_) = replaceCrefSubs(cr,repl,cond);
        e1 = getReplacement(repl, cr);
        e2 = avoidDoubleHashLookup(e1,t);
      then
        (e2,true);
    case ((e as DAE.CREF(componentRef = cr,ty = t)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (cr,true) = replaceCrefSubs(cr,repl,cond);
      then (DAE.CREF(cr,t),true);
    case ((e as DAE.BINARY(exp1 = e1,operator = op,exp2 = e2)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        true = c1 or c2;
      then
        (DAE.BINARY(e1_1,op,e2_1),true);
    case ((e as DAE.LBINARY(exp1 = e1,operator = op,exp2 = e2)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        true = c1 or c2;
      then
        (DAE.LBINARY(e1_1,op,e2_1),true);
    case ((e as DAE.UNARY(operator = op,exp = e1)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,true) = replaceExp(e1, repl, cond);
      then
        (DAE.UNARY(op,e1_1),true);
    case ((e as DAE.LUNARY(operator = op,exp = e1)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,true) = replaceExp(e1, repl, cond);
      then
        (DAE.LUNARY(op,e1_1),true);
    case (DAE.RELATION(exp1 = e1,operator = op,exp2 = e2, index=index_, optionExpisASUB= isExpisASUB),repl,cond)
      equation
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        true = c1 or c2;
      then
        (DAE.RELATION(e1_1,op,e2_1,index_,isExpisASUB),true);
    case ((e as DAE.IFEXP(expCond = e1,expThen = e2,expElse = e3)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        (e3_1,c3) = replaceExp(e3, repl, cond);
        true = c1 or c2 or c3;
      then
        (DAE.IFEXP(e1_1,e2_1,e3_1),true);
    case (DAE.CALL(path = Absyn.IDENT(name = "der"),expLst={e1 as DAE.CREF(componentRef = cr,ty=t)}),REPLACEMENTS(derConst=SOME(derConst)),cond)
      equation
        e = BaseHashTable.get(cr,derConst);
        (e,_) = replaceExp(e, inVariableReplacements, cond);
      then
        (e,true);
    case ((e as DAE.CALL(path = path,expLst = expl,attr = attr)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (expl_1,true) = replaceExpList(expl, repl, cond, {}, false);
      then
        (DAE.CALL(path,expl_1,attr),true);
    case ((e as DAE.PARTEVALFUNCTION(path = path,expList = expl,ty = tp)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (expl_1,true) = replaceExpList(expl, repl, cond, {}, false);
      then
        (DAE.PARTEVALFUNCTION(path,expl_1,tp),true);
    case ((e as DAE.ARRAY(ty = tp,scalar = c,array = expl)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (expl_1,true) = replaceExpList(expl, repl, cond, {}, false);
      then
        (DAE.ARRAY(tp,c,expl_1),true);
    case ((e as DAE.MATRIX(ty = t,integer = b,matrix = bexpl)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (bexpl_1,true) = replaceExpMatrix(bexpl, repl, cond, {}, false);
      then
        (DAE.MATRIX(t,b,bexpl_1),true);
    case ((e as DAE.RANGE(ty = tp,start = e1,step = NONE(),stop = e2)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        true = c1 or c2;
      then
        (DAE.RANGE(tp,e1_1,NONE(),e2_1),true);
    case ((e as DAE.RANGE(ty = tp,start = e1,step = SOME(e3),stop = e2)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        (e3_1,c3) = replaceExp(e3, repl, cond);
        true = c1 or c2 or c3;
      then
        (DAE.RANGE(tp,e1_1,SOME(e3_1),e2_1),true);
    case ((e as DAE.TUPLE(PR = expl)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (expl_1,true) = replaceExpList(expl, repl, cond, {}, false);
      then
        (DAE.TUPLE(expl_1),true);
    case ((e as DAE.CAST(ty = tp,exp = e1)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,true) = replaceExp(e1, repl, cond);
      then
        (DAE.CAST(tp,e1_1),true);
    case ((e as DAE.ASUB(exp = e1,sub = expl)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (expl,true) = replaceExpList(expl, repl, cond, {}, c1);
      then
        (Expression.makeASUB(e1_1,expl),true);
    case ((e as DAE.TSUB(exp = e1,ix = i, ty = tp)),repl,cond)
      equation
        true = replaceExpCond(cond, e1);
        (e1_1,true) = replaceExp(e1, repl, cond);
      then
        (DAE.TSUB(e1_1,i,tp),true);
    case ((e as DAE.SIZE(exp = e1,sz = SOME(e2))),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (e2_1,c2) = replaceExp(e2, repl, cond);
        true = c1 or c2;
      then
        (DAE.SIZE(e1_1,SOME(e2_1)),true);
    case (DAE.CODE(code = a,ty = tp),repl,cond)
      equation
        print("replace_exp on CODE not impl.\n");
      then
        (DAE.CODE(a,tp),false);
    case ((e as DAE.REDUCTION(reductionInfo = reductionInfo,expr = e1,iterators = iters)),repl,cond)
      equation
        true = replaceExpCond(cond, e);
        (e1_1,c1) = replaceExp(e1, repl, cond);
        (iters,true) = replaceExpIters(iters, repl, cond, {}, false);
      then (DAE.REDUCTION(reductionInfo,e1_1,iters),true);
    case (e,repl,cond)
      then (e,false);
  end matchcontinue;
end replaceExp;

protected function replaceCrefSubs
  input DAE.ComponentRef inCref;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> cond;
  output DAE.ComponentRef outCr;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outCr,replacementPerformed) := match (inCref,repl,cond)
    local
      String name;
      DAE.ComponentRef cr,cr_1;
      DAE.Type ty;
      list<DAE.Subscript> subs,subs_1;
      Boolean c1,c2;

    case (DAE.CREF_QUAL(ident = name, identType = ty, subscriptLst = subs, componentRef = cr), _, _)
      equation
        (subs_1, c1) = replaceCrefSubs2(subs, repl, cond);
        (cr_1, c2) = replaceCrefSubs(cr, repl, cond);
        subs = Util.if_(c1,subs_1,subs);
        cr = Util.if_(c2,cr_1,cr);
        cr = Util.if_(c1 or c2,DAE.CREF_QUAL(name, ty, subs, cr),inCref);
      then
        (cr, c1 or c2);

    case (DAE.CREF_IDENT(ident = name, identType = ty, subscriptLst = subs), _, _)
      equation
        (subs, c1) = replaceCrefSubs2(subs, repl, cond);
        cr = Util.if_(c1,DAE.CREF_IDENT(name, ty, subs),inCref);
      then
        (cr, c1);

    else (inCref,false);
  end match;
end replaceCrefSubs;

protected function replaceCrefSubs2
  input list<DAE.Subscript> isubs;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> cond;
  output list<DAE.Subscript> outSubs;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outSubs,replacementPerformed) := match (isubs,repl,cond)
    local
      DAE.Exp exp;
      Boolean c1,c2;
      list<DAE.Subscript> subs;

    case ({},_,_) then ({},false);
    case (DAE.WHOLEDIM()::subs, _, _)
      equation
        (subs,c1) = replaceCrefSubs2(subs,repl,cond);
      then (DAE.WHOLEDIM()::subs, c1);

    case (DAE.SLICE(exp = exp)::subs, _, _)
      equation
        (exp,c2) = replaceExp(exp, repl, cond);
        (subs,c1) = replaceCrefSubs2(subs,repl,cond);
      then
        (DAE.SLICE(exp)::subs, c1 or c2);

    case (DAE.INDEX(exp = exp)::subs, _, _)
      equation
        (exp,c2) = replaceExp(exp, repl, cond);
        (subs,c1) = replaceCrefSubs2(subs,repl,cond);
      then
        (DAE.INDEX(exp)::subs, c1 or c2);

    case (DAE.WHOLE_NONEXP(exp = exp)::subs, _, _)
      equation
        (exp,c2) = replaceExp(exp, repl, cond);
        (subs,c1) = replaceCrefSubs2(subs,repl,cond);
      then
        (DAE.WHOLE_NONEXP(exp)::subs, c1 or c2);

  end match;
end replaceCrefSubs2;

public function replaceExpList
  input list<DAE.Exp> iexpl;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> cond;
  input list<DAE.Exp> iacc1;
  input Boolean iacc2;
  output list<DAE.Exp> outExpl;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outExpl,replacementPerformed) := match (iexpl,repl,cond,iacc1,iacc2)
    local
      DAE.Exp exp;
      Boolean c,acc2;
      list<DAE.Exp> expl, acc1;

    case ({},_,_,acc1,acc2) then (listReverse(acc1),acc2);
    case (exp::expl,_,_,acc1,acc2)
      equation
        (exp,c) = replaceExp(exp,repl,cond);
        (acc1,acc2) = replaceExpList(expl,repl,cond,exp::acc1,c or acc2);
      then (acc1,acc2);
  end match;
end replaceExpList;

public function replaceExpList1
  input list<DAE.Exp> iexpl;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> cond;
  input list<DAE.Exp> iacc1;
  input list<Boolean> iacc2;
  output list<DAE.Exp> outExpl;
  output list<Boolean> replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outExpl,replacementPerformed) := match (iexpl,repl,cond,iacc1,iacc2)
    local
      DAE.Exp exp;
      Boolean c;
      list<Boolean> acc2;
      list<DAE.Exp> expl, acc1;

    case ({},_,_,acc1,acc2) then (listReverse(acc1),listReverse(acc2));
    case (exp::expl,_,_,acc1,acc2)
      equation
        (exp,c) = replaceExp(exp,repl,cond);
        (acc1,acc2) = replaceExpList1(expl,repl,cond,exp::acc1,c::acc2);
      then (acc1,acc2);
  end match;
end replaceExpList1;


protected function replaceExpIters
  input list<DAE.ReductionIterator> inIters;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> cond;
  input list<DAE.ReductionIterator> inAcc1;
  input Boolean inAcc2;
  output list<DAE.ReductionIterator> outIter;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outIter,replacementPerformed) := matchcontinue (inIters,repl,cond,inAcc1,inAcc2)
    local
      String id;
      DAE.Exp exp,gexp;
      DAE.Type ty;
      Boolean b1,b2;
      DAE.ReductionIterator iter;
      list<DAE.ReductionIterator> iters;
      list<DAE.ReductionIterator> acc1;
      Boolean acc2;

    case ({},_,_,acc1,acc2) then (listReverse(acc1),acc2);
    case (DAE.REDUCTIONITER(id,exp,NONE(),ty)::iters,_,_,acc1,_)
      equation
        (exp,true) = replaceExp(exp, repl, cond);
        (iters,_) = replaceExpIters(iters,repl,cond,DAE.REDUCTIONITER(id,exp,NONE(),ty)::acc1,true);
      then (iters,true);
    case (DAE.REDUCTIONITER(id,exp,SOME(gexp),ty)::iters,_,_,acc1,acc2)
      equation
        (exp,b1) = replaceExp(exp, repl, cond);
        (gexp,b2) = replaceExp(gexp, repl, cond);
        true = b1 or b2;
        (iters,_) = replaceExpIters(iters,repl,cond,DAE.REDUCTIONITER(id,exp,SOME(gexp),ty)::acc1,true);
      then (iters,true);
    case (iter::iters,_,_,acc1,acc2)
      equation
        (iters,acc2) = replaceExpIters(iters,repl,cond,iter::acc1,acc2);
      then (iters,acc2);
  end matchcontinue;
end replaceExpIters;

protected function replaceExpCond "function replaceExpCond(cond,e) => true &
  Helper function to replace_Expression. Evaluates a condition function if
  SOME otherwise returns true."
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input DAE.Exp inExp;
  output Boolean outBoolean;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  outBoolean:=
  match (inFuncTypeExpExpToBooleanOption,inExp)
    local
      Boolean res;
      FuncTypeExp_ExpToBoolean cond;
      DAE.Exp e;
    case (SOME(cond),e) /* cond e */
      equation
        res = cond(e);
      then
        res;
    case (NONE(),_) then true;
  end match;
end replaceExpCond;

protected function replaceExpMatrix "function: replaceExpMatrix
  author: PA
  Helper function to replaceExp, traverses Matrix expression list."
  input list<list<DAE.Exp>> inTplExpExpBooleanLstLst;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input list<list<DAE.Exp>> iacc1;
  input Boolean iacc2;
  output list<list<DAE.Exp>> outTplExpExpBooleanLstLst;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outTplExpExpBooleanLstLst,replacementPerformed) :=
  match (inTplExpExpBooleanLstLst,inVariableReplacements,inFuncTypeExpExpToBooleanOption,iacc1,iacc2)
    local
      VariableReplacements repl;
      Option<FuncTypeExp_ExpToBoolean> cond;
      list<DAE.Exp> e_1,e;
      list<list<DAE.Exp>> es;
      list<list<DAE.Exp>> acc1;
      Boolean acc2;

    case ({},repl,cond,acc1,acc2) then (listReverse(acc1),acc2);
    case ((e :: es),repl,cond,acc1,acc2)
      equation
        (e_1,acc2) = replaceExpList(e, repl, cond, {}, acc2);
        (acc1,acc2) = replaceExpMatrix(es, repl, cond, e_1::acc1, acc2);
      then
        (acc1,acc2);
  end match;
end replaceExpMatrix;

/*********************************************************/
/* condition function for replace Expression  */
/*********************************************************/

public function skipPreOperator "function: skipPreOperator
  The variable/exp in the pre operator should not be replaced.
  This function is passed to replace_exp to ensure this."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    case (DAE.CALL(path = Absyn.IDENT(name = "pre"))) then false;
    case (_) then true;
  end matchcontinue;
end skipPreOperator;

public function skipPreChangeEdgeOperator "function: skipPreChangeEdgeOperator
  The variable/exp in the pre/change/edge operator should not be replaced.
  This function is passed to replace_exp to ensure this."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    local
      DAE.ComponentRef cr;
    case DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {DAE.CREF(componentRef=cr)}) then selfGeneratedVar(cr);
    case DAE.CALL(path = Absyn.IDENT(name = "change"),expLst = {DAE.CREF(componentRef=cr)}) then selfGeneratedVar(cr);
    case DAE.CALL(path = Absyn.IDENT(name = "edge"),expLst = {DAE.CREF(componentRef=cr)}) then selfGeneratedVar(cr);
    case DAE.CALL(path = Absyn.IDENT(name = "pre")) then false;
    case DAE.CALL(path = Absyn.IDENT(name = "change")) then false;
    case DAE.CALL(path = Absyn.IDENT(name = "edge")) then false;
    case (_) then true;
  end matchcontinue;
end skipPreChangeEdgeOperator;

protected function selfGeneratedVar
  input DAE.ComponentRef inCref;
  output Boolean b;
algorithm
  b := match(inCref)
    case DAE.CREF_QUAL(ident = "$ZERO") then true;
    case DAE.CREF_QUAL(ident = "$_DER") then true;
    case DAE.CREF_QUAL(ident = "$pDER") then true;
    // keep same a while untill we know which are needed
    //case DAE.CREF_QUAL(ident = "$DER") then true;
    else then false;
  end match;
end selfGeneratedVar;

/*********************************************************/
/* replace Equations  */
/*********************************************************/

public function replaceEquationsArr
"function: replaceEquationsArr
  This function takes a list of equations ana a set of variable
  replacements and applies the replacements on all equations.
  The function returns the updated list of equations"
  input BackendDAE.EquationArray inEqns;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output BackendDAE.EquationArray outEqns;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outEqns,replacementPerformed) := matchcontinue(inEqns,repl,inFuncTypeExpExpToBooleanOption)
    local
      list<BackendDAE.Equation> eqns;
    case(_,_,_)
      equation
        // Do not do empty replacements; it just takes time ;)
        false = replacementEmpty(repl);
        ((_,_,eqns,replacementPerformed)) = BackendEquation.traverseBackendDAEEqns(inEqns,replaceEquationTraverser,(repl,inFuncTypeExpExpToBooleanOption,{},false));
        outEqns = Debug.bcallret1(replacementPerformed,BackendEquation.listEquation,eqns,inEqns);
      then
        (outEqns,replacementPerformed);
    else
      then
        (inEqns,false);
  end matchcontinue;
end replaceEquationsArr;

protected function replaceEquationTraverser
  "Help function to e.g. removeSimpleEquations"
  input tuple<BackendDAE.Equation,tuple<VariableReplacements,Option<FuncTypeExp_ExpToBoolean>,list<BackendDAE.Equation>,Boolean>> inTpl;
  output tuple<BackendDAE.Equation,tuple<VariableReplacements,Option<FuncTypeExp_ExpToBoolean>,list<BackendDAE.Equation>,Boolean>> outTpl;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
protected
  BackendDAE.Equation e;
  VariableReplacements repl;
  Option<FuncTypeExp_ExpToBoolean> optfunc;
  list<BackendDAE.Equation> eqns;
  Boolean b;
algorithm
 (e,(repl,optfunc,eqns,b)) := inTpl;
 (eqns,b) := replaceEquation(e,repl,optfunc,eqns,b);
 outTpl := (e,(repl,optfunc,eqns,b));
end replaceEquationTraverser;

public function replaceEquations
"function: replaceEquations
  This function takes a list of equations ana a set of variable
  replacements and applies the replacements on all equations.
  The function returns the updated list of equations"
  input list<BackendDAE.Equation> inEqns;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output list<BackendDAE.Equation> outEqns;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outEqns,replacementPerformed) := matchcontinue(inEqns,repl,inFuncTypeExpExpToBooleanOption)
    local
      list<BackendDAE.Equation> eqns;
    case(_,_,_)
      equation
        // Do not do empty replacements; it just takes time ;)
        false = replacementEmpty(repl);
        (eqns,replacementPerformed) = replaceEquations2(inEqns,repl,inFuncTypeExpExpToBooleanOption,{},false);
      then
        (eqns,replacementPerformed);
    else
      then
        (inEqns,false);
  end matchcontinue;
end replaceEquations;

protected function replaceEquations2
  input list<BackendDAE.Equation> inBackendDAEEquationLst;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input list<BackendDAE.Equation> inAcc;
  input Boolean iReplacementPerformed;
  output list<BackendDAE.Equation> outBackendDAEEquationLst;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outBackendDAEEquationLst,replacementPerformed) :=
  matchcontinue (inBackendDAEEquationLst,inVariableReplacements,inFuncTypeExpExpToBooleanOption,inAcc,iReplacementPerformed)
    local
      BackendDAE.Equation a;
      list<BackendDAE.Equation> es,acc;
      Boolean b;
    case ({},_,_,_,_) then (listReverse(inAcc),iReplacementPerformed);
    case (a::es,_,_,_,_)
      equation
        (acc,b) = replaceEquation(a,inVariableReplacements,inFuncTypeExpExpToBooleanOption,inAcc,iReplacementPerformed);
        (es,b) = replaceEquations2(es, inVariableReplacements,inFuncTypeExpExpToBooleanOption,acc,b);
      then
        (es,b);
  end matchcontinue;
end replaceEquations2;

protected function replaceEquation
  input BackendDAE.Equation inBackendDAEEquation;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input list<BackendDAE.Equation> inAcc;
  input Boolean iReplacementPerformed;
  output list<BackendDAE.Equation> outBackendDAEEquationLst;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outBackendDAEEquationLst,replacementPerformed) :=
  matchcontinue (inBackendDAEEquation,inVariableReplacements,inFuncTypeExpExpToBooleanOption,inAcc,iReplacementPerformed)
    local
      DAE.Exp e1_1,e2_1,e1_2,e2_2,e1,e2,e_1,e_2,e;
      list<BackendDAE.Equation> es;
      VariableReplacements repl;
      BackendDAE.Equation a;
      DAE.ComponentRef cr;
      Integer size;
      list<DAE.Exp> expl,expl1,expl2;
      BackendDAE.WhenEquation whenEqn,whenEqn1;
      DAE.ElementSource source;
      Boolean b1,b2,b3,diffed;
      list<Integer> dimSize;
      DAE.Algorithm alg;
      list<DAE.Statement> stmts,stmts1;
      list<Boolean> blst;
      list<BackendDAE.Equation> eqns;
      list<list<BackendDAE.Equation>> eqnslst;

    case (BackendDAE.ARRAY_EQUATION(dimSize=dimSize,left = e1,right = e2,source = source,differentiated = diffed),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_1);
        (DAE.EQUALITY_EXPS(e1_2,e2_2),source) = ExpressionSimplify.simplifyAddSymbolicOperation(DAE.EQUALITY_EXPS(e1_1,e2_1),source);
      then
        (BackendDAE.ARRAY_EQUATION(dimSize,e1_2,e2_2,source,diffed)::inAcc,true);
    case (BackendDAE.COMPLEX_EQUATION(size=size,left = e1,right = e2,source = source,differentiated = diffed),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_1);
        (DAE.EQUALITY_EXPS(e1_2,e2_2),source) = ExpressionSimplify.simplifyAddSymbolicOperation(DAE.EQUALITY_EXPS(e1_1,e2_1),source);
      then
        (BackendDAE.COMPLEX_EQUATION(size,e1_2,e2_2,source,diffed)::inAcc,true);
    case (BackendDAE.EQUATION(exp = e1,scalar = e2,source = source,differentiated = diffed),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_1);
        (DAE.EQUALITY_EXPS(e1_2,e2_2),source) = ExpressionSimplify.simplifyAddSymbolicOperation(DAE.EQUALITY_EXPS(e1_1,e2_1),source);
      then
        (BackendDAE.EQUATION(e1_2,e2_2,source,diffed)::inAcc,true);
    case (BackendDAE.ALGORITHM(size=size,alg = alg as DAE.ALGORITHM_STMTS(statementLst = stmts),source = source),repl,_,_,_)
      equation
        (stmts1,true) = replaceStatementLst(stmts,repl,inFuncTypeExpExpToBooleanOption,{},false);
        alg = DAE.ALGORITHM_STMTS(stmts1);
      then
        (BackendDAE.ALGORITHM(size,alg,source)::inAcc,true);
    case (BackendDAE.SOLVED_EQUATION(componentRef = cr,exp = e,source = source,differentiated = diffed),repl,_,_,_)
      equation
        (e_1,true) = replaceExp(e, repl,inFuncTypeExpExpToBooleanOption);
        (e_2,_) = ExpressionSimplify.simplify(e_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(true,source,e,e_2);
      then
        (BackendDAE.SOLVED_EQUATION(cr,e_2,source,diffed)::inAcc,true);
    case (BackendDAE.RESIDUAL_EQUATION(exp = e,source = source,differentiated = diffed),repl,_,_,_)
      equation
        (e_1,true) = replaceExp(e, repl,inFuncTypeExpExpToBooleanOption);
        (e_2,_) = ExpressionSimplify.simplify(e_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(true,source,e,e_2);
      then
        (BackendDAE.RESIDUAL_EQUATION(e_2,source,diffed)::inAcc,true);
    case (BackendDAE.WHEN_EQUATION(size,whenEqn,source),repl,_,_,_)
      equation
        (whenEqn1,source,true) = replaceWhenEquation(whenEqn,repl,inFuncTypeExpExpToBooleanOption,source);
      then
        (BackendDAE.WHEN_EQUATION(size,whenEqn1,source)::inAcc,true);
   case (BackendDAE.IF_EQUATION(conditions=expl, eqnstrue=eqnslst, eqnsfalse=eqns, source = source),repl,_,_,_)
      equation
        (expl1,blst) = replaceExpList1(expl, repl, inFuncTypeExpExpToBooleanOption, {}, {});
        b1 = Util.boolOrList(blst);
        source = DAEUtil.addSymbolicTransformationSubstitutionLst(blst,source,expl,expl1);
        (expl2,blst) = ExpressionSimplify.condsimplifyList1(blst,expl1,{},{});
        source = DAEUtil.addSymbolicTransformationSimplifyLst(blst,source,expl1,expl2);
        (eqnslst,b2) = List.map3Fold(eqnslst,replaceEquations2,repl,inFuncTypeExpExpToBooleanOption,{},false);
        (eqns,b3) = replaceEquations2(eqns,repl,inFuncTypeExpExpToBooleanOption,{},false);
        true = b1 or b2 or b3;
        eqns = optimizeIfEquation(expl2,eqnslst,eqns,{},{},source,inAcc);
      then
        (eqns,true);

    case (a,_,_,_,_) then (a::inAcc,iReplacementPerformed);
  end matchcontinue;
end replaceEquation;

protected function optimizeIfEquation
  input list<DAE.Exp> conditions;
  input list<list<BackendDAE.Equation>> theneqns;
  input list<BackendDAE.Equation> elseenqs;
  input list<DAE.Exp> conditions1;
  input list<list<BackendDAE.Equation>> theneqns1;
  input DAE.ElementSource source;
  input list<BackendDAE.Equation> inEqns;
  output list<BackendDAE.Equation> outEqns;
algorithm
  outEqns := matchcontinue(conditions,theneqns,elseenqs,conditions1,theneqns1,source,inEqns)
    local
      DAE.Exp e;
      list<DAE.Exp> explst;
      list<list<BackendDAE.Equation>> eqnslst;
      list<BackendDAE.Equation> eqns;

    // no true case left with condition<>false
    case ({},{},_,{},{},_,_)
      then
        listAppend(elseenqs,inEqns);
    // true case left with condition<>false
    case ({},{},_,_,_,_,_)
      equation
        explst = listReverse(conditions1);
        eqnslst = listReverse(theneqns1);
      then
        BackendDAE.IF_EQUATION(explst,eqnslst,elseenqs,source)::inEqns;
    // if true use it if it is the first one
    case(DAE.BCONST(true)::_,eqns::_,_,{},{},_,_)
      then
        listAppend(eqns,inEqns);
    // if true use it as new else if it is not the first one
    case(DAE.BCONST(true)::_,eqns::_,_,{},{},_,_)
      equation
        explst = listReverse(conditions1);
        eqnslst = listReverse(theneqns1);
      then
        BackendDAE.IF_EQUATION(explst,eqnslst,eqns,source)::inEqns;
    // if false skip it
    case(DAE.BCONST(false)::explst,_::eqnslst,_,_,_,_,_)
      then
        optimizeIfEquation(explst,eqnslst,elseenqs,conditions1,theneqns1,source,inEqns);
    // all other cases
    case(e::explst,eqns::eqnslst,_,_,_,_,_)
      then
        optimizeIfEquation(explst,eqnslst,elseenqs,e::conditions1,eqns::theneqns1,source,inEqns);
  end matchcontinue;
end optimizeIfEquation;

protected function validWhenLeftHandSide
  input DAE.Exp inLhs;
  input DAE.Exp inRhs;
  input DAE.ComponentRef oldCr;
  output DAE.ComponentRef outCr;
  output DAE.Exp oRhs;
algorithm
  (outCr,oRhs) := match(inLhs,inRhs,oldCr)
    local
      DAE.ComponentRef cr;
      DAE.Operator op;
      String msg;
    case(DAE.CREF(componentRef=cr),_,_) then (cr,inRhs);
    case(DAE.UNARY(operator=op,exp=DAE.CREF(componentRef=cr)),_,_) then (cr,DAE.UNARY(op,inRhs));
    case(DAE.LUNARY(operator=op,exp=DAE.CREF(componentRef=cr)),_,_) then (cr,DAE.LUNARY(op,inRhs));
    else
      equation
        msg = "BackendVarTransform: failed to replace left hand side of when equation " +&
              ComponentReference.printComponentRefStr(oldCr) +& " with " +& ExpressionDump.printExpStr(inLhs) +& "\n";
        // print(msg +& "\n");
        Debug.fprintln(Flags.FAILTRACE, msg);
      then
        fail();
  end match;
end validWhenLeftHandSide;

protected function replaceWhenEquation "Replaces variables in a when equation"
  input BackendDAE.WhenEquation whenEqn;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input DAE.ElementSource isource;
  output BackendDAE.WhenEquation outWhenEqn;
  output DAE.ElementSource osource;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outWhenEqn,osource,replacementPerformed) :=
  match(whenEqn,repl,inFuncTypeExpExpToBooleanOption,isource)
  local
    DAE.ComponentRef cr,cr1;
    DAE.Exp e,e1,e2,cre,cre1,cond,cond1,cond2;
    BackendDAE.WhenEquation weqn,elsePart,elsePart2;
    Boolean b1,b2,b3,b4;
    DAE.ElementSource source;

    case (BackendDAE.WHEN_EQ(cond,cr,e,NONE()),_,_,_)
      equation
        (e1,b1) = replaceExp(e, repl,inFuncTypeExpExpToBooleanOption);
        cre = Expression.crefExp(cr);
        (cre1,b3) = replaceExp(cre,repl,inFuncTypeExpExpToBooleanOption);
        (cr1,e1) = validWhenLeftHandSide(cre1,e1,cr);
        (cond1,b2) = replaceExp(cond, repl,inFuncTypeExpExpToBooleanOption);
        (e2,_) = ExpressionSimplify.condsimplify(b1,e1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,isource,e,e2);
        (cond2,_) = ExpressionSimplify.condsimplify(b2,cond1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,cond,cond2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b3,source,cre,cre1);
        b4 = b1 or b2 or b3;
        weqn = Util.if_(b4,BackendDAE.WHEN_EQ(cond2,cr1,e2,NONE()),whenEqn);
      then
        (weqn,source,b4);

    case (BackendDAE.WHEN_EQ(cond,cr,e,SOME(elsePart)),_,_,_)
      equation
        (elsePart2,source,b4) = replaceWhenEquation(elsePart,repl,inFuncTypeExpExpToBooleanOption,isource);
        (e1,b1) = replaceExp(e, repl,inFuncTypeExpExpToBooleanOption);
        cre = Expression.crefExp(cr);
        (cre1,b3) = replaceExp(cre,repl,inFuncTypeExpExpToBooleanOption);
        (cr1,e1) = validWhenLeftHandSide(cre1,e1,cr);
        (cond1,b2) = replaceExp(cond, repl,inFuncTypeExpExpToBooleanOption);
        (e2,_) = ExpressionSimplify.condsimplify(b1,e1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e,e2);
        (cond2,_) = ExpressionSimplify.condsimplify(b2,cond1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,cond,cond2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b3,source,cre,cre1);
        b1 = b1 or b2 or b3 or b4;
        weqn = Util.if_(b1,BackendDAE.WHEN_EQ(cond2,cr1,e2,SOME(elsePart2)),whenEqn);
      then
        (weqn,source,b1);
  end match;
end replaceWhenEquation;

/*********************************************************/
/* replace WhenClauses  */
/*********************************************************/

public function replaceWhenClauses
"function: replaceWhenClauses
  This function takes a list of when clauses ana a set of variable
  replacements and applies the replacements on all clauses.
  The function returns the updated list of clauses"
  input list<BackendDAE.WhenClause> iWhenclauses;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output list<BackendDAE.WhenClause> oWhenclauses;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
protected
  HashTable2.HashTable ht;
algorithm
  (oWhenclauses,replacementPerformed) := matchcontinue(iWhenclauses,repl,inFuncTypeExpExpToBooleanOption)
    local
      list<BackendDAE.WhenClause> whenclauses;
    case(_,REPLACEMENTS(hashTable = ht),_)
      equation
        // Do not do empty replacements; it just takes time ;)
        true = intGt(BaseHashTable.hashTableCurrentSize(ht),0);
        (whenclauses,replacementPerformed) =
          replaceWhenClausesLst(iWhenclauses,repl,inFuncTypeExpExpToBooleanOption,false,{});
      then
        (whenclauses,replacementPerformed);
    else
      then
        (iWhenclauses,false);
  end matchcontinue;
end replaceWhenClauses;

protected function replaceWhenClausesLst
"function: replaceWhenClausesLst
  author: Frenkel TUD 2012-09
  Traverse all expressions of a when clause list. It is possible to change the expressions"
  input list<BackendDAE.WhenClause> inWhenClauseLst;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input Boolean replacementPerformed;
  input list<BackendDAE.WhenClause> iAcc;
  output list<BackendDAE.WhenClause> oWhenclauses;
  output Boolean oReplacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (oWhenclauses,oReplacementPerformed) :=
   match (inWhenClauseLst,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed,iAcc)
    local
      Option<Integer> elsindx;
      list<BackendDAE.WhenOperator> reinitStmtLst,reinitStmtLst1;
      DAE.Exp cond,cond1;
      list<BackendDAE.WhenClause> wclst,wclst1;
      Boolean b,b1,b2;
      BackendDAE.WhenClause wc,wc1;

    case ({},_,_,_,_) then (listReverse(iAcc),replacementPerformed);

    case ((wc as BackendDAE.WHEN_CLAUSE(cond,reinitStmtLst,elsindx))::wclst,_,_,_,_)
      equation
        (cond1,b1) = replaceExp(cond,repl,inFuncTypeExpExpToBooleanOption);
        (cond1,_) = ExpressionSimplify.condsimplify(b1,cond1);
        (reinitStmtLst1,b2) = replaceWhenOperator(reinitStmtLst,repl,inFuncTypeExpExpToBooleanOption,false,{});
        b = b1 or b2;
        wc1 = Util.if_(b,BackendDAE.WHEN_CLAUSE(cond1,reinitStmtLst1,elsindx),wc);
        (wclst1,b) = replaceWhenClausesLst(wclst,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed or b,wc1::iAcc);
      then
        (wclst1,b);
  end match;
end replaceWhenClausesLst;

protected function replaceWhenOperator
"function: replaceWhenOperator
  author: Frenkel TUD 2012-09"
  input list<BackendDAE.WhenOperator> inReinitStmtLst;
  input VariableReplacements repl;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input Boolean replacementPerformed;
  input list<BackendDAE.WhenOperator> iAcc;
  output list<BackendDAE.WhenOperator> oReinitStmtLst;
  output Boolean oReplacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (oReinitStmtLst,oReplacementPerformed) :=
  match (inReinitStmtLst,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed,iAcc)
    local
      list<BackendDAE.WhenOperator> res,res1;
      BackendDAE.WhenOperator wop,wop1;
      DAE.Exp cond,cond1,msg,level,cre,cre1;
      DAE.ComponentRef cr,cr1;
      DAE.ElementSource source;
      Boolean b,b1,b2;
      Absyn.Path functionName;
      list<DAE.Exp> functionArgs,functionArgs1;
      list<Boolean> blst;

    case ({},_,_,_,_) then (listReverse(iAcc),replacementPerformed);

    case ((wop as BackendDAE.REINIT(stateVar=cr,value=cond,source=source))::res,_,_,_,_)
      equation
        cre = Expression.crefExp(cr);
        (cre1,b1) = replaceExp(cre,repl,inFuncTypeExpExpToBooleanOption);
        (cr1,_) = validWhenLeftHandSide(cre1,cre,cr);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,cre,cre1);
        (cond1,b2) = replaceExp(cond,repl,inFuncTypeExpExpToBooleanOption);
        (cond1,_) = ExpressionSimplify.condsimplify(b2,cond1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,cond,cond1);
        b = b1 or b2;
        wop1 = Util.if_(b,BackendDAE.REINIT(cr1,cond1,source),wop);
        (res1,b) =  replaceWhenOperator(res,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed or b,wop1::iAcc);
      then
        (res1,b);
    case ((wop as BackendDAE.ASSERT(condition=cond,message=msg,level=level,source=source))::res,_,_,_,_)
      equation
        (cond1,b) = replaceExp(cond,repl,inFuncTypeExpExpToBooleanOption);
        (cond1,_) = ExpressionSimplify.condsimplify(b,cond1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b,source,cond,cond1);
        wop1 = Util.if_(b,BackendDAE.ASSERT(cond1,msg,level,source),wop);
        (res1,b) =  replaceWhenOperator(res,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed or b,wop1::iAcc);
      then
        (res1,b);
    case ((wop as BackendDAE.TERMINATE(source=_))::res,_,_,_,_)
      equation
        (res1,b) =  replaceWhenOperator(res,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed,wop::iAcc);
      then
        (res1,b);
    case ((wop as BackendDAE.NORETCALL(functionName=functionName,functionArgs=functionArgs,source=source))::res,_,_,_,_)
      equation
        (functionArgs1,blst) = replaceExpList1(functionArgs, repl, inFuncTypeExpExpToBooleanOption, {}, {});
        b = Util.boolOrList(blst);
        source = DAEUtil.addSymbolicTransformationSubstitutionLst(blst,source,functionArgs,functionArgs1);
        wop1 = Util.if_(b,BackendDAE.NORETCALL(functionName,functionArgs1,source),wop);
        (res1,b) =  replaceWhenOperator(res,repl,inFuncTypeExpExpToBooleanOption,replacementPerformed or b,wop1::iAcc);
      then
        (res1,b);
  end match;
end replaceWhenOperator;

/*********************************************************/
/* replace statements  */
/*********************************************************/

public function replaceStatementLst "
function: replaceStatementLst
  perform replacements on statements.
"
  input list<DAE.Statement> inStatementLst;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input list<DAE.Statement> inAcc;
  input Boolean inBAcc;
  output list<DAE.Statement> outStatementLst;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outStatementLst,replacementPerformed) :=
  matchcontinue (inStatementLst,inVariableReplacements,inFuncTypeExpExpToBooleanOption,inAcc,inBAcc)
    local
      VariableReplacements repl;
      list<DAE.Statement> es,es_1,statementLst,statementLst_1;
      DAE.Statement statement,statement_1;
      DAE.Type type_;
      DAE.Exp e1_1,e2_1,e1,e2,e1_2,e2_2,e3,e3_1,e3_2;
      list<DAE.Exp> expExpLst,expExpLst_1;
      DAE.Else else_;
      DAE.ElementSource source;
      DAE.ComponentRef cr;
      Boolean iterIsArray;
      DAE.Ident ident;
      list<DAE.ComponentRef> conditions;
      Boolean initialCall;
      Integer index;
      Boolean b,b1,b2,b3;
      list<tuple<DAE.ComponentRef,Absyn.Info>> loopPrlVars "list of parallel variables used/referenced in the parfor loop";

    case ({},_,_,_,_) then (listReverse(inAcc),inBAcc);

    case ((DAE.STMT_ASSIGN(type_=type_,exp1=e1,exp=e2,source=source)::es),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        (e1_2,_) = ExpressionSimplify.simplify(e1_1);
        (e2_2,_) = ExpressionSimplify.simplify(e2_1);
        (e1_2,e2_2) = moveNegateRhs(e1_2,e2_2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_2);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_ASSIGN(type_,e1_2,e2_2,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_TUPLE_ASSIGN(type_=type_,expExpLst=expExpLst,exp=e2,source=source)::es),repl,_,_,_)
      equation
        (expExpLst_1,b1) = replaceExpList(expExpLst,repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_1);
        (e2_2,b1) = ExpressionSimplify.simplify(e2_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e2_1),DAE.PARTIAL_EQUATION(e2_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_TUPLE_ASSIGN(type_,expExpLst_1,e2_2,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_ASSIGN_ARR(type_=type_,componentRef=cr,exp=e2,source=source)::es),repl,_,_,_)
      equation
        e1 = Expression.crefExp(cr);
        (e1_1,b1) = replaceExp(e1,repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_1);
        (DAE.EQUALITY_EXPS(e1_1,e2_2),source) = ExpressionSimplify.simplifyAddSymbolicOperation(DAE.EQUALITY_EXPS(e1_1,e2_1),source);
        es_1 = validLhsArrayAssignSTMT(cr,e1_1,e2_2,type_,source,inAcc);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,es_1,true);
      then
        ( es_1,b);

    case ((DAE.STMT_IF(exp=e1,statementLst=statementLst,else_=else_,source=source)::es),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e1_2,_) = ExpressionSimplify.condsimplify(b1,e1_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_2);
        (es_1,b) = replaceSTMT_IF(e1_2,statementLst,else_,source,es,repl,inFuncTypeExpExpToBooleanOption,inAcc,inBAcc or b1);
      then
        (es_1,b);

    case ((DAE.STMT_FOR(type_=type_,iterIsArray=iterIsArray,iter=ident,index=index,range=e1,statementLst=statementLst,source=source)::es),repl,_,_,_)
      equation
        repl = addIterationVar(repl,ident);
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e1_1,b2) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.condsimplify(b2,e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        repl = removeIterationVar(repl,ident);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_FOR(type_,iterIsArray,ident,index,e1_2,statementLst_1,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_PARFOR(type_=type_,iterIsArray=iterIsArray,iter=ident,index=index,range=e1,statementLst=statementLst,loopPrlVars=loopPrlVars,source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e1_1,b2) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.condsimplify(b2,e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_PARFOR(type_,iterIsArray,ident,index,e1_2,statementLst_1,loopPrlVars,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_WHILE(exp=e1,statementLst=statementLst,source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e1_1,b2) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.condsimplify(b2,e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_WHILE(e1_2,statementLst_1,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_WHEN(exp=e1,conditions=conditions,initialCall=initialCall,statementLst=statementLst,elseWhen=NONE(),source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e1_1,b2) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.condsimplify(b2,e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_WHEN(e1_2,conditions,initialCall,statementLst_1,NONE(),source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_WHEN(exp=e1,conditions=conditions,initialCall=initialCall,statementLst=statementLst,elseWhen=SOME(statement),source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (statement_1::{},b2) = replaceStatementLst({statement}, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (e1_1,b3) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2 or b3;
        source = DAEUtil.addSymbolicTransformationSubstitution(b3,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.condsimplify(b3,e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_WHEN(e1_2,conditions,initialCall,statementLst_1,SOME(statement_1),source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_ASSERT(cond=e1,msg=e2,level=e3,source=source)::es),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        (e3_1,b3) = replaceExp(e3, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2 or b3;
        (e1_2,_) = ExpressionSimplify.condsimplify(b1,e1_1);
        (e2_2,_) = ExpressionSimplify.condsimplify(b2,e2_1);
        (e3_2,_) = ExpressionSimplify.condsimplify(b3,e3_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b3,source,e3,e3_2);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_ASSERT(e1_2,e2_2,e3_2,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_TERMINATE(msg=e1,source=source)::es),repl,_,_,_)
      equation
        (e1_1,true) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        source = DAEUtil.addSymbolicTransformationSubstitution(true,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.simplify(e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_TERMINATE(e1_2,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_REINIT(var=e1,value=e2,source=source)::es),repl,_,_,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e2_1,b2) = replaceExp(e2, repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
        (e1_2,_) = ExpressionSimplify.condsimplify(b1,e1_1);
        (e2_2,_) = ExpressionSimplify.condsimplify(b2,e2_1);
        source = DAEUtil.addSymbolicTransformationSubstitution(b1,source,e1,e1_2);
        source = DAEUtil.addSymbolicTransformationSubstitution(b2,source,e2,e2_2);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_REINIT(e1_2,e2_2,source)::inAcc,true);
      then
        (es_1,b);

    case ((DAE.STMT_NORETCALL(exp=e1,source=source)::es),repl,_,_,_)
      equation
        (e1_1,true) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        source = DAEUtil.addSymbolicTransformationSubstitution(true,source,e1,e1_1);
        (e1_2,b1) = ExpressionSimplify.simplify(e1_1);
        source = DAEUtil.addSymbolicTransformationSimplify(b1,source,DAE.PARTIAL_EQUATION(e1_1),DAE.PARTIAL_EQUATION(e1_2));
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_NORETCALL(e1_2,source)::inAcc,true);
      then
        ( es_1,b);

    // MetaModelica extension. KS
    case ((DAE.STMT_FAILURE(body=statementLst,source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,true) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_FAILURE(statementLst_1,source)::inAcc,true);
      then
        ( es_1,b);

    case ((DAE.STMT_TRY(tryBody=statementLst,source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,true) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption, DAE.STMT_TRY(statementLst_1,source)::inAcc,true);
      then
        (es_1,b);

    case ((DAE.STMT_CATCH(catchBody=statementLst,source=source)::es),repl,_,_,_)
      equation
        (statementLst_1,true) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_CATCH(statementLst_1,source)::inAcc,true);
      then
        (es_1,b);

    case ((statement::es),repl,_,_,_)
      equation
        (es_1,b1) = replaceStatementLst(es,repl,inFuncTypeExpExpToBooleanOption,statement::inAcc,inBAcc);
      then
        (es_1,b1);
  end matchcontinue;
end replaceStatementLst;

protected function moveNegateRhs
  input DAE.Exp inLhs;
  input DAE.Exp inRhs;
  output DAE.Exp outLhs;
  output DAE.Exp outRhs;
algorithm
  (outLhs,outRhs) := match(inLhs,inRhs)
    local
      DAE.Exp e;
      DAE.Type ty;
    case (DAE.LUNARY(DAE.NOT(ty),e),_) then (e,DAE.LUNARY(DAE.NOT(ty),inRhs));
    case (DAE.UNARY(DAE.UMINUS(ty),e),_) then (e,DAE.UNARY(DAE.UMINUS(ty),inRhs));
    case (DAE.UNARY(DAE.UMINUS_ARR(ty),e),_) then (e,DAE.UNARY(DAE.UMINUS_ARR(ty),inRhs));
    case (_,_) then (inLhs,inRhs);
  end match;
end moveNegateRhs;

protected function validLhsArrayAssignSTMT "
function: validLhsArrayAssignSTMT
  author Frenkel TUD 2012-11
  checks if the lhs is a variable or an array of variables."
  input DAE.ComponentRef oldCr;
  input DAE.Exp lhs;
  input DAE.Exp rhs;
  input DAE.Type type_;
  input DAE.ElementSource source;
  input list<DAE.Statement> inStatementLst;
  output list<DAE.Statement> outStatementLst;
algorithm
  outStatementLst :=
  matchcontinue (oldCr,lhs,rhs,type_,source,inStatementLst)
    local
      list<DAE.Statement> statementLst;
      DAE.ComponentRef cr;
      list<DAE.Exp> elst,elst1;
      DAE.Type tp;
      DAE.Exp e;
      list<Integer> ds;
      list<Option<Integer>> ad;
      list<list<DAE.Subscript>> subslst;
      String msg;
    case (_,DAE.CREF(componentRef=cr),_,_,_,_) then DAE.STMT_ASSIGN_ARR(type_,cr,rhs,source)::inStatementLst;
    case (_,DAE.UNARY(DAE.UMINUS(tp),DAE.CREF(componentRef=cr)),_,_,_,_) then DAE.STMT_ASSIGN_ARR(type_,cr,DAE.UNARY(DAE.UMINUS(tp),rhs),source)::inStatementLst;
    case (_,DAE.UNARY(DAE.UMINUS_ARR(tp),DAE.CREF(componentRef=cr)),_,_,_,_) then DAE.STMT_ASSIGN_ARR(type_,cr,DAE.UNARY(DAE.UMINUS_ARR(tp),rhs),source)::inStatementLst;
    case (_,DAE.LUNARY(DAE.NOT(tp),DAE.CREF(componentRef=cr)),_,_,_,_) then DAE.STMT_ASSIGN_ARR(type_,cr,DAE.LUNARY(DAE.NOT(tp),rhs),source)::inStatementLst;
    case (_,DAE.ARRAY(array=elst),_,_,_,_)
      equation
        ds = Expression.dimensionsSizes(Expression.arrayDimension(type_));
        ad = List.map(ds,Util.makeOption);
        subslst = BackendDAEUtil.arrayDimensionsToRange(ad);
        subslst = BackendDAEUtil.rangesToSubscripts(subslst);
        elst1 = List.map1r(subslst,Expression.applyExpSubscripts,rhs);
        e = listGet(elst1,1);
        tp = Expression.typeof(e);
        statementLst = List.threadFold2(elst,elst1,validLhsAssignSTMT,tp,source,inStatementLst);
      then
        statementLst;
    else
      equation
        msg = "BackendVarTransform: failed to replace left hand side of array assign statement " +&
              ComponentReference.printComponentRefStr(oldCr) +& " with " +& ExpressionDump.printExpStr(lhs) +& "\n";
        // print(msg +& "\n");
        Debug.fprintln(Flags.FAILTRACE, msg);
      then
        fail();
  end matchcontinue;
 end validLhsArrayAssignSTMT;

protected function validLhsAssignSTMT "
function: validLhsAssignSTMT
  author Frenkel TUD 2012-11
  checks if the lhs is a variable or an array of variables."
  input DAE.Exp lhs;
  input DAE.Exp rhs;
  input DAE.Type type_;
  input DAE.ElementSource source;
  input list<DAE.Statement> inStatementLst;
  output list<DAE.Statement> outStatementLst;
algorithm
  outStatementLst :=
  match (lhs,rhs,type_,source,inStatementLst)
    local DAE.Type tp;
    case (DAE.CREF(componentRef=_),_,_,_,_) then DAE.STMT_ASSIGN(type_,lhs,rhs,source)::inStatementLst;
    case (DAE.UNARY(DAE.UMINUS(tp),DAE.CREF(componentRef=_)),_,_,_,_) then DAE.STMT_ASSIGN(type_,lhs,DAE.UNARY(DAE.UMINUS(tp),rhs),source)::inStatementLst;
    case (DAE.LUNARY(DAE.NOT(tp),DAE.CREF(componentRef=_)),_,_,_,_) then DAE.STMT_ASSIGN(type_,lhs,DAE.LUNARY(DAE.NOT(tp),rhs),source)::inStatementLst;
  end match;
 end validLhsAssignSTMT;


protected function replaceElse "function: replaceElse

  Helper for replaceStatementLst.
"
  input DAE.Else inElse;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output DAE.Else outElse;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outElse,replacementPerformed) := matchcontinue (inElse,inVariableReplacements,inFuncTypeExpExpToBooleanOption)
    local
      VariableReplacements repl;
      list<DAE.Statement> statementLst,statementLst_1;
      DAE.Exp e1,e1_1,e1_2;
      DAE.Else else_,else_1;
      Boolean b1,b2;
    case (DAE.ELSEIF(exp=e1,statementLst=statementLst,else_=else_),repl,_)
      equation
        (e1_1,b1) = replaceExp(e1, repl,inFuncTypeExpExpToBooleanOption);
        (e1_2,_) = ExpressionSimplify.condsimplify(b1,e1_1);
        (else_1,b2) = replaceElse1(e1_2,statementLst,else_,repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
      then
        (else_1,true);
    case (DAE.ELSE(statementLst=statementLst),repl,_)
      equation
        (statementLst_1,true) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
      then
        (DAE.ELSE(statementLst_1),true);
    else (inElse,false);
  end matchcontinue;
end replaceElse;

protected function replaceElse1 "function: replaceElse1

  Helper for replaceStatementLst.
"
  input DAE.Exp inExp;
  input list<DAE.Statement> inStatementLst;
  input DAE.Else inElse;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  output DAE.Else outElse;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outElse,replacementPerformed) := matchcontinue (inExp,inStatementLst,inElse,inVariableReplacements,inFuncTypeExpExpToBooleanOption)
    local
      VariableReplacements repl;
      list<DAE.Statement> statementLst,statementLst_1;
      DAE.Exp e1;
      DAE.Else else_,else_1;
      Boolean b1,b2;
    case (DAE.BCONST(true),statementLst,_,repl,_)
      equation
        (statementLst_1,_) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
      then
        (DAE.ELSE(statementLst_1),true);
    case (DAE.BCONST(false),_,else_,repl,_)
      equation
        (else_1,_) = replaceElse(else_, repl,inFuncTypeExpExpToBooleanOption);
      then
        (else_1,true);
    case (e1,statementLst,else_,repl,_)
      equation
        (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
        (else_1,b2) = replaceElse(else_,repl,inFuncTypeExpExpToBooleanOption);
        true = b1 or b2;
      then
        (DAE.ELSEIF(e1,statementLst_1,else_1),true);
    case (e1,statementLst,else_,repl,_)
      then
        (DAE.ELSEIF(e1,statementLst,else_),false);
  end matchcontinue;
end replaceElse1;

protected function replaceSTMT_IF
  input DAE.Exp inExp;
  input list<DAE.Statement> inStatementLst;
  input DAE.Else inElse;
  input DAE.ElementSource inSource;
  input list<DAE.Statement> inStatementRestLst;
  input VariableReplacements inVariableReplacements;
  input Option<FuncTypeExp_ExpToBoolean> inFuncTypeExpExpToBooleanOption;
  input list<DAE.Statement> inAcc;
  input Boolean inBAcc;
  output list<DAE.Statement> outStatementLst;
  output Boolean replacementPerformed;
  partial function FuncTypeExp_ExpToBoolean
    input DAE.Exp inExp;
    output Boolean outBoolean;
  end FuncTypeExp_ExpToBoolean;
algorithm
  (outStatementLst,replacementPerformed) :=
  matchcontinue (inExp,inStatementLst,inElse,inSource,inStatementRestLst,inVariableReplacements,inFuncTypeExpExpToBooleanOption,inAcc,inBAcc)
    local
      DAE.Exp exp,exp_e;
      list<DAE.Statement> statementLst,statementLst_e,statementLst_1,es,es_1;
      DAE.Else else_,else_e,else_1;
      DAE.ElementSource source;
      VariableReplacements repl;
      Boolean b,b1,b2;
      case (DAE.BCONST(true),statementLst,_,_,es,repl,_,_,_)
        equation
          statementLst = listAppend(statementLst,es);
          (es_1,b) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,inAcc,true);
        then (es_1,b);
      case (DAE.BCONST(false),_,else_ as DAE.NOELSE(),source,es,repl,_,_,_)
        equation
          (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,inAcc,true);
        then (es_1,b);
      case (DAE.BCONST(false),_,else_ as DAE.ELSEIF(exp=exp_e,statementLst=statementLst_e,else_=else_e),source,es,repl,_,_,_)
        equation
          (es_1,b) = replaceSTMT_IF(exp_e,statementLst_e,else_e,source,es,repl,inFuncTypeExpExpToBooleanOption,inAcc,true);
        then (es_1,b);
      case (DAE.BCONST(false),_,else_ as DAE.ELSE(statementLst=statementLst_e),source,es,repl,_,_,_)
        equation
          statementLst = listAppend(statementLst_e,es);
          (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,statementLst,true);
        then (es_1,b);
      case (exp,statementLst,else_,source,es,repl,_,_,_)
        equation
          (statementLst_1,b1) = replaceStatementLst(statementLst, repl,inFuncTypeExpExpToBooleanOption,{},false);
          (else_1,b2) = replaceElse(else_,repl,inFuncTypeExpExpToBooleanOption);
          true = b1 or b2;
          (es_1,b) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_IF(exp,statementLst_1,else_1,source)::inAcc,true);
        then (es_1,b);
      case (exp,statementLst,else_,source,es,repl,_,_,_)
        equation
          (es_1,b1) = replaceStatementLst(es, repl,inFuncTypeExpExpToBooleanOption,DAE.STMT_IF(exp,statementLst,else_,source)::inAcc,inBAcc);
        then (es_1,b1);
   end matchcontinue;
end replaceSTMT_IF;

/*********************************************************/
/* dump replacements  */
/*********************************************************/

public function dumpReplacements
"function: dumpReplacements
  Prints the variable replacements on form var1 -> var2"
  input VariableReplacements inVariableReplacements;
algorithm
  _:=
  match (inVariableReplacements)
    local
      String str,len_str;
      Integer len;
      HashTable2.HashTable ht;
      list<tuple<DAE.ComponentRef,DAE.Exp>> tplLst;
    case (REPLACEMENTS(hashTable= ht))
      equation
        (tplLst) = BaseHashTable.hashTableList(ht);
        str = stringDelimitList(List.map(tplLst,printReplacementTupleStr),"\n");
        print("Replacements: (");
        len = listLength(tplLst);
        len_str = intString(len);
        print(len_str);
        print(")\n");
        print("=============\n");
        print(str);
        print("\n");
      then
        ();
  end match;
end dumpReplacements;

public function dumpExtendReplacements
"function: dumpReplacements
  Prints the variable extendreplacements on form var1 -> var2"
  input VariableReplacements inVariableReplacements;
algorithm
  _:=
  match (inVariableReplacements)
    local
      String str,len_str;
      Integer len;
      HashTable2.HashTable ht;
      list<tuple<DAE.ComponentRef,DAE.Exp>> tplLst;
    case (REPLACEMENTS(extendhashTable= ht))
      equation
        (tplLst) = BaseHashTable.hashTableList(ht);
        str = stringDelimitList(List.map(tplLst,printReplacementTupleStr),"\n");
        print("ExtendReplacements: (");
        len = listLength(tplLst);
        len_str = intString(len);
        print(len_str);
        print(")\n");
        print("=============\n");
        print(str);
        print("\n");
      then
        ();
  end match;
end dumpExtendReplacements;

public function dumpDerConstReplacements
"function: dumpReplacements
  Prints the variable derConst replacements on form var1 -> exp"
  input VariableReplacements inVariableReplacements;
algorithm
  _:=
  match (inVariableReplacements)
    local
      String str,len_str;
      Integer len;
      HashTable2.HashTable ht;
      list<tuple<DAE.ComponentRef,DAE.Exp>> tplLst;
    case (REPLACEMENTS(derConst= SOME(ht)))
      equation
        (tplLst) = BaseHashTable.hashTableList(ht);
        str = stringDelimitList(List.map(tplLst,printReplacementTupleStr),"\n");
        print("DerConstReplacements: (");
        len = listLength(tplLst);
        len_str = intString(len);
        print(len_str);
        print(")\n");
        print("=============\n");
        print(str);
        print("\n");
      then
        ();
    else then ();
  end match;
end dumpDerConstReplacements;

protected function printReplacementTupleStr "help function to dumpReplacements"
  input tuple<DAE.ComponentRef,DAE.Exp> tpl;
  output String str;
algorithm
  // optional exteded type debugging
  //str := ComponentReference.debugPrintComponentRefTypeStr(Util.tuple21(tpl)) +& " -> " +& ExpressionDump.debugPrintComponentRefExp(Util.tuple22(tpl));
  // Normal debugging, without type&dimension information on crefs.
  str := ComponentReference.printComponentRefStr(Util.tuple21(tpl)) +& " -> " +& ExpressionDump.printExpStr(Util.tuple22(tpl));
end printReplacementTupleStr;

public function dumpStatistics
"function: dumpStatistics
  author Frenkel TUD 2013-02
  Prints the size of replacement,inverse replacements and"
  input VariableReplacements inVariableReplacements;
protected
  HashTable2.HashTable ht;
  HashTable3.HashTable invht;
  HashTable2.HashTable extht;
  list<DAE.Ident> iVars;
  Option<HashTable2.HashTable> derConst;
algorithm
  REPLACEMENTS(ht,invht,extht,iVars,derConst) := inVariableReplacements;
  print("Replacements: " +& intString(BaseHashTable.hashTableCurrentSize(ht)) +& "\n");
  print("inv. Repl.  : " +& intString(BaseHashTable.hashTableCurrentSize(invht)) +& "\n");
  print("ext  Repl.  : " +& intString(BaseHashTable.hashTableCurrentSize(extht)) +& "\n");
  print("iVars.      : " +& intString(listLength(iVars)) +& "\n");
  extht := Util.getOptionOrDefault(derConst,HashTable2.emptyHashTable());
  print("derConst: " +& intString(BaseHashTable.hashTableCurrentSize(extht)) +& "\n");
end dumpStatistics;

end BackendVarTransform;
