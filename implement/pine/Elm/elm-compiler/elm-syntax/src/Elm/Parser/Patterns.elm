module Elm.Parser.Patterns exposing (pattern)

import Combine exposing (Parser, between, maybe, parens, sepBy, string)
import Elm.Parser.Base as Base
import Elm.Parser.Layout as Layout
import Elm.Parser.Node
import Elm.Parser.Numbers
import Elm.Parser.State exposing (State)
import Elm.Parser.Tokens exposing (characterLiteral, functionName, stringLiteral)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern exposing (Pattern(..), QualifiedNameRef)
import Parser as Core


tryToCompose : Node Pattern -> Parser State (Node Pattern)
tryToCompose x =
    maybe Layout.layout
        |> Combine.continueWith
            (Combine.oneOf
                [ Combine.succeed (\y -> Node.combine AsPattern x y)
                    |> Combine.ignore (Combine.fromCore (Core.keyword "as"))
                    |> Combine.ignore Layout.layout
                    |> Combine.keep (Elm.Parser.Node.parser functionName)
                , Combine.succeed (\y -> Node.combine UnConsPattern x y)
                    |> Combine.ignore (Combine.fromCore (Core.symbol "::"))
                    |> Combine.ignore (maybe Layout.layout)
                    |> Combine.keep pattern
                , Combine.succeed x
                ]
            )


pattern : Parser State (Node Pattern)
pattern =
    Combine.lazy
        (\() ->
            composablePattern |> Combine.andThen tryToCompose
        )


parensPattern : Parser State (Node Pattern)
parensPattern =
    Elm.Parser.Node.parser
        (parens (sepBy (string ",") (Layout.maybeAroundBothSides pattern))
            |> Combine.map
                (\c ->
                    case c of
                        [ x ] ->
                            ParenthesizedPattern x

                        _ ->
                            TuplePattern c
                )
        )


variablePart : Parser State (Node Pattern)
variablePart =
    Elm.Parser.Node.parser (Combine.map VarPattern functionName)


numberPart : Parser State Pattern
numberPart =
    Elm.Parser.Numbers.number IntPattern HexPattern


listPattern : Parser State (Node Pattern)
listPattern =
    Elm.Parser.Node.parser <|
        between
            (string "[" |> Combine.ignore (maybe Layout.layout))
            (string "]")
            (Combine.map ListPattern (sepBy (string ",") (Layout.maybeAroundBothSides pattern)))


type alias ConsumeArgs =
    Bool


composablePattern : Parser State (Node Pattern)
composablePattern =
    Combine.oneOf
        [ variablePart
        , qualifiedPattern True
        , Elm.Parser.Node.parser (stringLiteral |> Combine.map StringPattern)
        , Elm.Parser.Node.parser (characterLiteral |> Combine.map CharPattern)
        , Elm.Parser.Node.parser numberPart
        , Elm.Parser.Node.parser (Core.symbol "()" |> Combine.fromCore |> Combine.map (always UnitPattern))
        , Elm.Parser.Node.parser (Core.symbol "_" |> Combine.fromCore |> Combine.map (always AllPattern))
        , recordPattern
        , listPattern
        , parensPattern
        ]


qualifiedPatternArg : Parser State (Node Pattern)
qualifiedPatternArg =
    Combine.oneOf
        [ variablePart
        , qualifiedPattern False
        , Elm.Parser.Node.parser (stringLiteral |> Combine.map StringPattern)
        , Elm.Parser.Node.parser (characterLiteral |> Combine.map CharPattern)
        , Elm.Parser.Node.parser numberPart
        , Elm.Parser.Node.parser (Core.symbol "()" |> Combine.fromCore |> Combine.map (always UnitPattern))
        , Elm.Parser.Node.parser (Core.symbol "_" |> Combine.fromCore |> Combine.map (always AllPattern))
        , recordPattern
        , listPattern
        , parensPattern
        ]


qualifiedPattern : ConsumeArgs -> Parser State (Node Pattern)
qualifiedPattern consumeArgs =
    Elm.Parser.Node.parser Base.typeIndicator
        |> Combine.ignore (maybe Layout.layout)
        |> Combine.andThen
            (\(Node range ( mod, name )) ->
                (if consumeArgs then
                    Combine.manyWithEndLocationForLastElement range Node.range (qualifiedPatternArg |> Combine.ignore (maybe Layout.layout))

                 else
                    Combine.succeed ( range.end, [] )
                )
                    |> Combine.map
                        (\( end, args ) ->
                            Node
                                { start = range.start, end = end }
                                (NamedPattern (QualifiedNameRef mod name) args)
                        )
            )


recordPattern : Parser State (Node Pattern)
recordPattern =
    Elm.Parser.Node.parser
        (Combine.map RecordPattern <|
            between
                (string "{" |> Combine.continueWith (maybe Layout.layout))
                (string "}")
                (sepBy (string ",") (Layout.maybeAroundBothSides (Elm.Parser.Node.parser functionName)))
        )
