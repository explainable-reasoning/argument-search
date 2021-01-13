module Logic exposing (..)

import List.Extra as List
import Maybe
import Maybe.Extra as Maybe
import Types exposing (..)


decompose : Proposition -> DNF
decompose p =
    case p of
        Variable a ->
            [ [ Positive a ] ]

        And a b ->
            List.map List.concat
                (List.cartesianProduct
                    [ decompose a
                    , decompose b
                    ]
                )

        Or a b ->
            List.concat
                [ decompose a
                , decompose b

                --, decompose (And a b)
                ]

        Implies a b ->
            decompose (Or (Not a) b)

        Equiv a b ->
            decompose (And (Implies a b) (Implies b a))

        True_ ->
            [ [] ]

        False_ ->
            []

        Not (Variable a) ->
            [ [ Negative a ] ]

        Not (And a b) ->
            decompose (Or (Not a) (Not b))

        Not (Or a b) ->
            decompose (And (Not a) (Not b))

        Not (Implies a b) ->
            decompose (Implies (Not b) (Not a))

        Not (Equiv a b) ->
            decompose (Or (Not (Implies a b)) (Not (Implies b a)))

        Not (Not a) ->
            decompose a

        Not True_ ->
            decompose False_

        Not False_ ->
            decompose True_


opposite : Proposition -> Proposition
opposite p =
    case p of
        Not q ->
            q

        _ ->
            Not p


contradicts : Fact -> Fact -> Bool
contradicts a b =
    case ( a, b ) of
        ( Positive a_, Negative b_ ) ->
            a_ == b_

        ( Negative a_, Positive b_ ) ->
            a_ == b_

        _ ->
            False


inconsistent : List Fact -> Bool
inconsistent =
    List.uniquePairs
        >> List.any (\( a, b ) -> contradicts a b)


impossible : DNF -> Bool
impossible =
    List.all inconsistent


add : Fact -> DNF -> DNF
add a =
    List.map ((::) a)


combine : DNF -> DNF -> DNF
combine a b =
    List.cartesianProduct [ a, b ] |> List.map List.concat


closes : DNF -> DNF -> Bool
closes a l =
    impossible (combine a l) && not (impossible l)


shrinks : DNF -> DNF -> Bool
shrinks a b =
    List.length (List.filter inconsistent (combine a b))
        > List.length (List.filter inconsistent b)


consistent : List Fact -> Bool
consistent =
    List.uniquePairs
        >> List.all (\( a, b ) -> not (contradicts a b))


cases : Proposition -> DNF
cases p =
    List.filter consistent (decompose p)


closures : Proposition -> DNF
closures p =
    List.filter inconsistent (decompose p)



-- DECISION SUPPORT


reduce : List Proposition -> Proposition
reduce =
    List.foldl And True_


matters : Proposition -> List Proposition -> Bool
matters a l =
    List.any
        (\aa ->
            List.any
                (\b -> contradicts aa b)
                (List.concat (cases (reduce l)))
        )
        (List.concat (decompose a))


unknown : List Proposition -> List Proposition -> DNF
unknown question information =
    case
        List.find (\p -> matters p question) information
    of
        Nothing ->
            cases (reduce question)

        Just a ->
            unknown
                (a :: question)
                (List.filter ((/=) a) information)


variable : Fact -> String
variable fact =
    case fact of
        Positive a ->
            a

        Negative a ->
            a


shortestLength : List (List a) -> Maybe Int
shortestLength l =
    List.minimum (List.map List.length l)


paths : DNF -> DNF
paths branches =
    branches
        |> List.cartesianProduct
        |> List.map (List.uniqueBy string.fromFact)


questions : DNF -> List String
questions branches =
    shortestLength (paths branches)
        |> Maybe.map (\m -> List.filter (\facts -> List.length facts == m) (paths branches))
        |> Maybe.withDefault []
        |> List.concat
        |> List.map variable



-- EXPLANATION


negateFact : Fact -> Fact
negateFact fact =
    case fact of
        Positive a ->
            Negative a

        Negative a ->
            Positive a


negate : DNF -> DNF
negate l =
    l |> List.cartesianProduct |> List.map (List.map negateFact)


consistentCases : DNF -> DNF -> DNF
consistentCases a b =
    List.filter (\c -> List.all consistent (combine [ c ] a)) b


{-| Performs resolution.
-}
arguments : DNF -> List Proposition -> List Argument
arguments question information =
    information
        |> List.map
            (\p ->
                let
                    cases_ =
                        cases p

                    negatedQuestion =
                        negate question

                    restQuestion =
                        consistentCases cases_ negatedQuestion ++ consistentCases negatedQuestion cases_

                    relevant =
                        List.length restQuestion < (List.length cases_ * List.length negatedQuestion)

                    decisive =
                        restQuestion == []
                in
                case ( relevant, decisive ) of
                    ( True, True ) ->
                        Just (Assumption p)

                    ( True, False ) ->
                        procon (negate restQuestion) (List.remove p information)
                            |> Maybe.map (\l -> Argument p l)

                    ( False, _ ) ->
                        Nothing
            )
        |> Maybe.values


procon : DNF -> List Proposition -> Maybe { pro : List Argument, contra : List Argument }
procon question information =
    let
        pro =
            arguments question information

        contra =
            arguments (negate question) information
    in
    case ( pro, contra ) of
        ( [], [] ) ->
            Nothing

        _ ->
            Just
                { pro = pro
                , contra = contra
                }


isDefeated : Preference -> Argument -> Bool
isDefeated preferred a =
    case a of
        Assumption _ ->
            False

        Argument h { pro, contra } ->
            (pro
                |> List.filter (\p -> not (isDefeated preferred p) && not (isRebutted preferred ( pro, contra ) p))
                |> (==) []
            )
                || (contra
                        |> List.filter (\p -> not (isDefeated preferred p) && not (isRebutted preferred ( contra, pro ) p))
                        |> List.any (\p -> Maybe.withDefault False (preferred (head p) h))
                   )


isRebutted : Preference -> ( List Argument, List Argument ) -> Argument -> Bool
isRebutted preferred ( colleagues, opponents ) a =
    opponents
        |> List.filter (\p -> not (isDefeated preferred p))
        |> List.any (\b -> Maybe.withDefault False (preferred (head b) (head a)))


head a =
    case a of
        Assumption h ->
            h

        Argument h _ ->
            h


winnersLosers :
    Preference
    ->
        { pro : List Argument
        , contra : List Argument
        }
    -> Support
winnersLosers preference { pro, contra } =
    let
        candidates =
            List.map (\a -> ( True, a )) pro ++ List.map (\a -> ( False, a )) contra

        ( losers, winners ) =
            List.partition
                (\( isPro, a ) ->
                    let
                        ( colleagues, opponents ) =
                            List.partition (\( isPro_, _ ) -> isPro_ == isPro) candidates
                                |> (\( c, o ) -> ( c |> List.map Tuple.second, o |> List.map Tuple.second ))
                    in
                    isRebutted preference ( colleagues, opponents ) a || isDefeated preference a
                )
                candidates
    in
    { relevant =
        let
            ( pro_, contra_ ) =
                winners
                    |> List.map
                        (\( isPro, a ) ->
                            case a of
                                Assumption h ->
                                    ( isPro, RelevantAssumption h )

                                Argument h l ->
                                    ( isPro, RelevantArgument h (winnersLosers preference l) )
                        )
                    |> List.partition Tuple.first
        in
        { pro = List.map Tuple.second pro_, contra = List.map Tuple.second contra_ }
    , irrelevant =
        let
            ( pro_, contra_ ) =
                losers |> List.map (\( isPro, a ) -> ( isPro, head a )) |> List.partition Tuple.first
        in
        { pro = List.map Tuple.second pro_, contra = List.map Tuple.second contra_ }
    }


explanation : Preference -> Proposition -> List Proposition -> Maybe Support
explanation preference question information =
    procon (cases question) information |> Maybe.map (winnersLosers preference)
