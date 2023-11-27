{-# LANGUAGE ExistentialQuantification, TypeApplications, BlockArguments #-}
{-# LANGUAGE GADTs, PolyKinds #-}
{-# LANGUAGE LambdaCase, ScopedTypeVariables, PatternSynonyms #-}

-- * Original type checker code by Stephanie Weirich at Dagstuhl (Sept 04)
-- * Modernized with Type.Reflection, also by Stephanie
-- * Polytyped prims added
-- * Type-class dictionary passing added
-- * Dropped UType in favor of TypeRep

import qualified Data.Graph as Graph
import qualified Data.Map as Map
import qualified Data.Generics.Schemes as SYB
import qualified Type.Reflection
import qualified Data.Maybe as Maybe
import qualified Language.Haskell.Exts as HSE

import qualified Data.ByteString as ByteString
import qualified Data.Text as Text
import qualified Data.Text.IO as Text

import Data.Map (Map)
import Data.Text (Text)
import Data.Constraint
import GHC.Types
import Type.Reflection (TypeRep, typeRepKind)
import Test.Hspec

--------------------------------------------------------------------------------
-- Untyped AST

data UTerm
  = UVar String
  | ULam String (forall (a::Type). TypeRep a) UTerm
  | UApp UTerm UTerm
  | UForall SomeTRep Forall
  | ULit (forall g. Typed (Term g))

newtype Forall = Forall (forall (a :: Type) g. TypeRep a -> Typed (Term g))

lit :: Type.Reflection.Typeable a => a -> UTerm
lit l = ULit (Typed (Type.Reflection.typeOf l) (Lit l))

--------------------------------------------------------------------------------
-- Typed AST

data Term g t where
  Var :: Var g t -> Term g t
  Lam :: TypeRep (a :: Type) -> Term (g, a) b -> Term g (a -> b)
  App :: Term g (s -> t) -> Term g s -> Term g t
  Lit :: a -> Term g a

data Var g t where
  ZVar :: Var (h, t) t
  SVar :: Var h t -> Var (h, s) t

data Typed (thing :: Type -> Type) = forall ty. Typed (TypeRep (ty :: Type)) (thing ty)

--------------------------------------------------------------------------------
-- Type checker helpers

data SomeTRep = forall (a :: Type). SomeTRep (TypeRep a)
deriving instance Show SomeTRep
instance Eq SomeTRep where
  SomeTRep x == SomeTRep y = Type.Reflection.SomeTypeRep x == Type.Reflection.SomeTypeRep y

-- The type environment and lookup
data TyEnv g where
  Nil :: TyEnv g
  Cons :: String -> TypeRep (t :: Type) -> TyEnv h -> TyEnv (h, t)

lookupVar :: String -> TyEnv g -> Typed (Var g)
lookupVar _ Nil = error "Variable not found"
lookupVar v (Cons s ty e)
  | v == s = Typed ty ZVar
  | otherwise = case lookupVar v e of
      Typed ty v -> Typed ty (SVar v)

--------------------------------------------------------------------------------
-- Type checker

tc :: UTerm -> TyEnv g -> Typed (Term g)
tc (UVar v) env = case lookupVar v env of
  Typed ty v -> Typed ty (Var v)
tc (ULam s bndr_ty' body) env =
      case tc body (Cons s bndr_ty' env) of
        Typed body_ty' body' ->
          Typed
            (Type.Reflection.Fun bndr_ty' body_ty')
            (Lam bndr_ty' body')
tc (UApp e1 e2) env =
  case tc e1 env of
    Typed (Type.Reflection.Fun bndr_ty body_ty) e1' ->
      case tc e2 env of
        Typed arg_ty e2' ->
          case Type.Reflection.eqTypeRep arg_ty bndr_ty of
            Nothing -> error "Type error"
            Just (Type.Reflection.HRefl) ->
             let kind = typeRepKind body_ty
             in
             case Type.Reflection.eqTypeRep kind (Type.Reflection.typeRep @Type) of
               Just Type.Reflection.HRefl
                 -> Typed body_ty
                     (App e1'
                          e2')
-- Mono-typed terms
tc (ULit lit) _env = lit
-- Polytyped terms, must be, syntactically, fully-saturated
tc (UForall (SomeTRep typeRep) (Forall f)) _env =
  f typeRep

--------------------------------------------------------------------------------
-- Evaluator

eval :: env -> Term env t -> t
eval env (Var v) = lookp v env
eval env (Lam _ e) = \x -> eval (env, x) e
eval env (App e1 e2) = (eval env e1) (eval env e2)
eval _env (Lit a) = a

lookp :: Var env t -> env -> t
lookp ZVar (_, x) = x
lookp (SVar v) (env, x) = lookp v env

--------------------------------------------------------------------------------
-- Top-level example

check :: UTerm -> TyEnv () -> Typed (Term ())
check = tc

main2 :: IO ()
main2 = do
  let demo :: IO () =
        case check id_test Nil of
          Typed t ex ->
            case Type.Reflection.eqTypeRep (typeRepKind t) (Type.Reflection.typeRep @Type) of
              Just Type.Reflection.HRefl ->
                case Type.Reflection.eqTypeRep t (Type.Reflection.typeRep @(Bool -> Bool)) of
                  Just Type.Reflection.HRefl ->
                    let bool :: Bool -> Bool = eval () ex
                    in print (bool True)
  demo
  let demo2 :: IO () =
        case check show_test Nil of
          Typed t ex ->
            case Type.Reflection.eqTypeRep (typeRepKind t) (Type.Reflection.typeRep @Type) of
              Just Type.Reflection.HRefl ->
                case Type.Reflection.eqTypeRep t (Type.Reflection.typeRep @(Dict (Show Bool) -> Bool -> String)) of
                  Nothing -> error "Didn't match type Dict (Show Bool) -> Bool -> String"
                  Just Type.Reflection.HRefl ->
                    let bool :: Dict (Show Bool) -> Bool -> String = eval () ex
                    in putStrLn (bool (Dict @(Show Bool)) True)
  demo2
  let demo2 :: IO () =
        case check show_test2 Nil of
          Typed t ex ->
            case Type.Reflection.eqTypeRep (typeRepKind t) (Type.Reflection.typeRep @Type) of
              Just Type.Reflection.HRefl ->
                case Type.Reflection.eqTypeRep t (Type.Reflection.typeRep @(String)) of
                  Nothing -> error "Didn't match type String"
                  Just Type.Reflection.HRefl ->
                    let string :: String = eval () ex
                    in putStrLn string
  demo2
  let demo2 :: IO () =
        case check show_test3 Nil of
          Typed t ex ->
            case Type.Reflection.eqTypeRep (typeRepKind t) (Type.Reflection.typeRep @Type) of
              Just Type.Reflection.HRefl ->
                case Type.Reflection.eqTypeRep t (Type.Reflection.typeRep @(String)) of
                  Nothing -> error "Didn't match type String"
                  Just Type.Reflection.HRefl ->
                    let string :: String = eval () ex
                    in putStrLn string
  demo2


-- example code

id_test :: UTerm
id_test = UForall (SomeTRep (Type.Reflection.typeRep @Bool)) id_

show_test :: UTerm
show_test = UForall (SomeTRep $ Type.Reflection.typeRep @Bool) show_

show_test2 :: UTerm
show_test2 = UApp (UApp (UForall ( SomeTRep $ Type.Reflection.typeRep @Bool) show_) (lit (Dict @(Show Bool)))) (lit True)

show_test3 :: UTerm
show_test3 = UApp (UApp (UForall (SomeTRep $ Type.Reflection.typeRep @Int) show_) (lit (Dict @(Show Int)))) (lit @Int 3)

id_ :: Forall
id_ = Forall (\a -> Typed (Type.Reflection.Fun a a) (Lit id))

show_ :: Forall
show_ =
  Forall $ \(a :: TypeRep a) ->
    Type.Reflection.withTypeable a $
    Typed (Type.Reflection.Fun (Type.Reflection.typeRep @(Dict (Show a))) (Type.Reflection.Fun a (Type.Reflection.typeRep @String)))
          (Lit (\Dict -> show))

--------------------------------------------------------------------------------
-- Desugar expressions

data DesugarError = InvalidVariable | UnknownType String deriving (Show, Eq)

desguarExp :: HSE.Exp HSE.SrcSpanInfo -> Either DesugarError UTerm
desguarExp = go where
  go = \case
    HSE.Paren _ x -> go x
    HSE.Lit _ lit' -> case lit' of
      HSE.Char _ char _ -> pure $ lit char
      HSE.String _ string _ -> pure $ lit string
      HSE.Int _ int _ -> pure $ lit int
    HSE.App _ f x -> UApp <$> go f <*> go x
    HSE.Var _ qname ->
      case qname of
        HSE.UnQual _ (HSE.Ident _ string) -> Right $ UVar string
        HSE.Qual _ (HSE.ModuleName _ prefix) (HSE.Ident _ string)
          | Just uterm <- Map.lookup (prefix ++ "." ++ string) supportedLits ->
            pure uterm
        _ -> Left InvalidVariable

--------------------------------------------------------------------------------
-- Desugar types

desugarType :: HSE.Type HSE.SrcSpanInfo -> Either DesugarError SomeTRep
desugarType = go where
  go :: HSE.Type HSE.SrcSpanInfo -> Either DesugarError SomeTRep
  go = \case
    HSE.TyParen _ x -> go x
    HSE.TyCon _ (HSE.UnQual _ (HSE.Ident _ name))
      | Just rep <- Map.lookup name supportedTypeConstructors -> pure rep
    HSE.TyFun l a b -> do
      SomeTRep aRep <- go a
      SomeTRep bRep <- go b
      pure $ SomeTRep (Type.Reflection.Fun aRep bRep)
    t -> Left $ UnknownType $ HSE.prettyPrint t

desugarTypeSpec :: Spec
desugarTypeSpec = do
  it "desugarType" $ do
    shouldBe (try "Bool") (Right (SomeTRep $ Type.Reflection.typeRep @Bool))
    shouldBe (try "Int") (Right (SomeTRep $ Type.Reflection.typeRep @Int))
    shouldBe (try "Bool -> Int") (Right (SomeTRep $ Type.Reflection.typeRep @(Bool -> Int)))
  where try e = case fmap desugarType $ HSE.parseType e of
           HSE.ParseOk r -> r
           _ -> error "Parse failed."

--------------------------------------------------------------------------------
-- Occurs check

anyCycles :: [(String, HSE.Exp HSE.SrcSpanInfo)] -> Bool
anyCycles =
  any isCycle .
  Graph.stronglyConnComp .
  map \(name, e) -> (name, name, freeVariables e)
  where
    isCycle = \case
      Graph.CyclicSCC{} -> True
      _ -> False

anyCyclesSpec :: Spec
anyCyclesSpec = do
 it "anyCycles" do
   shouldBe (try [("foo","\\z -> x * Z.y"), ("bar","\\z -> Main.bar * Z.y")]) True
   shouldBe (try [("foo","\\z -> Main.bar * Z.y"), ("bar","\\z -> Main.foo * Z.y")]) True
   shouldBe (try [("foo","\\z -> x * Z.y"), ("bar","\\z -> Main.mu * Z.y")]) False
   shouldBe (try [("foo","\\z -> x * Z.y"), ("bar","\\z -> Main.foo * Z.y")]) False

  where
   try named =
    case traverse (\(n, e) -> (n, ) <$> HSE.parseExp e) named of
      HSE.ParseOk decls -> anyCycles decls
      _ -> error "Parse failed."

--------------------------------------------------------------------------------
-- Get free variables of an HSE expression

freeVariables :: HSE.Exp HSE.SrcSpanInfo -> [String]
freeVariables =
  Maybe.mapMaybe unpack .
  SYB.listify (const True :: HSE.QName HSE.SrcSpanInfo -> Bool)
  where
    unpack = \case
      HSE.Qual _ (HSE.ModuleName _ "Main") (HSE.Ident _ name) -> pure name
      _ -> Nothing

freeVariablesSpec :: Spec
freeVariablesSpec = do
 it "freeVariables" $ shouldBe (try "\\z -> Main.x * Z.y") ["x"]
  where try e = case fmap freeVariables $ HSE.parseExp e of
           HSE.ParseOk names -> names
           _ -> error "Parse failed."

--------------------------------------------------------------------------------
-- Test everything

spec :: Spec
spec = do
  anyCyclesSpec
  freeVariablesSpec
  desugarTypeSpec

--------------------------------------------------------------------------------
-- Supported type constructors

supportedTypeConstructors :: Map String SomeTRep
supportedTypeConstructors = Map.fromList [
  ("Bool", SomeTRep $ Type.Reflection.typeRep @Bool),
  ("Int", SomeTRep $ Type.Reflection.typeRep @Int),
  ("Char", SomeTRep $ Type.Reflection.typeRep @Char),
  ("Text", SomeTRep $ Type.Reflection.typeRep @Text)
  ]

--------------------------------------------------------------------------------
-- Support primitives

supportedLits :: Map String UTerm
supportedLits = Map.fromList [
   ("Text.putStrLn", lit Text.putStrLn),
   ("Text.getLine", lit Text.getLine)
  ]
