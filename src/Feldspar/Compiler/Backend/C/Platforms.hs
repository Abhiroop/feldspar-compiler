--
-- Copyright (c) 2009-2011, ERICSSON AB
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
--     * Redistributions of source code must retain the above copyright notice,
--       this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of the ERICSSON AB nor the names of its contributors
--       may be used to endorse or promote products derived from this software
--       without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
-- SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
-- CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
-- OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
-- OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

{-# LANGUAGE RecordWildCards #-}

module Feldspar.Compiler.Backend.C.Platforms
    ( availablePlatforms
    , c99
    , c99OpenMp
    , c99Wool
    , tic64x
    , extend
    , deepCopy
    ) where

import Data.Maybe (fromMaybe)

import Feldspar.Compiler.Backend.C.Options
import Feldspar.Compiler.Imperative.Representation
import Feldspar.Compiler.Imperative.Frontend

availablePlatforms :: [Platform]
availablePlatforms = [ c99, c99OpenMp, c99Wool, tic64x ]

c99 :: Platform
c99 = Platform {
    name = "c99",
    types =
        [ (1 :# (NumType Signed S8),             "int8_t")
        , (1 :# (NumType Signed S16),            "int16_t")
        , (1 :# (NumType Signed S32),            "int32_t")
        , (1 :# (NumType Signed S64),            "int64_t")
        , (1 :# (NumType Unsigned S8),           "uint8_t")
        , (1 :# (NumType Unsigned S16),          "uint16_t")
        , (1 :# (NumType Unsigned S32),          "uint32_t")
        , (1 :# (NumType Unsigned S64),          "uint64_t")
        , (1 :# BoolType,                        "bool")
        , (1 :# FloatType,                       "float")
        , (1 :# DoubleType,                      "double")
        , (1 :# (ComplexType (1 :# FloatType)),  "float complex")
        , (1 :# (ComplexType (1 :# DoubleType)), "double complex")
        ] ,
    values =
        [ (1 :# (ComplexType (1 :# FloatType)), \cx -> "(" ++ showRe cx ++ "+" ++ showIm cx ++ "i)")
        , (1 :# (ComplexType (1 :# DoubleType)), \cx -> "(" ++ showRe cx ++ "+" ++ showIm cx ++ "i)")
        , (1 :# BoolType, \b -> if boolValue b then "true" else "false")
        ] ,
    includes =
        [ "feldspar_c99.h"
        , "feldspar_array.h"
        , "feldspar_future.h"
        , "ivar.h"
        , "taskpool.h"
        , "<stdint.h>"
        , "<string.h>"
        , "<math.h>"
        , "<stdbool.h>"
        , "<complex.h>"],
    varFloating = True
}

c99OpenMp :: Platform
c99OpenMp = c99 { name = "c99OpenMp"
                , varFloating = False
                }

c99Wool :: Platform
c99Wool = c99 { name = "c99Wool"
              , includes = "wool.h":includes c99
              , varFloating = False
              }

tic64x :: Platform
tic64x = Platform {
    name = "tic64x",
    types =
        [ (1 :# (NumType Signed S8),             "char")
        , (1 :# (NumType Signed S16),            "short")
        , (1 :# (NumType Signed S32),            "int")
        , (1 :# (NumType Signed S40),            "long")
        , (1 :# (NumType Signed S64),            "long long")
        , (1 :# (NumType Unsigned S8),           "unsigned char")
        , (1 :# (NumType Unsigned S16),          "unsigned short")
        , (1 :# (NumType Unsigned S32),          "unsigned")
        , (1 :# (NumType Unsigned S40),          "unsigned long")
        , (1 :# (NumType Unsigned S64),          "unsigned long long")
        , (1 :# BoolType,                        "int")
        , (1 :# FloatType,                       "float")
        , (1 :# DoubleType,                      "double")
        , (1 :# (ComplexType (1 :# FloatType)),  "complexOf_float")
        , (1 :# (ComplexType (1 :# DoubleType)), "complexOf_double")
        ] ,
    values =
        [ (1 :# (ComplexType (1 :# FloatType)), \cx -> "complex_fun_float(" ++ showRe cx ++ "," ++ showIm cx ++ ")")
        , (1 :# (ComplexType (1 :# DoubleType)), \cx -> "complex_fun_double(" ++ showRe cx ++ "," ++ showIm cx ++ ")")
        , (1 :# BoolType, \b -> if boolValue b then "1" else "0")
        ] ,
    includes = [ "feldspar_tic64x.h", "feldspar_array.h", "<c6x.h>", "<string.h>"
               , "<math.h>"],
    varFloating = True
}

showRe, showIm :: Constant t -> String
showRe = showConstant . realPartComplexValue
showIm = showConstant . imagPartComplexValue

showConstant :: Constant t -> String
showConstant (DoubleConst c) = show c ++ "f"
showConstant (FloatConst c)  = show c ++ "f"
showConstant c               = show c

deepCopy :: Options -> [ActualParameter ()] -> [Program ()]
deepCopy opts [ValueParameter arg1, ValueParameter arg2]
  | arg1 == arg2
  = []

  | ConstExpr ArrayConst{..} <- arg2
  = initArray (Just arg1) (litI32 $ toInteger $ length arrayValues)
    : zipWith (\i c -> Assign (ArrayElem arg1 (litI32 i)) (ConstExpr c)) [0..] arrayValues

  | NativeArray{} <- typeof arg2
  , l@(ConstExpr (IntConst n _)) <- arrayLength arg2
  = if n < safetyLimit opts
      then initArray (Just arg1) l:map (\i -> Assign (ArrayElem arg1 (litI32 i)) (ArrayElem arg2 (litI32 i))) [0..(n-1)]
      else error $ unlines ["Internal compiler error: array size (" ++ show n ++ ") too large for deepcopy", show arg1, show arg2]

  | StructType _ fts <- typeof arg2
  = concatMap (deepCopyField . fst) fts

  | not (isArray (typeof arg1))
  = [Assign arg1 arg2]
    where deepCopyField fld = deepCopy opts [ ValueParameter $ StructField arg1 fld
                                            , ValueParameter $ StructField arg2 fld]

deepCopy _ (ValueParameter arg1 : ins'@(ValueParameter in1:ins))
  | isArray (typeof arg1)
  = [ initArray (Just arg1) expDstLen, copyFirstSegment ] ++
      flattenCopy (ValueParameter arg1) ins argnLens arg1len
    where expDstLen = foldr ePlus (litI32 0) aLens
          copyFirstSegment = if arg1 == in1
                                then Empty
                                else call "copyArray" [ ValueParameter arg1
                                                      , ValueParameter in1]
          aLens@(arg1len:argnLens) = map (\(ValueParameter src) -> arrayLength src) ins'

deepCopy _ _ = error "Multiple non-array arguments to copy"

flattenCopy :: ActualParameter () -> [ActualParameter ()] -> [Expression ()] ->
               Expression () -> [Program ()]
flattenCopy _ [] [] _ = []
flattenCopy dst (t:ts) (l:ls) cLen = call "copyArrayPos" [dst, ValueParameter cLen, t]
                                   : flattenCopy dst ts ls (ePlus cLen l)

ePlus :: Expression () -> Expression () -> Expression ()
ePlus (ConstExpr (IntConst 0 _)) e = e
ePlus e (ConstExpr (IntConst 0 _)) = e
ePlus e1 e2                        = binop (1 :# (NumType Signed S32)) "+" e1 e2

extend :: Platform -> String -> Type -> String
extend Platform{..} s t = s ++ "_fun_" ++ fromMaybe (show t) (lookup t types)

