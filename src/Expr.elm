module Expr exposing
    ( Expr(..)
    , evaluate
    , parse
    )

{-
   Sewing pattern editor
   Copyright (C) 2018  Fabian Kirchner <kirchner@posteo.de>

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU Affero General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <https://www.gnu.org/licenses/>.
-}

import Char
import Dict exposing (Dict)
import Parser exposing (..)
import Set


type Expr
    = Number Float
    | Variable String
    | Function String (List String)
    | Sum Expr Expr
    | Difference Expr Expr
    | Product Expr Expr
    | Quotient Expr Expr
    | Max Expr Expr


parse : List String -> String -> Result (List DeadEnd) Expr
parse reservedWords string =
    Parser.run (expr ("max" :: reservedWords)) string


evaluate :
    (String -> List String -> Maybe Float)
    -> Dict String Expr
    -> Expr
    -> Maybe Float
evaluate functions variables e =
    case e of
        Number float ->
            Just float

        Variable name ->
            Dict.get name variables
                |> Maybe.andThen (evaluate functions variables)

        Function name args ->
            functions name args

        Sum exprA exprB ->
            Maybe.map2 (\a b -> a + b)
                (evaluate functions variables exprA)
                (evaluate functions variables exprB)

        Difference exprA exprB ->
            Maybe.map2 (\a b -> a - b)
                (evaluate functions variables exprA)
                (evaluate functions variables exprB)

        Product exprA exprB ->
            Maybe.map2 (\a b -> a * b)
                (evaluate functions variables exprA)
                (evaluate functions variables exprB)

        Quotient exprA exprB ->
            Maybe.map2 (\a b -> a / b)
                (evaluate functions variables exprA)
                (evaluate functions variables exprB)

        Max exprA exprB ->
            Maybe.map2 Basics.max
                (evaluate functions variables exprA)
                (evaluate functions variables exprB)



---- PARSER


digits : Parser Expr
digits =
    number
        { int = Just (Number << toFloat)
        , hex = Nothing
        , octal = Nothing
        , binary = Nothing
        , float = Just Number
        }


var : List String -> Parser Expr
var reservedWords =
    map Variable <|
        variable
            { start = Char.isAlpha
            , inner = \c -> Char.isAlphaNum c || c == '_'
            , reserved = Set.fromList reservedWords
            }


function : List String -> Parser Expr
function reservedWords =
    succeed Function
        |= variable
            { start = Char.isLower
            , inner = \c -> Char.isAlphaNum c || c == '_'
            , reserved = Set.empty
            }
        |. symbol "("
        |. spaces
        |= (variable
                { start = Char.isAlpha
                , inner = \c -> Char.isAlphaNum c || c == '_'
                , reserved = Set.fromList reservedWords
                }
                |> andThen
                    (\firstArg ->
                        argsHelp reservedWords [ firstArg ]
                    )
           )
        |. symbol ")"


max : List String -> Parser Expr
max reservedWords =
    succeed Max
        |. keyword "max"
        |. symbol "("
        |. spaces
        |= lazy (\_ -> expr reservedWords)
        |. spaces
        |. symbol ","
        |. spaces
        |= lazy (\_ -> expr reservedWords)
        |. spaces
        |. symbol ")"


argsHelp : List String -> List String -> Parser (List String)
argsHelp reservedWords revArgs =
    succeed identity
        |. spaces
        |= oneOf
            [ succeed identity
                |. symbol ","
                |. spaces
                |= variable
                    { start = Char.isAlpha
                    , inner = \c -> Char.isAlphaNum c || c == '_'
                    , reserved = Set.fromList reservedWords
                    }
                |> andThen (\nextArg -> argsHelp reservedWords (nextArg :: revArgs))
            , succeed (List.reverse revArgs)
            ]


term : List String -> Parser Expr
term reservedWords =
    oneOf
        [ digits
        , max reservedWords
        , backtrackable (function reservedWords)
        , var reservedWords
        , succeed identity
            |. symbol "("
            |. spaces
            |= lazy (\_ -> expr reservedWords)
            |. spaces
            |. symbol ")"
        ]


expr : List String -> Parser Expr
expr reservedWords =
    term reservedWords
        |> andThen (exprHelp reservedWords [])


exprHelp : List String -> List ( Expr, Operator ) -> Expr -> Parser Expr
exprHelp reservedWords revOps prevExpr =
    succeed identity
        |. spaces
        |= oneOf
            [ succeed Tuple.pair
                |= operator
                |. spaces
                |= term reservedWords
                |> andThen
                    (\( op, nextExpr ) ->
                        exprHelp reservedWords (( prevExpr, op ) :: revOps) nextExpr
                    )
            , lazy (\_ -> succeed (finalize revOps prevExpr))
            ]


type Operator
    = AddOp
    | DifOp
    | MulOp
    | DivOp


operator : Parser Operator
operator =
    oneOf
        [ map (\_ -> AddOp) (symbol "+")
        , map (\_ -> DifOp) (symbol "-")
        , map (\_ -> MulOp) (symbol "*")
        , map (\_ -> DivOp) (symbol "/")
        ]


finalize : List ( Expr, Operator ) -> Expr -> Expr
finalize revOps finalExpr =
    case revOps of
        [] ->
            finalExpr

        ( nextExpr, MulOp ) :: otherRevOps ->
            finalize otherRevOps (Product nextExpr finalExpr)

        ( nextExpr, DivOp ) :: otherRevOps ->
            finalize otherRevOps (Quotient nextExpr finalExpr)

        ( nextExpr, AddOp ) :: otherRevOps ->
            Sum (finalize otherRevOps nextExpr) finalExpr

        ( nextExpr, DifOp ) :: otherRevOps ->
            Difference (finalize otherRevOps nextExpr) finalExpr
