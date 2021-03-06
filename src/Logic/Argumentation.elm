module Logic.Argumentation exposing (..)

import List.Extra as List
import Logic.Core exposing (..)
import Maybe
import Maybe.Extra as Maybe


{-| Preference relation: If the two propositions attack each other, is the first proposition stronger?
-}
type alias Preference =
    Proposition -> Proposition -> Maybe Bool


{-| Converts a list of ranked propositions to a list of propositions and a preference relation on them.
-}
rankingToPreference : List ( Int, Proposition ) -> ( List Proposition, Preference )
rankingToPreference l =
    ( List.map Tuple.second l
    , \a b ->
        l
            |> List.find (\( _, p ) -> p == a)
            |> Maybe.map
                (\( i, _ ) ->
                    l
                        |> List.find (\( _, q ) -> q == b)
                        |> Maybe.map (\( j, _ ) -> i > j)
                )
            |> Maybe.join
    )


type alias Support =
    { pro : List Argument
    , contra : List Argument
    }


type Argument
    = Assumption Proposition
    | Argument Proposition Support
    | Open (List Fact)


head : Argument -> Maybe Proposition
head a =
    case a of
        Assumption h ->
            Just h

        Argument h _ ->
            Just h

        Open _ ->
            Nothing


arguments : DNF -> DNF -> List Proposition -> List Argument
arguments originalQuestion question information =
    information
        |> List.map
            (\p ->
                let
                    cases_ =
                        cases p

                    negatedQuestion =
                        negate_ question

                    restQuestion =
                        consistentCases cases_ negatedQuestion ++ consistentCases negatedQuestion cases_

                    relevant =
                        List.length restQuestion < (List.length cases_ + List.length negatedQuestion)

                    decisive =
                        restQuestion == []
                in
                case ( relevant, decisive ) of
                    ( True, True ) ->
                        Just (Assumption p)

                    ( True, False ) ->
                        let
                            { pro, contra } =
                                proContra originalQuestion (negate_ restQuestion) (List.remove p information)
                        in
                        if pro /= [] && contra /= [] then
                            Just (Argument p { pro = pro, contra = contra })

                        else
                            Nothing

                    ( False, _ ) ->
                        Nothing
            )
        |> Maybe.values
        |> (\l ->
                case l of
                    [] ->
                        if
                            impossible (combine (negate_ originalQuestion) question)
                                || impossible (combine originalQuestion question)
                        then
                            []

                        else
                            List.map Open question

                    _ ->
                        l
           )


proContra : DNF -> DNF -> List Proposition -> Support
proContra originalQuestion question information =
    let
        pro =
            arguments originalQuestion question information

        contra =
            arguments originalQuestion (negate_ question) information
    in
    { pro = pro
    , contra = contra
    }


isPreferred : Preference -> Argument -> Argument -> Bool
isPreferred preference a b =
    case ( a, b ) of
        ( Open _, Open _ ) ->
            False

        ( Open _, _ ) ->
            False

        ( _, Open _ ) ->
            True

        ( a_, b_ ) ->
            Maybe.map2 (\ha hb -> preference ha hb)
                (head a_)
                (head b_)
                |> Maybe.join
                |> Maybe.withDefault False


isDefeated : Preference -> Argument -> Bool
isDefeated preference a =
    case a of
        Argument _ { pro, contra } ->
            (pro
                |> List.filter (\p -> not (isDefeated preference p) && not (isRebutted preference contra p))
                |> (==) []
            )
                || (contra
                        |> List.filter (\p -> not (isDefeated preference p) && not (isRebutted preference pro p))
                        |> List.any (\p -> isPreferred preference p a)
                   )

        _ ->
            False


isRebutted : Preference -> List Argument -> Argument -> Bool
isRebutted preference opponents a =
    opponents
        |> List.filter (\p -> not (isDefeated preference p))
        |> List.any (\b -> isPreferred preference b a)


winnersLosers : Preference -> Support -> { winners : Support, losers : Support }
winnersLosers preference { pro, contra } =
    let
        ( proLosers, proWinners ) =
            List.partition (\a -> isRebutted preference contra a || isDefeated preference a) pro

        ( contraLosers, contraWinners ) =
            List.partition (\a -> isRebutted preference pro a || isDefeated preference a) contra
    in
    { winners = { pro = proWinners, contra = contraWinners }
    , losers = { pro = proLosers, contra = contraLosers }
    }


explanation : Proposition -> ( List Proposition, Preference ) -> { winners : Support, losers : Support }
explanation question ( information, preference ) =
    winnersLosers preference (proContra (cases question) (cases question) information)


openArguments : Preference -> { winners : Support, losers : Support } -> List (List String)
openArguments preference { winners } =
    let
        { pro, contra } =
            winners
    in
    (openArguments_ preference pro ++ openArguments_ preference contra)
        |> List.map List.unique
        |> List.unique


openArguments_ : Preference -> List Argument -> List (List String)
openArguments_ preference l =
    l
        |> List.map
            (\a ->
                case a of
                    Argument _ support ->
                        openArguments preference (winnersLosers preference support)

                    Open c ->
                        [ List.map variable c ]

                    Assumption _ ->
                        []
            )
        |> List.concat


questions preference supports =
    openArguments preference supports
        |> List.cartesianProduct
        |> List.filter (\l -> List.length l > 0)
        |> List.map List.unique
        |> List.map List.sort
        |> List.unique
        |> List.sortBy List.length
