module Main exposing (..)

import Browser exposing (sandbox)
import Element exposing (..)
import Element.Background as Background
import Element.Events as Events
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes exposing (style)
import Logic exposing (..)
import LogicParser exposing (logic, parse)
import Maybe.Extra as Maybe
import Types exposing (..)


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , view = view
        , update = update
        }


type alias Model =
    { rulesInput : String
    , questionInput : String
    , rules : Maybe (List Proposition)
    , question : Maybe Proposition
    }


type Msg
    = NewRules String
    | NewQuestion String
    | LoadExample ( String, List String )


init : Model
init =
    { rulesInput = "a /\\ b -> c\na\nb\n"
    , questionInput = "c"
    , rules =
        Just
            [ Implies (And (Variable "a") (Variable "b")) (Variable "c")
            , Variable "a"
            , Variable "b"
            ]
    , question = Just (Variable "c")
    }


view : Model -> Html Msg
view model =
    layout
        [ logicFont
        , paddingXY 0 50
        ]
        (column
            [ width (px 600)
            , spacing 50
            , centerX
            ]
            [ Input.multiline [ logicFont ]
                { onChange = NewRules
                , text = model.rulesInput
                , placeholder = Nothing
                , label = Input.labelAbove [] (text "Rules:")
                , spellcheck = False
                }
            , case model.rules of
                Nothing ->
                    text "Error parsing rules."

                _ ->
                    none
            , el
                [ Font.color (rgb 0 0 1)
                , Events.onClick (LoadExample employment)
                , pointer
                ]
                (text "Load employment law example.")
            , el
                [ Font.color (rgb 0 0 1)
                , Events.onClick (LoadExample disj)
                , pointer
                ]
                (text "Load disjunction example.")
            , Input.text [ logicFont ]
                { onChange = NewQuestion
                , text = model.questionInput
                , placeholder = Nothing
                , label = Input.labelAbove [] (text "Question:")
                }
            , case model.question of
                Nothing ->
                    text "Error parsing question."

                _ ->
                    none
            , case ( model.rules, model.question ) of
                ( Just rules, Just question ) ->
                    column
                        [ width fill
                        , spacingXY 0 20
                        ]
                        [ paragraph [] [ text "Explanations:" ]
                        , column [ width fill ]
                            (explanation question rules
                                |> List.map (viewExplanation 0)
                            )
                        ]

                _ ->
                    none
            ]
        )


viewExplanation : Int -> Argument -> Element msg
viewExplanation depth a =
    let
        indented depth_ x =
            row [ width fill ]
                [ column [ width (px (depth_ * 20)) ] []
                , column
                    [ width fill
                    , Background.color (rgba 0 0 0 ((toFloat depth_ + 1) * 0.1))
                    , padding 5
                    ]
                    [ x ]
                ]
    in
    column
        [ width fill
        , spacing 2
        ]
        (case a of
            Assumption p ->
                [ indented depth (text (string.fromProposition p)) ]

            Argument p l ->
                indented depth (text (string.fromProposition p))
                    :: List.map (viewExplanation (depth + 1)) l
        )


marginLeft : Int -> Element.Attribute msg
marginLeft x =
    htmlAttribute (style "margin-left" (String.fromInt x ++ "px"))


logicFont : Element.Attribute Msg
logicFont =
    Font.family
        [ Font.external
            { name = "FiraLogic"
            , url = "font.css"
            }
        , Font.sansSerif
        ]


update : Msg -> Model -> Model
update msg model =
    case msg of
        NewRules s ->
            { model
                | rulesInput = s
                , rules =
                    s
                        |> String.split "\n"
                        |> List.filter (\a -> String.replace " " "" a /= "")
                        |> List.map parse
                        |> Maybe.combine
            }

        NewQuestion s ->
            { model
                | questionInput = s
                , question = parse s
            }

        LoadExample ( question, rules ) ->
            { model
                | rulesInput = String.join "\n" rules ++ "\n"
                , rules = Maybe.combine (List.map parse rules)
                , questionInput = question
                , question = parse question
            }


employment =
    ( "CanMakeRequestForChange"
    , [ "Employed"
      , "¬LessThanTenEmployees"
      , "¬ReachedOldAgeInsurance"
      , "MilitaryOfficial"
      , "WorkedForAtLeastTwentySixWeeks"
      , "Employed -> CanMakeRequestForChange"
      , "Employed /\\ LessThanTenEmployees -> ¬CanMakeRequestForChange"
      , "Employed /\\ ReachedOldAgeInsurance -> ¬CanMakeRequestForChange"
      , "Employed /\\ MilitaryOfficial -> ¬CanMakeRequestForChange"
      ]
    )


disj =
    ( "c"
    , [ "a or b -> c"
      , "a or b"
      ]
    )
