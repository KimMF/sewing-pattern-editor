port module Main exposing (main)

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

import Accessibility.Widget as Widget
import Array
import Axis2d exposing (Axis2d)
import BoundingBox2d
import Browser exposing (Document)
import Browser.Dom
import Browser.Events
import Browser.Navigation exposing (Key)
import Circle2d exposing (Circle2d)
import Color
import Css
import Direction2d
import Element exposing (Element)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Element.Input as Input
import Geometry.Svg as Svg
import Html.Attributes
import Html.Events as Events
import Html.Styled as Html
import Html.Styled.Attributes as Attributes
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline as Decode
import Json.Encode as Encode exposing (Value)
import LineSegment2d exposing (LineSegment2d)
import Pattern exposing (Circle, Detail, Line, LineSegment, Pattern, Point)
import Point2d exposing (Point2d)
import Polygon2d exposing (Polygon2d)
import QuadraticSpline2d
import Store exposing (Entry)
import Styled.Listbox as Listbox exposing (Listbox)
import Styled.Listbox.Dropdown as Dropdown exposing (Dropdown)
import Svg exposing (Svg)
import Svg.Attributes
import Svg.Events
import Task
import That exposing (That)
import Those exposing (Those)
import Url exposing (Url)
import Vector2d
import VoronoiDiagram2d


main : Program Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = onUrlRequest
        , onUrlChange = onUrlChange
        }


port safePattern : Value -> Cmd msg


port requestPattern : () -> Cmd msg


port patternReceived : (Value -> msg) -> Sub msg


port safeViewport : Value -> Cmd msg


port requestViewport : () -> Cmd msg


port viewportReceived : (Value -> msg) -> Sub msg



---- MODEL


type alias Model =
    { windowWidth : Int
    , windowHeight : Int
    , zoom : Float
    , center : Position
    , maybeDrag : Maybe Drag

    -- PATTERN
    , pattern : Pattern
    , hoveredPoint : Maybe (That Point)
    , hoveredTool : Maybe ToolTag
    , dialog : Dialog

    -- RIGHT TOOLBAR
    , rightToolbarVisible : Bool
    , variablesVisible : Bool
    , pointsVisible : Bool
    }


type alias Viewport =
    { zoom : Float
    , center : Position
    }


encodeViewport : Model -> Value
encodeViewport model =
    Encode.object
        [ ( "zoom", Encode.float model.zoom )
        , ( "center", encodePosition model.center )
        ]


encodePosition : Position -> Value
encodePosition { x, y } =
    Encode.object
        [ ( "x", Encode.float x )
        , ( "y", Encode.float y )
        ]


viewportDecoder : Decoder Viewport
viewportDecoder =
    Decode.succeed Viewport
        |> Decode.required "zoom" Decode.float
        |> Decode.required "center"
            (Decode.succeed Position
                |> Decode.required "x" Decode.float
                |> Decode.required "y" Decode.float
            )


type alias Drag =
    { start : Position
    , current : Position
    }


type alias Position =
    { x : Float
    , y : Float
    }


type Dialog
    = NoDialog
    | Tool Tool
    | CreateVariable
        { name : String
        , value : String
        }


type ToolTag
    = LeftOfTag
    | RightOfTag
    | AboveTag
    | BelowTag
    | AtAngleTag
    | BetweenRatioTag
    | BetweenLengthTag
    | CircleCircleTag
    | CenteredAtTag
    | ThroughTwoPointsTag
    | FromToTag
    | MirrorAtTag
    | CutAlongLineSegmentTag
    | CounterClockwiseTag


toolToTag : Tool -> ToolTag
toolToTag tool =
    let
        pointDataToTag pointData =
            case pointData of
                LeftOf _ ->
                    LeftOfTag

                RightOf _ ->
                    RightOfTag

                Above _ ->
                    AboveTag

                Below _ ->
                    BelowTag

                AtAngle _ ->
                    AtAngleTag

                BetweenRatio _ ->
                    BetweenRatioTag

                BetweenLength _ ->
                    BetweenLengthTag

                CircleCircle _ ->
                    CircleCircleTag
    in
    case tool of
        CreatePoint _ pointData ->
            pointDataToTag pointData

        EditPoint _ pointData ->
            pointDataToTag pointData

        CenteredAt _ ->
            CenteredAtTag

        ThroughTwoPoints _ ->
            ThroughTwoPointsTag

        FromTo _ ->
            FromToTag

        MirrorAt _ ->
            MirrorAtTag

        CutAlongLineSegment _ ->
            CutAlongLineSegmentTag

        CounterClockwise _ ->
            CounterClockwiseTag


type PointData
    = LeftOf
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , distance : String
        }
    | RightOf
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , distance : String
        }
    | Above
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , distance : String
        }
    | Below
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , distance : String
        }
    | AtAngle
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , angle : String
        , distance : String
        }
    | BetweenRatio
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , dropdownAnchorB : Dropdown
        , maybeThatAnchorB : Maybe (That Point)
        , ratio : String
        }
    | BetweenLength
        { dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , dropdownAnchorB : Dropdown
        , maybeThatAnchorB : Maybe (That Point)
        , length : String
        }
    | CircleCircle
        { dropdownCircleA : Dropdown
        , maybeThatCircleA : Maybe (That Circle)
        , dropdownCircleB : Dropdown
        , maybeThatCircleB : Maybe (That Circle)
        , first : Bool
        }


type Tool
    = CreatePoint String PointData
    | EditPoint (That Point) PointData
      -- CIRCLES
    | CenteredAt
        { name : String
        , dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , radius : String
        }
      -- LINES
    | ThroughTwoPoints
        { name : String
        , dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , dropdownAnchorB : Dropdown
        , maybeThatAnchorB : Maybe (That Point)
        }
      -- LINE SEGMENTS
    | FromTo
        { name : String
        , dropdownAnchorA : Dropdown
        , maybeThatAnchorA : Maybe (That Point)
        , dropdownAnchorB : Dropdown
        , maybeThatAnchorB : Maybe (That Point)
        }
      -- TRANSFORMATIONS
    | MirrorAt
        { dropdown : Dropdown
        , thatLine : Maybe (That Line)
        , listbox : Listbox
        , thosePoints : Those Point
        }
    | CutAlongLineSegment
        { dropdownLineSegment : Dropdown
        , thatLineSegment : Maybe (That LineSegment)
        , dropdownDetail : Dropdown
        , thatDetail : Maybe (That Detail)
        }
      -- DETAILS
    | CounterClockwise (List (That Point))


toolDescription : ToolTag -> Element msg
toolDescription toolTag =
    let
        simpleDistanceHorizontal kind =
            Element.paragraph []
                [ s "Create a new "
                , strong "point"
                , s " to the "
                , strong kind
                , s " another point."
                ]

        simpleDistanceVertical kind =
            Element.paragraph []
                [ s "Create a new "
                , Element.el
                    [ Font.bold ]
                    (Element.text "point")
                , s " "
                , Element.el
                    [ Font.bold ]
                    (Element.text kind)
                , s " another point."
                ]

        s =
            Element.text

        strong =
            Element.el [ Font.bold ] << Element.text
    in
    case toolTag of
        LeftOfTag ->
            simpleDistanceHorizontal "left of"

        RightOfTag ->
            simpleDistanceHorizontal "right of"

        AboveTag ->
            simpleDistanceVertical "above"

        BelowTag ->
            simpleDistanceVertical "below"

        AtAngleTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "point"
                , s " relative to another point by providing an "
                , strong "angle"
                , s " and a "
                , strong "distance"
                , s "."
                ]

        BetweenRatioTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "point"
                , s " between two other points at a certain "
                , strong "ratio"
                , s "."
                ]

        BetweenLengthTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "point"
                , s " between two other points at a certain "
                , strong "length"
                , s "."
                ]

        CircleCircleTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "point"
                , s " at the intersection of two "
                , strong "circles"
                , s "."
                ]

        CenteredAtTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "circle"
                , s " by providing its "
                , strong "center point"
                , s " and the "
                , strong "radius"
                , s "."
                ]

        ThroughTwoPointsTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "line"
                , s " through "
                , strong "two points"
                , s "."
                ]

        FromToTag ->
            Element.paragraph []
                [ s "Connect "
                , strong "two points"
                , s " with a new "
                , strong "line segment"
                , s "."
                ]

        MirrorAtTag ->
            Element.paragraph []
                [ s "Mirror a "
                , strong "set of points"
                , s " along a "
                , strong "line"
                , s "."
                ]

        CutAlongLineSegmentTag ->
            Element.paragraph []
                [ s "Cut a "
                , strong "detail"
                , s " into two along a "
                , strong "line segment"
                , s "."
                ]

        CounterClockwiseTag ->
            Element.paragraph []
                [ s "Create a new "
                , strong "detail"
                , s " by connecting "
                , strong "points"
                , s " counterclockwise."
                ]


selectedPointsFromTool : Tool -> Those Point
selectedPointsFromTool tool =
    let
        empty =
            Those.fromList []

        onlyAnchorA data =
            data.maybeThatAnchorA
                |> maybeToList
                |> Those.fromList

        anchorAandB data =
            [ data.maybeThatAnchorA, data.maybeThatAnchorB ]
                |> List.filterMap identity
                |> Those.fromList

        selectedPointsFromPointData pointData =
            case pointData of
                LeftOf data ->
                    onlyAnchorA data

                RightOf data ->
                    onlyAnchorA data

                Above data ->
                    onlyAnchorA data

                Below data ->
                    onlyAnchorA data

                AtAngle data ->
                    onlyAnchorA data

                BetweenRatio data ->
                    anchorAandB data

                BetweenLength data ->
                    anchorAandB data

                CircleCircle _ ->
                    empty
    in
    case tool of
        CreatePoint _ pointData ->
            selectedPointsFromPointData pointData

        EditPoint _ pointData ->
            selectedPointsFromPointData pointData

        CenteredAt data ->
            onlyAnchorA data

        ThroughTwoPoints data ->
            anchorAandB data

        FromTo data ->
            anchorAandB data

        MirrorAt { thosePoints } ->
            thosePoints

        CutAlongLineSegment _ ->
            empty

        CounterClockwise targets ->
            Those.fromList targets


selectedLinesFromTool : Tool -> Those Line
selectedLinesFromTool tool =
    let
        empty =
            Those.fromList []

        selectedLinesFromPointData pointData =
            case pointData of
                LeftOf _ ->
                    empty

                RightOf _ ->
                    empty

                Above _ ->
                    empty

                Below _ ->
                    empty

                AtAngle _ ->
                    empty

                BetweenRatio _ ->
                    empty

                BetweenLength _ ->
                    empty

                CircleCircle _ ->
                    empty
    in
    case tool of
        CreatePoint _ pointData ->
            selectedLinesFromPointData pointData

        EditPoint _ pointData ->
            selectedLinesFromPointData pointData

        CenteredAt _ ->
            empty

        ThroughTwoPoints _ ->
            empty

        FromTo _ ->
            empty

        MirrorAt { thatLine } ->
            thatLine
                |> maybeToList
                |> Those.fromList

        CutAlongLineSegment _ ->
            empty

        CounterClockwise _ ->
            empty


selectedLineSegmentsFromTool : Tool -> Those LineSegment
selectedLineSegmentsFromTool tool =
    let
        empty =
            Those.fromList []

        selectedLineSegmentsFromPointData pointData =
            case pointData of
                LeftOf _ ->
                    empty

                RightOf _ ->
                    empty

                Above _ ->
                    empty

                Below _ ->
                    empty

                AtAngle _ ->
                    empty

                BetweenRatio _ ->
                    empty

                BetweenLength _ ->
                    empty

                CircleCircle _ ->
                    empty
    in
    case tool of
        CreatePoint _ pointData ->
            selectedLineSegmentsFromPointData pointData

        EditPoint _ pointData ->
            selectedLineSegmentsFromPointData pointData

        CenteredAt _ ->
            empty

        ThroughTwoPoints _ ->
            empty

        FromTo _ ->
            empty

        MirrorAt _ ->
            empty

        CutAlongLineSegment { thatLineSegment } ->
            thatLineSegment
                |> maybeToList
                |> Those.fromList

        CounterClockwise _ ->
            empty


selectedDetailsFromTool : Tool -> Those Detail
selectedDetailsFromTool tool =
    let
        empty =
            Those.fromList []

        selectedDetailsFromPointData pointData =
            case pointData of
                LeftOf _ ->
                    empty

                RightOf _ ->
                    empty

                Above _ ->
                    empty

                Below _ ->
                    empty

                AtAngle _ ->
                    empty

                BetweenRatio _ ->
                    empty

                BetweenLength _ ->
                    empty

                CircleCircle _ ->
                    empty
    in
    case tool of
        CreatePoint _ pointData ->
            selectedDetailsFromPointData pointData

        EditPoint _ pointData ->
            selectedDetailsFromPointData pointData

        CenteredAt _ ->
            empty

        ThroughTwoPoints _ ->
            empty

        FromTo _ ->
            empty

        MirrorAt _ ->
            empty

        CutAlongLineSegment { thatDetail } ->
            thatDetail
                |> maybeToList
                |> Those.fromList

        CounterClockwise _ ->
            empty


maybeToList : Maybe a -> List a
maybeToList maybeA =
    case maybeA of
        Nothing ->
            []

        Just a ->
            [ a ]


type alias Flags =
    { windowWidth : Int
    , windowHeight : Int
    , pattern : Maybe Pattern
    , viewport : Maybe Viewport
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.succeed Flags
        |> Decode.required "windowWidth" Decode.int
        |> Decode.required "windowHeight" Decode.int
        |> Decode.optional "pattern" (Decode.map Just Pattern.decoder) Nothing
        |> Decode.optional "viewport" (Decode.map Just viewportDecoder) Nothing


init : Value -> Url -> Key -> ( Model, Cmd Msg )
init value url key =
    case Decode.decodeValue flagsDecoder value of
        Err error ->
            ( { windowWidth = 1280
              , windowHeight = 640
              , zoom = 1
              , center = Position 0 0
              , maybeDrag = Nothing
              , pattern = defaultPattern
              , hoveredPoint = Nothing
              , hoveredTool = Nothing
              , dialog = NoDialog
              , rightToolbarVisible = False
              , variablesVisible = True
              , pointsVisible = False
              }
            , Cmd.batch
                [ requestPattern ()
                , requestViewport ()
                ]
            )

        Ok flags ->
            ( { windowWidth = flags.windowWidth
              , windowHeight = flags.windowHeight
              , zoom =
                    flags.viewport
                        |> Maybe.map .zoom
                        |> Maybe.withDefault 1
              , center =
                    flags.viewport
                        |> Maybe.map .center
                        |> Maybe.withDefault (Position 0 0)
              , maybeDrag = Nothing
              , pattern = Maybe.withDefault defaultPattern flags.pattern
              , hoveredPoint = Nothing
              , hoveredTool = Nothing
              , dialog = NoDialog
              , rightToolbarVisible = False
              , variablesVisible = True
              , pointsVisible = False
              }
            , Cmd.none
            )


defaultPattern =
    Pattern.empty
        |> Pattern.insertPoint
            (Just "origin")
            (Pattern.origin { x = 0, y = 0 })



---- VIEW


view : Model -> Document Msg
view model =
    { title = "Sewing Pattern Editor"
    , body =
        [ Element.layoutWith
            { options =
                [ Element.focusStyle
                    { borderColor = Just (color (Color.rgb255 229 223 197))
                    , backgroundColor = Nothing
                    , shadow = Nothing
                    }
                ]
            }
            [ Element.width Element.fill
            , Element.height Element.fill
            , Font.family
                [ Font.external
                    { name = "Roboto"
                    , url = "https://fonts.googleapis.com/css?family=Roboto"
                    }
                , Font.sansSerif
                ]
            ]
            (Element.el
                [ Element.width Element.fill
                , Element.height Element.fill
                , Element.inFront (viewOverlay model)
                ]
                (viewWorkspace model)
            )
        ]
    }


viewWorkspace : Model -> Element Msg
viewWorkspace model =
    let
        maybeTool =
            case model.dialog of
                Tool tool ->
                    Just tool

                _ ->
                    Nothing

        selectedPoints =
            maybeTool
                |> Maybe.map selectedPointsFromTool
                |> Maybe.withDefault (Those.fromList [])

        selectedLines =
            maybeTool
                |> Maybe.map selectedLinesFromTool
                |> Maybe.withDefault (Those.fromList [])

        selectedLineSegments =
            maybeTool
                |> Maybe.map selectedLineSegmentsFromTool
                |> Maybe.withDefault (Those.fromList [])

        selectedDetails =
            maybeTool
                |> Maybe.map selectedDetailsFromTool
                |> Maybe.withDefault (Those.fromList [])
    in
    Element.el
        [ Element.width Element.fill
        , Element.height Element.fill
        , Element.inFront (viewDialog model.pattern model.dialog)
        ]
        (Element.html <|
            Svg.svg
                [ Svg.Attributes.viewBox (viewBox model)
                , Html.Attributes.style "user-select" "none"
                , Events.on "mousedown" <|
                    Decode.map MouseDown <|
                        Decode.map2 Position
                            (Decode.field "screenX" Decode.float)
                            (Decode.field "screenY" Decode.float)
                ]
                [ drawPattern model
                    model.hoveredPoint
                    selectedPoints
                    selectedLines
                    selectedLineSegments
                    selectedDetails
                    model.pattern
                ]
        )


viewOverlay model =
    Element.column
        [ Element.width Element.fill
        , Element.height Element.fill
        , Element.htmlAttribute <|
            Html.Attributes.style "pointer-events" "none"
        ]
        [ Element.row
            [ Element.height Element.fill
            , Element.width Element.fill
            ]
            [ viewLeftToolbar model
            , Element.el
                [ Element.width Element.fill
                , Element.height Element.fill
                ]
                Element.none
            , viewZoom model
            , viewRightToolbar model
            ]
        , Element.row
            [ Element.width Element.fill
            , Element.height (Element.px 40)
            , Element.paddingXY 10 5
            , Element.spacing 5
            , Background.color gray950
            , Element.htmlAttribute <|
                Html.Attributes.style "pointer-events" "auto"
            ]
            [ case model.hoveredTool of
                Nothing ->
                    Element.none

                Just toolTag ->
                    Element.el
                        [ Font.size 12
                        , Font.color white
                        , Element.width Element.fill
                        ]
                        (toolDescription toolTag)
            , Element.newTabLink
                [ Element.alignRight
                , Element.paddingXY 5 5
                , Font.color white
                ]
                { url = "https://github.com/kirchner/sewing-pattern-editor"
                , label = devIcon "github-plain"
                }
            ]
        ]


viewLeftToolbar model =
    Element.column
        [ Element.height Element.fill
        , Background.color gray900
        , Element.htmlAttribute <|
            Html.Attributes.style "pointer-events" "auto"
        ]
        [ viewToolSelector model.hoveredTool <|
            case model.dialog of
                Tool tool ->
                    Just tool

                _ ->
                    Nothing
        , Element.el [ Element.height Element.fill ] Element.none
        , Element.row
            [ Element.paddingXY 10 5
            , Element.width Element.fill
            ]
            [ buttonDanger "Clear pattern" ClearPatternClicked
            ]
        ]


viewZoom model =
    Element.column
        [ Element.height Element.fill ]
        [ Element.el [ Element.height Element.fill ] Element.none
        , Element.row
            [ Element.width Element.fill
            , Element.padding 20
            , Element.spacing 10
            ]
            [ Input.button
                [ Element.mouseOver
                    [ Font.color gray700 ]
                , Element.htmlAttribute <|
                    Html.Attributes.style "pointer-events" "auto"
                ]
                { onPress = Just ZoomPlusClicked
                , label =
                    bigIcon "search-plus"
                }
            , Input.button
                [ Element.mouseOver
                    [ Font.color gray700 ]
                , Element.htmlAttribute <|
                    Html.Attributes.style "pointer-events" "auto"
                ]
                { onPress = Just ZoomMinusClicked
                , label =
                    bigIcon "search-minus"
                }
            ]
        ]


viewBox : Model -> String
viewBox model =
    let
        width =
            toFloat model.windowWidth * model.zoom

        height =
            toFloat model.windowHeight * model.zoom
    in
    String.join " "
        [ String.fromFloat (-1 * width / 2)
        , String.fromFloat (-1 * height / 2)
        , String.fromFloat width
        , String.fromFloat height
        ]


viewRightToolbar : Model -> Element Msg
viewRightToolbar model =
    Element.row
        [ Element.height Element.fill
        , Element.htmlAttribute <|
            Html.Attributes.style "pointer-events" "auto"
        ]
        [ Input.button
            [ Element.height Element.fill
            , Element.padding 2
            , Background.color gray900
            , Border.color gray900
            , Border.width 1
            , Element.mouseOver
                [ Background.color gray800 ]
            ]
            { onPress = Just ToolbarToggleClicked
            , label =
                Element.el
                    [ Element.height Element.fill
                    ]
                    (Element.el
                        [ Element.centerY
                        , Element.centerX
                        ]
                        (Element.html <|
                            Html.toUnstyled <|
                                Html.i
                                    [ Attributes.class "fas"
                                    , Attributes.class <|
                                        if model.rightToolbarVisible then
                                            "fa-chevron-right"

                                        else
                                            "fa-chevron-left"
                                    , Attributes.css
                                        [ Css.fontSize (Css.px 12)
                                        , Css.color (Css.rgb 229 223 197)
                                        ]
                                    ]
                                    []
                        )
                    )
            }
        , if model.rightToolbarVisible then
            Element.column
                [ Element.width (Element.px 400)
                , Element.height Element.fill
                , Background.color gray900
                ]
                [ viewVariables model
                , viewPoints model
                ]

          else
            Element.none
        ]



-- DIALOG


viewDialog pattern dialog =
    case dialog of
        NoDialog ->
            Element.none

        Tool tool ->
            Element.el
                [ Element.alignLeft
                , Element.moveRight 200
                , Element.width (Element.px 300)
                , Background.color gray900
                ]
                (viewTool pattern
                    (Pattern.points pattern)
                    (Pattern.circles pattern)
                    (Pattern.lines pattern)
                    (Pattern.lineSegments pattern)
                    (Pattern.details pattern)
                    tool
                )

        CreateVariable { name, value } ->
            Element.el
                [ Element.centerX
                , Element.moveRight 150
                , Element.width (Element.px 350)
                , Background.color gray900
                ]
                (viewVariable name value)



-- TOOL


viewTool :
    Pattern
    -> List ( That Point, Entry Point )
    -> List ( That Circle, Entry Circle )
    -> List ( That Line, Entry Line )
    -> List ( That LineSegment, Entry LineSegment )
    -> List ( That Detail, Entry Detail )
    -> Tool
    -> Element Msg
viewTool pattern points circles lines lineSegments details tool =
    Element.column
        [ Element.width Element.fill
        , Element.padding 15
        , Element.spacing 20
        ]
        [ Element.el
            [ Font.size 12
            , Font.color white
            ]
            (toolDescription (toolToTag tool))
        , Element.column
            [ Element.width Element.fill
            , Element.spacing 10
            ]
            (case tool of
                CreatePoint name pointData ->
                    labeledInputText NameChanged "name" name
                        :: (case pointData of
                                LeftOf data ->
                                    viewSimpleDistanceTool pattern points "leftof" data

                                RightOf data ->
                                    viewSimpleDistanceTool pattern points "rightof" data

                                Above data ->
                                    viewSimpleDistanceTool pattern points "above" data

                                Below data ->
                                    viewSimpleDistanceTool pattern points "below" data

                                AtAngle data ->
                                    viewAngle pattern points data

                                BetweenRatio data ->
                                    viewBetweenRatio pattern points data

                                BetweenLength data ->
                                    viewBetweenLength pattern points data

                                CircleCircle data ->
                                    viewCircleCircle pattern circles data
                           )

                EditPoint _ pointData ->
                    case pointData of
                        LeftOf data ->
                            viewSimpleDistanceTool pattern points "leftof" data

                        RightOf data ->
                            viewSimpleDistanceTool pattern points "rightof" data

                        Above data ->
                            viewSimpleDistanceTool pattern points "above" data

                        Below data ->
                            viewSimpleDistanceTool pattern points "below" data

                        AtAngle data ->
                            viewAngle pattern points data

                        BetweenRatio data ->
                            viewBetweenRatio pattern points data

                        BetweenLength data ->
                            viewBetweenLength pattern points data

                        CircleCircle data ->
                            viewCircleCircle pattern circles data

                CenteredAt data ->
                    viewCenteredAt pattern points data

                ThroughTwoPoints data ->
                    viewThroughTwoPoints pattern points data

                FromTo data ->
                    viewFromTo pattern points data

                MirrorAt data ->
                    viewMirrorAt pattern points lines data

                CutAlongLineSegment data ->
                    viewCutAlongLineSegment pattern lineSegments details data

                CounterClockwise targets ->
                    viewCounterClockwise pattern points targets
            )
        , Element.row
            [ Element.alignRight
            , Element.spacing 5
            ]
            [ case tool of
                CreatePoint _ _ ->
                    buttonCreate "Create" CreateClicked

                EditPoint _ _ ->
                    buttonCreate "Update" UpdateClicked

                _ ->
                    buttonCreate "Create" CreateClicked
            , buttonDismiss "Cancel" CancelClicked
            ]
        ]


viewSimpleDistanceTool pattern points toolId data =
    [ labeledDropdown (toolId ++ "-anchor")
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledFormulaInputText DistanceChanged "distance" data.distance
    ]


viewAngle pattern points data =
    [ labeledDropdown "at-angle-anchor"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledFormulaInputText AngleChanged "angle" data.angle
    , labeledFormulaInputText DistanceChanged "distance" data.distance
    ]


viewBetweenRatio pattern points data =
    [ labeledDropdown "between-ratio-anchor-a"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "1st anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledDropdown "between-ratio-anchor-b"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorBMsg
        , label = "2st anchor"
        , options = points
        }
        data.dropdownAnchorB
        data.maybeThatAnchorB
    , labeledFormulaInputText RatioChanged "ratio" data.ratio
    ]


viewBetweenLength pattern points data =
    [ labeledDropdown "between-length-anchor-a"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "1st anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledDropdown "between-length-anchor-b"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorBMsg
        , label = "2st anchor"
        , options = points
        }
        data.dropdownAnchorB
        data.maybeThatAnchorB
    , labeledFormulaInputText LengthChanged "length" data.length
    ]


viewCircleCircle pattern circles data =
    [ labeledDropdown "circle-circle--circle-a"
        { optionToName = circleName pattern
        , placeholder = "Select a circle.."
        , lift = DropdownCircleAMsg
        , label = "1st circle"
        , options = circles
        }
        data.dropdownCircleA
        data.maybeThatCircleA
    , labeledDropdown "circle-circle--circle-b"
        { optionToName = circleName pattern
        , placeholder = "Select a circle.."
        , lift = DropdownCircleBMsg
        , label = "2st circle"
        , options = circles
        }
        data.dropdownCircleB
        data.maybeThatCircleB
    , Input.radioRow
        [ Element.width Element.fill
        , Element.padding 5
        , Element.spacing 10
        , Font.size 16
        , Font.color white
        ]
        { onChange = FirstChanged
        , options =
            [ Input.option True <|
                Element.el
                    [ Border.width 1
                    , Border.color gray900
                    ]
                    (Element.text "first")
            , Input.option False <|
                Element.el
                    [ Border.width 1
                    , Border.color gray900
                    ]
                    (Element.text "second")
            ]
        , selected = Just data.first
        , label =
            Input.labelAbove
                [ Font.size 12
                , Font.variant Font.smallCaps
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.text "intersection")
        }
    ]


viewCenteredAt pattern points data =
    [ labeledInputText NameChanged "name" data.name
    , labeledDropdown "centered-at-anchor"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledFormulaInputText RadiusChanged "radius" data.radius
    ]


viewThroughTwoPoints pattern points data =
    [ labeledInputText NameChanged "name" data.name
    , labeledDropdown "through-two-points-anchor-a"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "1st anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledDropdown "through-two-points-anchor-b"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorBMsg
        , label = "2st anchor"
        , options = points
        }
        data.dropdownAnchorB
        data.maybeThatAnchorB
    ]


viewFromTo pattern points data =
    [ labeledInputText NameChanged "name" data.name
    , labeledDropdown "from-to-anchor-a"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorAMsg
        , label = "1st anchor"
        , options = points
        }
        data.dropdownAnchorA
        data.maybeThatAnchorA
    , labeledDropdown "from-to-anchor-b"
        { optionToName = pointName pattern
        , placeholder = "Select a point.."
        , lift = DropdownAnchorBMsg
        , label = "2st anchor"
        , options = points
        }
        data.dropdownAnchorB
        data.maybeThatAnchorB
    ]


viewMirrorAt pattern points lines data =
    [ labeledDropdown "mirror-at-line"
        { optionToName = lineName pattern
        , placeholder = "Select a line.."
        , lift = DropdownLineMsg
        , label = "line"
        , options = lines
        }
        data.dropdown
        data.thatLine
    , labeledListbox "mirror-at-points"
        { optionToName = pointName pattern
        , lift = ListboxPointsMsg
        , label = "targets"
        , options = points
        }
        data.listbox
        data.thosePoints
    ]


viewCutAlongLineSegment pattern lineSegments details data =
    [ labeledDropdown "cut-along-line-segment--line-segment"
        { optionToName = lineSegmentName pattern
        , placeholder = "Select a line segment.."
        , lift = DropdownLineSegmentMsg
        , label = "line segment"
        , options = lineSegments
        }
        data.dropdownLineSegment
        data.thatLineSegment
    , labeledDropdown "cut-along-line-segment--detail"
        { optionToName = detailName pattern
        , placeholder = "Select a detail.."
        , lift = DropdownDetailMsg
        , label = "detail"
        , options = details
        }
        data.dropdownDetail
        data.thatDetail
    ]


viewCounterClockwise pattern points targets =
    let
        pointButton ( thatPoint, { name } ) =
            Input.button
                [ Element.padding 5
                , Background.color gray800
                , Border.color gray900
                , Border.width 1
                , Element.mouseOver
                    [ Background.color gray700 ]
                ]
                { onPress = Just (PointAdded thatPoint)
                , label =
                    Element.text (Maybe.withDefault "<unnamed>" name)
                }
    in
    [ Element.text
        (targets
            |> List.filterMap (Pattern.getPoint pattern)
            |> List.map (.name >> Maybe.withDefault "<unnamed>")
            |> String.join ", "
        )
    , Element.column [] <|
        List.map pointButton points
    ]


pointName pattern =
    Pattern.getPoint pattern
        >> Maybe.andThen .name
        >> Maybe.withDefault "<unnamed>"


circleName pattern =
    Pattern.getCircle pattern
        >> Maybe.andThen .name
        >> Maybe.withDefault "<unnamed>"


lineName pattern =
    Pattern.getLine pattern
        >> Maybe.andThen .name
        >> Maybe.withDefault "<unnamed>"


lineSegmentName pattern =
    Pattern.getLineSegment pattern
        >> Maybe.andThen .name
        >> Maybe.withDefault "<unnamed>"


detailName pattern =
    Pattern.getDetail pattern
        >> Maybe.andThen .name
        >> Maybe.withDefault "<unnamed>"



-- VARIABLE


viewVariable name value =
    Element.column
        [ Element.width Element.fill
        , Element.padding 15
        , Element.spacing 15
        ]
        [ Element.paragraph
            [ Font.size 12
            , Font.color white
            ]
            [ Element.text "Create a new "
            , Element.el
                [ Font.bold ]
                (Element.text "variable")
            ]
        , Element.column
            [ Element.width Element.fill
            , Element.spacing 10
            ]
            [ labeledInputText VariableNameChanged "name" name
            , labeledFormulaInputText VariableValueChanged "value" value
            ]
        , Element.row
            [ Element.alignRight
            , Element.spacing 5
            ]
            [ buttonCreate "Create" CreateClicked
            , buttonDismiss "Cancel" CancelClicked
            ]
        ]



-- TOOL SELECTOR


viewToolSelector hoveredTool maybeTool =
    let
        viewGroup name rows =
            Element.column
                [ Element.spacing 5
                , Element.width Element.fill
                ]
                [ Element.el
                    [ Font.size 12
                    , Font.variant Font.smallCaps
                    , Font.color (color (Color.rgb255 229 223 197))
                    ]
                    (Element.text name)
                , Element.column
                    [ Element.spacing 5 ]
                    (List.map viewRow rows)
                ]

        viewRow buttons =
            Element.row
                [ Element.spacing 5
                , Element.width Element.fill
                ]
                buttons

        is toolTag =
            case maybeTool of
                Nothing ->
                    False

                Just tool ->
                    toolToTag tool == toolTag
    in
    Element.column
        [ Element.padding 10
        , Element.spacing 10
        , Element.width Element.fill
        ]
        [ viewGroup "points"
            [ [ button hoveredTool LeftOfTag "left_of" "Left of"
              , button hoveredTool RightOfTag "right_of" "Right of"
              ]
            , [ button hoveredTool AboveTag "above" "Above"
              , button hoveredTool BelowTag "below" "Below"
              ]
            , [ button hoveredTool AtAngleTag "at_angle" "At angle"
              ]
            , [ button hoveredTool BetweenRatioTag "at_angle" "Between at ratio"
              , button hoveredTool BetweenLengthTag "at_angle" "Between at length"
              ]
            , [ button hoveredTool CircleCircleTag "at_angle" "Circle-Circle intersection"
              ]
            ]
        , viewGroup "circles"
            [ [ button hoveredTool CenteredAtTag "through_two_points" "Centered at"
              ]
            ]
        , viewGroup "lines"
            [ [ button hoveredTool ThroughTwoPointsTag "through_two_points" "Through two points"
              ]
            ]
        , viewGroup "line segments"
            [ [ button hoveredTool FromToTag "from_to" "From to"
              ]
            ]
        , viewGroup "transformations"
            [ [ button hoveredTool MirrorAtTag "mirror_at" "Mirror at"
              , button hoveredTool CutAlongLineSegmentTag "cut_along_line_segment" "Cut along line segment"
              ]
            ]
        , viewGroup "details"
            [ [ button hoveredTool CounterClockwiseTag "counter_clockwise" "Counter clockwise"
              ]
            ]
        ]



-- VARIABLES


viewVariables model =
    let
        viewFloatValue value =
            Element.el
                [ Font.size 14
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.el [ Element.alignRight ]
                    (Element.text (String.fromFloat value))
                )
    in
    Element.column
        [ Element.width Element.fill
        , Element.padding 10
        , Element.spacing 10
        ]
        [ accordionToggle VariablesRulerClicked "variables" model.variablesVisible
        , if model.variablesVisible then
            Element.column
                [ Element.width Element.fill
                , Element.spacing 15
                , Element.padding 5
                ]
                [ Element.table
                    [ Element.spacing 7 ]
                    { data = List.sortBy .name (Pattern.variables model.pattern)
                    , columns =
                        [ { header =
                                Element.el
                                    [ Font.size 12
                                    , Font.variant Font.smallCaps
                                    , Font.color (color (Color.rgb255 229 223 197))
                                    ]
                                    (Element.text "name")
                          , width = Element.fill
                          , view =
                                \{ name } ->
                                    Element.el
                                        [ Font.size 14
                                        , Font.color (color (Color.rgb255 229 223 197))
                                        ]
                                        (Element.text name)
                          }
                        , { header =
                                Element.el
                                    [ Font.size 12
                                    , Font.variant Font.smallCaps
                                    , Font.color (color (Color.rgb255 229 223 197))
                                    ]
                                    (Element.text "value")
                          , width = Element.shrink
                          , view =
                                \{ computed } ->
                                    viewFloatValue computed
                          }
                        , { header = Element.none
                          , width = Element.shrink
                          , view =
                                \_ ->
                                    Element.row
                                        [ Element.paddingEach
                                            { left = 5
                                            , right = 0
                                            , top = 0
                                            , bottom = 0
                                            }
                                        , Element.spacing 10
                                        ]
                                        [ Input.button
                                            [ Font.color white
                                            , Border.width 1
                                            , Border.color gray900
                                            , Element.mouseOver
                                                [ Font.color gray700 ]
                                            ]
                                            { onPress = Nothing
                                            , label =
                                                Element.el
                                                    [ Element.centerX
                                                    , Element.centerY
                                                    ]
                                                    (icon "edit")
                                            }
                                        , Input.button
                                            [ Font.color white
                                            , Border.width 1
                                            , Border.color gray900
                                            , Element.mouseOver
                                                [ Font.color gray700 ]
                                            ]
                                            { onPress = Nothing
                                            , label =
                                                Element.el
                                                    [ Element.centerX
                                                    , Element.centerY
                                                    ]
                                                    (icon "trash")
                                            }
                                        ]
                          }
                        ]
                    }
                , Element.row
                    [ Element.width Element.fill ]
                    [ Input.button
                        [ Element.alignRight
                        , Element.paddingXY 8 7
                        , Font.size 14
                        , Background.color gray800
                        , Border.color gray800
                        , Border.width 1
                        , Font.color white
                        , Element.mouseOver
                            [ Background.color gray700 ]
                        ]
                        { onPress = Just VariableCreateClicked
                        , label = Element.text "Create variable"
                        }
                    ]
                ]

          else
            Element.none
        ]


viewPoints model =
    let
        viewHeader name =
            Element.el
                [ Font.size 12
                , Font.variant Font.smallCaps
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.text name)

        viewValue value =
            Element.el
                [ Font.size 14
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.text value)

        viewFloatHeader name =
            Element.el
                [ Font.size 12
                , Font.variant Font.smallCaps
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.el [ Element.alignRight ]
                    (Element.text name)
                )

        viewFloatValue value =
            Element.el
                [ Font.size 14
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.el [ Element.alignRight ]
                    (Element.text (String.fromInt (round value)))
                )
    in
    Element.column
        [ Element.width Element.fill
        , Element.padding 10
        , Element.spacing 10
        ]
        [ accordionToggle PointsRulerClicked "points" model.pointsVisible
        , if model.pointsVisible then
            Element.column
                [ Element.width Element.fill
                , Element.spacing 15
                , Element.padding 5
                ]
                [ Element.table
                    [ Element.spacing 7 ]
                    { data =
                        List.sortBy (Tuple.second >> .name >> Maybe.withDefault "")
                            (Pattern.points model.pattern)
                    , columns =
                        [ { header = viewHeader "name"
                          , width = Element.fill
                          , view =
                                \( _, { name } ) ->
                                    viewValue (Maybe.withDefault "<no name>" name)
                          }
                        , { header = viewFloatHeader "x"
                          , width = Element.px 35
                          , view =
                                \( thatPoint, _ ) ->
                                    thatPoint
                                        |> Pattern.getPointGeometry model.pattern
                                        |> Maybe.map
                                            (Point2d.xCoordinate >> viewFloatValue)
                                        |> Maybe.withDefault Element.none
                          }
                        , { header = viewFloatHeader "y"
                          , width = Element.px 35
                          , view =
                                \( thatPoint, _ ) ->
                                    thatPoint
                                        |> Pattern.getPointGeometry model.pattern
                                        |> Maybe.map
                                            (Point2d.yCoordinate >> viewFloatValue)
                                        |> Maybe.withDefault Element.none
                          }
                        , { header = Element.none
                          , width = Element.shrink
                          , view =
                                \( thatPoint, _ ) ->
                                    Element.row
                                        [ Element.paddingEach
                                            { left = 5
                                            , right = 0
                                            , top = 0
                                            , bottom = 0
                                            }
                                        , Element.spacing 10
                                        ]
                                        [ Input.button
                                            [ Font.color white
                                            , Border.width 1
                                            , Border.color gray900
                                            , Element.mouseOver
                                                [ Font.color gray700 ]
                                            ]
                                            { onPress = Just (EditPointClicked thatPoint)
                                            , label =
                                                Element.el
                                                    [ Element.centerX
                                                    , Element.centerY
                                                    ]
                                                    (icon "edit")
                                            }
                                        , Input.button
                                            [ Font.color white
                                            , Border.width 1
                                            , Border.color gray900
                                            , Element.mouseOver
                                                [ Font.color gray700 ]
                                            ]
                                            { onPress = Nothing
                                            , label =
                                                Element.el
                                                    [ Element.centerX
                                                    , Element.centerY
                                                    ]
                                                    (icon "trash")
                                            }
                                        ]
                          }
                        ]
                    }
                ]

          else
            Element.none
        ]



---- REUSABLE ELEMENTS


icon name =
    Element.html <|
        Html.toUnstyled <|
            Html.i
                [ Attributes.class "fas"
                , Attributes.class ("fa-" ++ name)
                , Attributes.css
                    [ Css.fontSize (Css.px 12)
                    , Css.color Css.inherit
                    ]
                ]
                []


bigIcon name =
    Element.html <|
        Html.toUnstyled <|
            Html.i
                [ Attributes.class "fas"
                , Attributes.class ("fa-" ++ name)
                , Attributes.css
                    [ Css.fontSize (Css.px 24)
                    , Css.color Css.inherit
                    ]
                ]
                []


devIcon name =
    Element.html <|
        Html.toUnstyled <|
            Html.i
                [ Attributes.class ("devicon-" ++ name)
                , Attributes.css
                    [ Css.fontSize (Css.px 24)
                    , Css.color Css.inherit
                    ]
                ]
                []


accordionToggle msg name visible =
    Input.button
        [ Element.width Element.fill
        , Element.padding 5
        , Border.color gray900
        , Border.width 1
        , Element.mouseOver
            [ Background.color gray800 ]
        ]
        { onPress = Just msg
        , label =
            Element.row
                [ Element.width Element.fill
                ]
                [ Element.el
                    [ Element.width Element.fill
                    , Font.size 16
                    , Font.variant Font.smallCaps
                    , Font.color (color (Color.rgb255 229 223 197))
                    ]
                    (Element.text name)
                , Element.html <|
                    Html.toUnstyled <|
                        Html.i
                            [ Attributes.class "fas"
                            , Attributes.class <|
                                if visible then
                                    "fa-chevron-up"

                                else
                                    "fa-chevron-down"
                            , Attributes.css
                                [ Css.fontSize (Css.px 12)
                                , Css.paddingRight (Css.px 5)
                                , Css.color (Css.rgb 229 223 197)
                                ]
                            ]
                            []
                ]
        }


button : Maybe ToolTag -> ToolTag -> String -> String -> Element Msg
button maybeHoveredTool toolTag iconSrc label =
    let
        selected =
            Just toolTag == maybeHoveredTool
    in
    Input.button
        [ Element.padding 5
        , Background.color <|
            if selected then
                gray700

            else
                gray800
        , Border.color gray900
        , Border.width 1
        , Element.Events.onMouseEnter (SelectToolHovered toolTag)
        , Element.Events.onMouseLeave SelectToolUnhovered
        , Element.mouseOver
            [ Background.color <|
                if selected then
                    gray700

                else
                    gray700
            ]
        ]
        { onPress = Just (SelectToolClicked toolTag)
        , label =
            Element.image
                [ Element.width (Element.px 48)
                , Element.height (Element.px 48)
                ]
                { src = "/assets/icons/" ++ iconSrc ++ ".svg"
                , description = label
                }
        }


buttonDismiss : String -> msg -> Element msg
buttonDismiss label msg =
    Input.button
        [ Element.paddingXY 8 7
        , Element.width Element.fill
        , Font.size 14
        , Background.color gray800
        , Border.color gray800
        , Border.width 1
        , Font.color white
        , Element.mouseOver
            [ Background.color gray700 ]
        ]
        { onPress = Just msg
        , label = Element.text label
        }


buttonDanger : String -> msg -> Element msg
buttonDanger label msg =
    Input.button
        [ Element.padding 8
        , Element.width Element.fill
        , Font.size 14
        , Background.color gray800
        , Border.color gray800
        , Border.width 1
        , Font.color white
        , Element.mouseOver
            [ Background.color gray700 ]
        ]
        { onPress = Just msg
        , label = Element.el [ Element.centerX ] (Element.text label)
        }


buttonCreate : String -> msg -> Element msg
buttonCreate label msg =
    Input.button
        [ Element.paddingXY 8 7
        , Background.color gray800
        , Border.color gray800
        , Border.width 1
        , Font.color white
        , Font.size 14
        , Element.mouseOver
            [ Background.color gray700 ]
        ]
        { onPress = Just msg
        , label = Element.text label
        }


labeledInputText : (String -> msg) -> String -> String -> Element msg
labeledInputText onChange label name =
    Input.text
        [ Element.width Element.fill
        , Element.padding 5
        , Font.size 16
        , Font.color white
        , Background.color gray700
        , Border.width 1
        , Border.color gray700
        , Element.htmlAttribute <|
            Html.Attributes.id (label ++ "-input")
        ]
        { onChange = onChange
        , text = name
        , placeholder = Nothing
        , label =
            Input.labelAbove
                [ Font.size 12
                , Font.variant Font.smallCaps
                , Font.color (color (Color.rgb255 229 223 197))
                ]
                (Element.text label)
        }


labeledFormulaInputText : (String -> msg) -> String -> String -> Element msg
labeledFormulaInputText onChange label text =
    let
        lineCount =
            List.length (String.split "\n" text)
    in
    Input.multiline
        [ Element.width Element.fill
        , Element.paddingEach <|
            if lineCount == 1 then
                { left = 5
                , right = 5
                , top = 10
                , bottom = 0
                }

            else
                { left =
                    if lineCount < 10 then
                        30

                    else
                        40
                , right = 5
                , top = 10
                , bottom = 0
                }
        , Element.inFront <|
            if lineCount == 1 then
                Element.none

            else
                Element.row
                    [ Element.height Element.fill
                    , Element.paddingXY 5 0
                    , Element.spacing 5
                    ]
                    [ Element.column
                        [ Font.size 16
                        , Font.color white
                        , Font.family
                            [ Font.external
                                { name = "Roboto Mono"
                                , url = "https://fonts.googleapis.com/css?family=Roboto+Mono"
                                }
                            , Font.monospace
                            ]
                        , Element.spacing 5
                        ]
                        (List.range 1 lineCount
                            |> List.map
                                (\lineNumber ->
                                    Element.el
                                        [ Element.alignRight ]
                                        (Element.text (String.fromInt lineNumber))
                                )
                        )
                    , Element.el
                        [ Element.paddingXY 0 5
                        , Element.height Element.fill
                        ]
                        (Element.el
                            [ Element.height Element.fill
                            , Element.width (Element.px 1)
                            , Background.color white
                            ]
                            Element.none
                        )
                    ]
        , Element.spacing 5
        , Font.size 16
        , Font.color white
        , Font.family
            [ Font.external
                { name = "Roboto Mono"
                , url = "https://fonts.googleapis.com/css?family=Roboto+Mono"
                }
            , Font.monospace
            ]
        , Background.color gray700
        , Border.width 1
        , Border.color gray700
        , Element.htmlAttribute <|
            Html.Attributes.id (label ++ "-input")
        , Element.htmlAttribute <|
            Html.Attributes.rows lineCount
        , Element.htmlAttribute <|
            Html.Attributes.style "white-space" "pre"
        ]
        { onChange = onChange
        , text = text
        , placeholder = Nothing
        , spellcheck = False
        , label =
            Input.labelAbove
                [ Font.size 12
                , Font.color (color (Color.rgb255 229 223 197))
                , Font.variant Font.smallCaps
                , Element.htmlAttribute <|
                    Html.Attributes.style "font-variant" "small-caps"
                , Font.family
                    [ Font.external
                        { name = "Roboto"
                        , url = "https://fonts.googleapis.com/css?family=Roboto"
                        }
                    , Font.sansSerif
                    ]
                ]
                (Element.text label)
        }


labeledDropdown :
    String
    ->
        { lift : Dropdown.Msg (That object) -> Msg
        , optionToName : That object -> String
        , placeholder : String
        , label : String
        , options : List ( That object, Entry object )
        }
    -> Dropdown
    -> Maybe (That object)
    -> Element Msg
labeledDropdown id customization dropdown selection =
    let
        { optionToName, placeholder, lift, label, options } =
            customization
    in
    Element.column
        [ Element.width Element.fill
        , Element.spacing 3
        ]
        [ Element.el
            [ Font.size 12
            , Font.color (color (Color.rgb255 229 223 197))
            , Font.variant Font.smallCaps
            , Element.htmlAttribute <|
                Html.Attributes.id (id ++ "-label")
            ]
            (Element.text label)
        , Element.el [ Element.width Element.fill ] <|
            Element.html <|
                Html.toUnstyled <|
                    Html.map lift <|
                        Dropdown.view
                            (dropdownViewConfig optionToName placeholder)
                            { id = id
                            , labelledBy = id ++ "-label"
                            }
                            (List.map (Tuple.first >> Listbox.option) options)
                            dropdown
                            selection
        ]


labeledListbox :
    String
    ->
        { optionToName : That object -> String
        , lift : Listbox.Msg (That object) -> Msg
        , label : String
        , options : List ( That object, Entry object )
        }
    -> Listbox
    -> Those object
    -> Element Msg
labeledListbox id { optionToName, lift, label, options } listbox selection =
    Element.column
        [ Element.width Element.fill
        , Element.spacing 3
        ]
        [ Element.el
            [ Font.size 12
            , Font.color (color (Color.rgb255 229 223 197))
            , Font.variant Font.smallCaps
            , Element.htmlAttribute <|
                Html.Attributes.id (id ++ "-label")
            ]
            (Element.text label)
        , Element.el [ Element.width Element.fill ] <|
            Element.html <|
                Html.toUnstyled <|
                    Listbox.view (listboxViewConfig optionToName)
                        { id = id
                        , labelledBy = id ++ "-label"
                        , lift = lift
                        }
                        (List.map (Tuple.first >> Listbox.option) options)
                        listbox
                        (Those.toList selection)
        ]


labeledInputRadio :
    (That a -> msg)
    -> String
    -> Maybe (That a)
    -> List ( That a, Entry a )
    -> Element msg
labeledInputRadio msg label selected options =
    let
        option ( that, { name } ) =
            Input.option that <|
                Element.el
                    [ Element.padding 3 ]
                    (Element.text (Maybe.withDefault "<unnamed>" name))
    in
    Input.radio
        [ Element.paddingXY 8 7
        , Element.width Element.fill
        ]
        { onChange = msg
        , selected = selected
        , label =
            Input.labelLeft
                [ Element.centerY
                , Element.paddingXY 5 0
                , Element.width (Element.px 120)
                ]
                (Element.text label)
        , options = List.map option options
        }


horizontalLine : Element msg
horizontalLine =
    Element.el
        [ Element.height (Element.px 1)
        , Element.width Element.fill
        , Background.color (color Color.white)
        ]
        Element.none


color =
    Element.fromRgb << Color.toRgba


white =
    color (Color.rgb255 229 223 197)


green900 =
    color (Color.rgb255 27 94 32)


gray700 =
    color (Color.rgb255 97 97 97)


gray750 =
    color (Color.rgb255 82 82 82)


gray800 =
    color (Color.rgb255 66 66 66)


gray900 =
    color (Color.rgb255 33 33 33)


gray950 =
    color (Color.rgb255 22 22 22)



---- DROPDOWN CONFIG


dropdownUpdateConfig =
    Dropdown.updateConfig That.hash
        { jumpAtEnds = True
        , separateFocus = True
        , selectionFollowsFocus = False
        , handleHomeAndEnd = True
        , closeAfterMouseSelection = True
        , typeAhead = Listbox.noTypeAhead
        , minimalGap = 0
        , initialGap = 0
        }


dropdownViewConfig printOption placeholder =
    Dropdown.viewConfig That.hash
        { container =
            [ Attributes.css
                [ Css.displayFlex
                , Css.flexGrow (Css.num 10000)
                , Css.position Css.relative
                ]
            ]
        , button =
            \{ maybeSelection } ->
                { attributes =
                    [ Attributes.css
                        [ Css.displayFlex
                        , Css.flexGrow (Css.num 10000)
                        , Css.margin Css.zero
                        , Css.paddingLeft (Css.px 5)
                        , Css.paddingRight (Css.px 5)
                        , Css.paddingBottom (Css.px 5)
                        , Css.paddingTop (Css.px 5)
                        , Css.borderColor (Css.rgb 97 97 97)
                        , Css.borderStyle Css.solid
                        , Css.borderWidth (Css.px 1)
                        , Css.borderRadius (Css.px 3)
                        , Css.boxSizing Css.borderBox
                        , Css.fontFamilies [ "Roboto", "sans-serif" ]
                        , Css.fontSize (Css.px 16)
                        , Css.fontStyle Css.normal
                        , Css.fontWeight (Css.int 400)
                        , Css.lineHeight (Css.px 20)
                        , Css.backgroundColor (Css.rgb 97 97 97)
                        , Css.color (Css.rgb 229 223 197)
                        , Css.focus
                            [ Css.borderColor (Css.rgb 229 223 197) ]
                        ]
                    ]
                , children =
                    [ Html.text <|
                        case maybeSelection of
                            Nothing ->
                                placeholder

                            Just thatPoint ->
                                printOption thatPoint
                    ]
                }
        , ul =
            [ Attributes.css
                [ Css.zIndex (Css.int 2000)
                , Css.top (Css.pct 100)
                , Css.width (Css.pct 100)
                , Css.maxHeight (Css.rem 20)
                , Css.overflowY Css.auto
                , Css.padding Css.zero
                , Css.margin Css.zero
                , Css.color (Css.rgb 229 223 197)
                , Css.backgroundColor (Css.rgb 66 66 66)
                , Css.borderWidth (Css.px 1)
                , Css.borderStyle Css.solid
                , Css.borderColor (Css.rgb 66 66 66)
                , Css.borderRadius (Css.px 3)
                , Css.boxSizing Css.borderBox
                , Css.focus
                    [ Css.borderColor (Css.rgb 229 223 197) ]
                ]
            ]
        , liOption =
            \{ focused, hovered } thatPoint ->
                let
                    defaultAttrs =
                        [ Attributes.css
                            [ Css.display Css.block
                            , Css.cursor Css.pointer
                            , Css.lineHeight (Css.rem 1)
                            , Css.padding (Css.px 10)
                            , Css.fontSize (Css.px 16)
                            ]
                        ]
                in
                { attributes =
                    if focused then
                        [ Attributes.css
                            [ Css.backgroundColor (Css.rgb 97 97 97) ]
                        ]
                            ++ defaultAttrs

                    else if hovered then
                        [ Attributes.css
                            [ Css.backgroundColor (Css.rgb 82 82 82) ]
                        ]
                            ++ defaultAttrs

                    else
                        defaultAttrs
                , children =
                    [ Html.text (printOption thatPoint) ]
                }
        , liDivider = Listbox.noDivider
        }



---- LISTBOX CONFIG


listboxUpdateConfig =
    Listbox.updateConfig That.hash
        { jumpAtEnds = True
        , separateFocus = True
        , selectionFollowsFocus = False
        , handleHomeAndEnd = True
        , typeAhead = Listbox.noTypeAhead
        , minimalGap = 0
        , initialGap = 0
        }


listboxViewConfig printOption =
    Listbox.viewConfig That.hash
        { ul =
            [ Attributes.css
                [ Css.top (Css.pct 100)
                , Css.width (Css.pct 100)
                , Css.maxHeight (Css.rem 10)
                , Css.overflowY Css.auto
                , Css.padding Css.zero
                , Css.margin Css.zero
                , Css.backgroundColor (Css.rgb 66 66 66)
                , Css.boxSizing Css.borderBox
                , Css.borderWidth (Css.px 1)
                , Css.borderStyle Css.solid
                , Css.borderColor (Css.rgb 66 66 66)
                , Css.borderRadius (Css.px 3)
                , Css.color (Css.rgb 229 223 197)
                , Css.focus
                    [ Css.borderColor (Css.rgb 229 223 197) ]
                ]
            ]
        , liOption =
            \{ selected, focused, hovered } thatPoint ->
                let
                    defaultAttrs =
                        [ Attributes.css
                            [ Css.display Css.block
                            , Css.cursor Css.pointer
                            , Css.lineHeight (Css.rem 1)
                            , Css.padding (Css.px 10)
                            , Css.fontSize (Css.px 16)
                            ]
                        ]
                in
                { attributes =
                    if focused then
                        [ Attributes.css
                            [ Css.backgroundColor (Css.rgb 97 97 97) ]
                        ]
                            ++ defaultAttrs

                    else if hovered then
                        [ Attributes.css
                            [ Css.backgroundColor (Css.rgb 82 82 82) ]
                        ]
                            ++ defaultAttrs

                    else
                        defaultAttrs
                , children =
                    [ Html.i
                        [ Attributes.class "fas"
                        , Attributes.class "fa-check"
                        , Attributes.css
                            [ Css.fontSize (Css.px 12)
                            , Css.paddingRight (Css.px 5)
                            , if selected then
                                Css.color Css.inherit

                              else
                                Css.color Css.transparent
                            ]
                        ]
                        []
                    , Html.text (printOption thatPoint)
                    ]
                }
        , liDivider = Listbox.noDivider
        , empty = Html.text ""
        , focusable = True
        }



---- SVG


drawPattern :
    Model
    -> Maybe (That Point)
    -> Those Point
    -> Those Line
    -> Those LineSegment
    -> Those Detail
    -> Pattern
    -> Svg Msg
drawPattern model hoveredPoint selectedPoints selectedLines selectedLineSegments selectedDetails pattern =
    let
        ( geometry, problems ) =
            Pattern.geometry pattern

        translation =
            String.concat
                [ "translate("
                , String.fromFloat (-1 * x)
                , " "
                , String.fromFloat (-1 * y)
                , ")"
                ]

        { x, y } =
            case model.maybeDrag of
                Nothing ->
                    model.center

                Just drag ->
                    { x = model.center.x + (drag.start.x - drag.current.x) * model.zoom
                    , y = model.center.y + (drag.start.y - drag.current.y) * model.zoom
                    }

        hoverPolygons =
            VoronoiDiagram2d.fromVerticesBy
                (\( _, _, p2d ) -> p2d)
                (Array.fromList geometry.points)
                |> Result.toMaybe
                |> Maybe.map (VoronoiDiagram2d.polygons boundingBox2d)
                |> Maybe.withDefault []

        boundingBox2d =
            BoundingBox2d.fromExtrema
                { minX = -1 * width / 2 + x
                , minY = -1 * height / 2 + y
                , maxX = (-1 * width / 2) + width + x
                , maxY = (-1 * height / 2) + height + y
                }

        width =
            toFloat model.windowWidth * model.zoom

        height =
            toFloat model.windowHeight * model.zoom
    in
    Svg.g [ Svg.Attributes.transform translation ] <|
        List.concat
            [ [ Svg.defs []
                    [ Svg.marker
                        [ Svg.Attributes.id "arrow"
                        , Svg.Attributes.viewBox "0 0 10 10"
                        , Svg.Attributes.refX "5"
                        , Svg.Attributes.refY "5"
                        , Svg.Attributes.markerWidth "6"
                        , Svg.Attributes.markerHeight "6"
                        , Svg.Attributes.orient "auto-start-reverse"
                        , Svg.Attributes.fill "blue"
                        ]
                        [ Svg.path
                            [ Svg.Attributes.d "M 0 0 L 10 5 L 0 10 z" ]
                            []
                        ]
                    ]
              ]
            , List.map (drawDetail selectedDetails) geometry.details
            , List.map (drawLine selectedLines) geometry.lines
            , List.map (drawLineSegment selectedLineSegments) geometry.lineSegments
            , List.map drawCircle geometry.circles
            , List.map (drawPoint pattern hoveredPoint selectedPoints) geometry.points
            , List.map drawHoverPolygon hoverPolygons
            ]


drawPoint :
    Pattern
    -> Maybe (That Point)
    -> Those Point
    -> ( That Point, Maybe String, Point2d )
    -> Svg Msg
drawPoint pattern hoveredPoint selectedPoints ( thatPoint, maybeName, point2d ) =
    let
        ( x, y ) =
            Point2d.coordinates point2d

        hovered =
            hoveredPoint
                |> Maybe.map (That.areEqual thatPoint)
                |> Maybe.withDefault False

        selected =
            Those.member thatPoint selectedPoints

        helper =
            if hovered then
                Svg.g []
                    [ case
                        hoveredPoint
                            |> Maybe.andThen (Pattern.getPoint pattern)
                            |> Maybe.map .value
                      of
                        Just (Pattern.LeftOf thatAnchorPoint _) ->
                            drawAnchorLine thatAnchorPoint hoveredPoint

                        Just (Pattern.RightOf thatAnchorPoint _) ->
                            drawAnchorLine thatAnchorPoint hoveredPoint

                        Just (Pattern.Above thatAnchorPoint _) ->
                            drawAnchorLine thatAnchorPoint hoveredPoint

                        Just (Pattern.Below thatAnchorPoint _) ->
                            drawAnchorLine thatAnchorPoint hoveredPoint

                        Just (Pattern.AtAngle thatAnchorPoint _ _) ->
                            drawAnchorLine thatAnchorPoint hoveredPoint

                        _ ->
                            Svg.text ""
                    , case
                        hoveredPoint
                            |> Maybe.map (Pattern.getPointGeometries pattern)
                      of
                        Nothing ->
                            Svg.text ""

                        Just point2ds ->
                            drawPointChain point2ds
                    ]

            else
                Svg.text ""

        drawAnchorLine thatAnchorPoint maybeHoveredPoint =
            Maybe.map2
                (\point2dA point2dB ->
                    Svg.g
                        []
                        [ Svg.lineSegment2d
                            [ Svg.Attributes.stroke "blue"
                            , Svg.Attributes.strokeDasharray "4"
                            , Svg.Attributes.strokeWidth "1"
                            ]
                            (LineSegment2d.fromEndpoints
                                ( point2dA, point2dB )
                            )
                        , Svg.circle2d
                            [ Svg.Attributes.fill "blue" ]
                            (Circle2d.withRadius 2 point2dA)
                        ]
                )
                (Maybe.andThen (Pattern.point2d pattern) maybeHoveredPoint)
                (Pattern.point2d pattern thatAnchorPoint)
                |> Maybe.withDefault (Svg.text "")

        drawPointChain points =
            List.foldl drawLink ( Nothing, [] ) points
                |> Tuple.second
                |> Svg.g []

        drawLink point ( maybePreviousPoint, links ) =
            ( Just point
            , (case maybePreviousPoint of
                Nothing ->
                    Svg.g []
                        [ Svg.circle2d [ Svg.Attributes.fill "blue" ]
                            (Circle2d.withRadius 2 point)
                        ]

                Just previousPoint ->
                    let
                        startPoint =
                            previousPoint

                        midpoint =
                            LineSegment2d.from previousPoint point
                                |> LineSegment2d.midpoint

                        controlPoint =
                            case Direction2d.from previousPoint point of
                                Nothing ->
                                    midpoint

                                Just direction ->
                                    Point2d.along
                                        (Axis2d.through midpoint (Direction2d.perpendicularTo direction))
                                        (Point2d.squaredDistanceFrom startPoint endPoint / 1500)

                        endPoint =
                            point

                        spline =
                            QuadraticSpline2d.with
                                { startPoint = startPoint
                                , controlPoint = controlPoint
                                , endPoint = endPoint
                                }

                        id =
                            midpoint
                                |> Point2d.coordinates
                                |> (\( s, t ) ->
                                        String.join "-"
                                            [ String.fromFloat s
                                            , String.fromFloat t
                                            ]
                                   )
                    in
                    Svg.g []
                        [ Svg.mask
                            [ Svg.Attributes.id ("circleMask-" ++ id) ]
                            [ Svg.boundingBox2d
                                [ Svg.Attributes.fill "white" ]
                                (QuadraticSpline2d.boundingBox spline)
                            , Svg.circle2d
                                [ Svg.Attributes.fill "black" ]
                                (Circle2d.withRadius 15 startPoint)
                            , Svg.circle2d
                                [ Svg.Attributes.fill "black" ]
                                (Circle2d.withRadius 15 endPoint)
                            ]
                        , Svg.quadraticSpline2d
                            [ Svg.Attributes.stroke "blue"
                            , Svg.Attributes.strokeDasharray "4"
                            , Svg.Attributes.fill "none"
                            , Svg.Attributes.markerEnd "url(#arrow)"
                            , Svg.Attributes.mask ("url(#circleMask-" ++ id ++ ")")
                            ]
                            spline
                        , Svg.circle2d [ Svg.Attributes.fill "blue" ]
                            (Circle2d.withRadius 2 point)
                        ]
              )
                :: links
            )
    in
    Svg.g []
        [ Svg.circle2d
            [ Svg.Attributes.fill "black" ]
            (Circle2d.withRadius 2 point2d)
        , if selected then
            Svg.circle2d
                [ Svg.Attributes.stroke "blue"
                , Svg.Attributes.fill "none"
                ]
                (Circle2d.withRadius 5 point2d)

          else
            Svg.g [] []
        , helper
        , maybeName
            |> Maybe.map
                (\name ->
                    Svg.text_
                        [ Svg.Attributes.x (String.fromFloat x)
                        , Svg.Attributes.y (String.fromFloat y)
                        , Svg.Attributes.dy "-5"
                        , Svg.Attributes.style "font: 10px sans-serif;"
                        , Svg.Attributes.textAnchor "middle"
                        ]
                        [ Svg.text name ]
                )
            |> Maybe.withDefault (Svg.text "")
        ]


drawHoverPolygon ( ( thatPoint, _, _ ), polygon2d ) =
    Svg.polygon2d
        [ Svg.Attributes.fill "transparent"
        , Svg.Events.onMouseOver (PointHovered (Just thatPoint))
        , Svg.Events.onMouseOut (PointHovered Nothing)
        ]
        polygon2d


drawLine : Those Line -> ( That Line, Maybe String, Axis2d ) -> Svg msg
drawLine selectedLines ( thatLine, maybeName, axis2d ) =
    let
        selected =
            Those.member thatLine selectedLines
    in
    Svg.lineSegment2d
        [ Svg.Attributes.stroke <|
            if selected then
                "blue"

            else
                "grey"
        ]
        (LineSegment2d.fromEndpoints
            ( Point2d.along axis2d -10000
            , Point2d.along axis2d 10000
            )
        )


drawLineSegment :
    Those LineSegment
    -> ( That LineSegment, Maybe String, LineSegment2d )
    -> Svg msg
drawLineSegment selectedLineSegments ( thatLineSegment, maybeName, lineSegment2d ) =
    let
        selected =
            Those.member thatLineSegment selectedLineSegments
    in
    Svg.lineSegment2d
        [ Svg.Attributes.stroke <|
            if selected then
                "blue"

            else
                "grey"
        ]
        lineSegment2d


drawCircle : ( That Circle, Maybe String, Circle2d ) -> Svg msg
drawCircle ( thatCircle, maybeName, circle2d ) =
    Svg.circle2d
        [ Svg.Attributes.stroke "grey"
        , Svg.Attributes.strokeWidth "1px"
        , Svg.Attributes.fill "transparent"
        ]
        circle2d


drawDetail : Those Detail -> ( That Detail, Maybe String, Polygon2d ) -> Svg msg
drawDetail selectedDetails ( thatDetail, maybeName, polygon2d ) =
    let
        selected =
            Those.member thatDetail selectedDetails
    in
    Svg.polygon2d
        [ Svg.Attributes.fill "lightGrey"
        , Svg.Attributes.stroke <|
            if selected then
                "blue"

            else
                "black"
        , Svg.Attributes.strokeWidth "1"
        ]
        polygon2d



---- UPDATE


type Msg
    = NoOp
    | WindowResized Int Int
    | ZoomPlusClicked
    | ZoomMinusClicked
    | MouseDown Position
    | MouseMove Position
    | MouseUp Position
      -- TOOL POINTS
    | SelectToolHovered ToolTag
    | SelectToolUnhovered
    | SelectToolClicked ToolTag
    | EditPointClicked (That Point)
      -- TOOL PARAMETERS
    | NameChanged String
    | AngleChanged String
    | DistanceChanged String
    | RatioChanged String
    | LengthChanged String
    | RadiusChanged String
    | PointAdded (That Point)
    | DropdownAnchorAMsg (Dropdown.Msg (That Point))
    | DropdownAnchorBMsg (Dropdown.Msg (That Point))
    | DropdownLineMsg (Dropdown.Msg (That Line))
    | ListboxPointsMsg (Listbox.Msg (That Point))
    | DropdownLineSegmentMsg (Dropdown.Msg (That LineSegment))
    | DropdownDetailMsg (Dropdown.Msg (That Detail))
    | DropdownCircleAMsg (Dropdown.Msg (That Circle))
    | DropdownCircleBMsg (Dropdown.Msg (That Circle))
    | FirstChanged Bool
      -- TOOL ACTIONS
    | CreateClicked
    | UpdateClicked
    | CancelClicked
      -- PATTERN
    | PointHovered (Maybe (That Point))
      -- STORAGE
    | ClearPatternClicked
    | PatternReceived Value
    | ViewportReceived Value
      -- RIGHT TOOLBAR
    | ToolbarToggleClicked
    | VariablesRulerClicked
    | VariableCreateClicked
    | VariableNameChanged String
    | VariableValueChanged String
    | PointsRulerClicked


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        WindowResized newWidth newHeight ->
            ( { model
                | windowWidth = newWidth
                , windowHeight = newHeight
              }
            , Cmd.none
            )

        ZoomPlusClicked ->
            let
                newModel =
                    { model | zoom = model.zoom / 1.1 }
            in
            ( newModel
            , safeViewport (encodeViewport newModel)
            )

        ZoomMinusClicked ->
            let
                newModel =
                    { model | zoom = model.zoom * 1.1 }
            in
            ( newModel
            , safeViewport (encodeViewport newModel)
            )

        MouseDown position ->
            ( { model
                | maybeDrag =
                    Just
                        { start = position
                        , current = position
                        }
              }
            , Cmd.none
            )

        MouseMove position ->
            case model.maybeDrag of
                Nothing ->
                    ( model, Cmd.none )

                Just drag ->
                    ( { model | maybeDrag = Just { drag | current = position } }
                    , Cmd.none
                    )

        MouseUp position ->
            let
                newCenter =
                    case model.maybeDrag of
                        Nothing ->
                            model.center

                        Just drag ->
                            { x = model.center.x + (drag.start.x - position.x) * model.zoom
                            , y = model.center.y + (drag.start.y - position.y) * model.zoom
                            }

                newModel =
                    { model
                        | maybeDrag = Nothing
                        , center = newCenter
                    }
            in
            ( newModel
            , safeViewport (encodeViewport newModel)
            )

        -- POINTS
        SelectToolHovered toolTag ->
            ( { model | hoveredTool = Just toolTag }
            , Cmd.none
            )

        SelectToolUnhovered ->
            ( { model | hoveredTool = Nothing }
            , Cmd.none
            )

        SelectToolClicked toolTag ->
            let
                tool =
                    case toolTag of
                        LeftOfTag ->
                            CreatePoint "" <|
                                LeftOf
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , distance = ""
                                    }

                        RightOfTag ->
                            CreatePoint "" <|
                                RightOf
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , distance = ""
                                    }

                        AboveTag ->
                            CreatePoint "" <|
                                Above
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , distance = ""
                                    }

                        BelowTag ->
                            CreatePoint "" <|
                                Below
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , distance = ""
                                    }

                        AtAngleTag ->
                            CreatePoint "" <|
                                AtAngle
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , angle = ""
                                    , distance = ""
                                    }

                        BetweenRatioTag ->
                            CreatePoint "" <|
                                BetweenRatio
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , dropdownAnchorB = Dropdown.init
                                    , maybeThatAnchorB = Nothing
                                    , ratio = ""
                                    }

                        BetweenLengthTag ->
                            CreatePoint "" <|
                                BetweenLength
                                    { dropdownAnchorA = Dropdown.init
                                    , maybeThatAnchorA = Nothing
                                    , dropdownAnchorB = Dropdown.init
                                    , maybeThatAnchorB = Nothing
                                    , length = ""
                                    }

                        CircleCircleTag ->
                            CreatePoint "" <|
                                CircleCircle
                                    { dropdownCircleA = Dropdown.init
                                    , maybeThatCircleA = Nothing
                                    , dropdownCircleB = Dropdown.init
                                    , maybeThatCircleB = Nothing
                                    , first = True
                                    }

                        CenteredAtTag ->
                            CenteredAt
                                { name = ""
                                , dropdownAnchorA = Dropdown.init
                                , maybeThatAnchorA = Nothing
                                , radius = ""
                                }

                        ThroughTwoPointsTag ->
                            ThroughTwoPoints
                                { name = ""
                                , dropdownAnchorA = Dropdown.init
                                , maybeThatAnchorA = Nothing
                                , dropdownAnchorB = Dropdown.init
                                , maybeThatAnchorB = Nothing
                                }

                        FromToTag ->
                            FromTo
                                { name = ""
                                , dropdownAnchorA = Dropdown.init
                                , maybeThatAnchorA = Nothing
                                , dropdownAnchorB = Dropdown.init
                                , maybeThatAnchorB = Nothing
                                }

                        MirrorAtTag ->
                            MirrorAt
                                { dropdown = Dropdown.init
                                , thatLine = Nothing
                                , listbox = Listbox.init
                                , thosePoints = Those.none
                                }

                        CutAlongLineSegmentTag ->
                            CutAlongLineSegment
                                { dropdownLineSegment = Dropdown.init
                                , thatLineSegment = Nothing
                                , dropdownDetail = Dropdown.init
                                , thatDetail = Nothing
                                }

                        CounterClockwiseTag ->
                            CounterClockwise []
            in
            ( { model | dialog = Tool tool }
            , case toolTag of
                CutAlongLineSegmentTag ->
                    Dropdown.focus "cut-along-line-segment--line-segment"
                        |> Task.attempt (\_ -> NoOp)

                CounterClockwiseTag ->
                    Cmd.none

                _ ->
                    Browser.Dom.focus "name-input"
                        |> Task.attempt (\_ -> NoOp)
            )

        EditPointClicked thatPoint ->
            case Pattern.getPoint model.pattern thatPoint of
                Nothing ->
                    ( model, Cmd.none )

                Just { name, value } ->
                    case value of
                        Pattern.Origin _ _ ->
                            ( model, Cmd.none )

                        Pattern.LeftOf thatAnchor distance ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            LeftOf
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchor
                                                , distance = distance
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.RightOf thatAnchor distance ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            RightOf
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchor
                                                , distance = distance
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.Above thatAnchor distance ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            Above
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchor
                                                , distance = distance
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.Below thatAnchor distance ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            Below
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchor
                                                , distance = distance
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.AtAngle thatAnchor angle distance ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            AtAngle
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchor
                                                , angle = angle
                                                , distance = distance
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.BetweenRatio thatAnchorA thatAnchorB ratio ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            BetweenRatio
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchorA
                                                , dropdownAnchorB = Dropdown.init
                                                , maybeThatAnchorB = Just thatAnchorB
                                                , ratio = ratio
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.BetweenLength thatAnchorA thatAnchorB length ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            BetweenLength
                                                { dropdownAnchorA = Dropdown.init
                                                , maybeThatAnchorA = Just thatAnchorA
                                                , dropdownAnchorB = Dropdown.init
                                                , maybeThatAnchorB = Just thatAnchorB
                                                , length = length
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.FirstCircleCircle thatCircleA thatCircleB ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            CircleCircle
                                                { dropdownCircleA = Dropdown.init
                                                , maybeThatCircleA = Just thatCircleA
                                                , dropdownCircleB = Dropdown.init
                                                , maybeThatCircleB = Just thatCircleB
                                                , first = True
                                                }
                              }
                            , Cmd.none
                            )

                        Pattern.SecondCircleCircle thatCircleA thatCircleB ->
                            ( { model
                                | dialog =
                                    Tool <|
                                        EditPoint thatPoint <|
                                            CircleCircle
                                                { dropdownCircleA = Dropdown.init
                                                , maybeThatCircleA = Just thatCircleA
                                                , dropdownCircleB = Dropdown.init
                                                , maybeThatCircleB = Just thatCircleB
                                                , first = False
                                                }
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( model, Cmd.none )

        -- TOOL PARAMETERS
        NameChanged newName ->
            let
                updateName toTool data =
                    ( { model | dialog = Tool (toTool { data | name = newName }) }
                    , Cmd.none
                    )
            in
            case model.dialog of
                NoDialog ->
                    ( model, Cmd.none )

                Tool (CreatePoint name toolData) ->
                    ( { model | dialog = Tool (CreatePoint newName toolData) }
                    , Cmd.none
                    )

                Tool (EditPoint _ _) ->
                    ( model, Cmd.none )

                Tool (CenteredAt data) ->
                    updateName CenteredAt data

                Tool (ThroughTwoPoints data) ->
                    updateName ThroughTwoPoints data

                Tool (FromTo data) ->
                    updateName FromTo data

                Tool (MirrorAt _) ->
                    ( model, Cmd.none )

                Tool (CutAlongLineSegment _) ->
                    ( model, Cmd.none )

                Tool (CounterClockwise _) ->
                    ( model, Cmd.none )

                CreateVariable _ ->
                    ( model, Cmd.none )

        AngleChanged newAngle ->
            let
                updateAngle toPointData data =
                    toPointData { data | angle = newAngle }

                updatePointData pointData =
                    case pointData of
                        AtAngle data ->
                            updateAngle AtAngle data

                        _ ->
                            pointData
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    ( { model
                        | dialog = Tool (CreatePoint name (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                Tool (EditPoint thatPoint pointData) ->
                    ( { model
                        | dialog = Tool (EditPoint thatPoint (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        DistanceChanged newDistance ->
            let
                updateDistance toPointData data =
                    toPointData { data | distance = newDistance }

                updatePointData pointData =
                    case pointData of
                        LeftOf data ->
                            updateDistance LeftOf data

                        RightOf data ->
                            updateDistance RightOf data

                        Above data ->
                            updateDistance Above data

                        Below data ->
                            updateDistance Below data

                        AtAngle data ->
                            updateDistance AtAngle data

                        _ ->
                            pointData
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    ( { model
                        | dialog = Tool (CreatePoint name (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                Tool (EditPoint thatPoint pointData) ->
                    ( { model
                        | dialog = Tool (EditPoint thatPoint (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        RatioChanged newRatio ->
            let
                updateRatio toPointData data =
                    toPointData { data | ratio = newRatio }

                updatePointData pointData =
                    case pointData of
                        BetweenRatio data ->
                            updateRatio BetweenRatio data

                        _ ->
                            pointData
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    ( { model
                        | dialog = Tool (CreatePoint name (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                Tool (EditPoint thatPoint pointData) ->
                    ( { model
                        | dialog = Tool (EditPoint thatPoint (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        LengthChanged newLength ->
            let
                updateLength toPointData data =
                    toPointData { data | length = newLength }

                updatePointData pointData =
                    case pointData of
                        BetweenLength data ->
                            updateLength BetweenLength data

                        _ ->
                            pointData
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    ( { model
                        | dialog = Tool (CreatePoint name (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                Tool (EditPoint thatPoint pointData) ->
                    ( { model
                        | dialog = Tool (EditPoint thatPoint (updatePointData pointData))
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        RadiusChanged newRadius ->
            case model.dialog of
                Tool (CenteredAt data) ->
                    ( { model | dialog = Tool (CenteredAt { data | radius = newRadius }) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        PointAdded thatPoint ->
            case model.dialog of
                Tool (CounterClockwise targets) ->
                    ( { model | dialog = Tool (CounterClockwise (thatPoint :: targets)) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        DropdownAnchorAMsg dropdownMsg ->
            let
                updateDropdown toPointData pointData =
                    case pointData of
                        LeftOf data ->
                            updateDropdownAnchorA model (toPointData << LeftOf) dropdownMsg data

                        RightOf data ->
                            updateDropdownAnchorA model (toPointData << RightOf) dropdownMsg data

                        Above data ->
                            updateDropdownAnchorA model (toPointData << Above) dropdownMsg data

                        Below data ->
                            updateDropdownAnchorA model (toPointData << Below) dropdownMsg data

                        AtAngle data ->
                            updateDropdownAnchorA model (toPointData << AtAngle) dropdownMsg data

                        BetweenRatio data ->
                            updateDropdownAnchorA model (toPointData << BetweenRatio) dropdownMsg data

                        BetweenLength data ->
                            updateDropdownAnchorA model (toPointData << BetweenLength) dropdownMsg data

                        _ ->
                            ( model, Cmd.none )
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    updateDropdown (CreatePoint name) pointData

                Tool (EditPoint thatPoint pointData) ->
                    updateDropdown (EditPoint thatPoint) pointData

                Tool (CenteredAt data) ->
                    updateDropdownAnchorA model CenteredAt dropdownMsg data

                Tool (ThroughTwoPoints data) ->
                    updateDropdownAnchorA model ThroughTwoPoints dropdownMsg data

                Tool (FromTo data) ->
                    updateDropdownAnchorA model FromTo dropdownMsg data

                _ ->
                    ( model, Cmd.none )

        DropdownAnchorBMsg dropdownMsg ->
            let
                updateDropdown toPointData pointData =
                    case pointData of
                        BetweenRatio data ->
                            updateDropdownAnchorB model (toPointData << BetweenRatio) dropdownMsg data

                        BetweenLength data ->
                            updateDropdownAnchorB model (toPointData << BetweenLength) dropdownMsg data

                        _ ->
                            ( model, Cmd.none )
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    updateDropdown (CreatePoint name) pointData

                Tool (EditPoint thatPoint pointData) ->
                    updateDropdown (EditPoint thatPoint) pointData

                Tool (ThroughTwoPoints data) ->
                    updateDropdownAnchorB model ThroughTwoPoints dropdownMsg data

                Tool (FromTo data) ->
                    updateDropdownAnchorB model FromTo dropdownMsg data

                _ ->
                    ( model, Cmd.none )

        DropdownLineMsg dropdownMsg ->
            case model.dialog of
                Tool (MirrorAt data) ->
                    let
                        ( newDropdown, dropdownCmd, newLine ) =
                            Dropdown.update dropdownUpdateConfig
                                (Pattern.lines model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                dropdownMsg
                                data.dropdown
                                data.thatLine
                    in
                    ( { model
                        | dialog =
                            Tool <|
                                MirrorAt
                                    { data
                                        | dropdown = newDropdown
                                        , thatLine = newLine
                                    }
                      }
                    , Cmd.map DropdownLineMsg dropdownCmd
                    )

                _ ->
                    ( model, Cmd.none )

        ListboxPointsMsg listboxMsg ->
            case model.dialog of
                Tool (MirrorAt data) ->
                    let
                        ( newListbox, listboxCmd, newPoints ) =
                            Listbox.update listboxUpdateConfig
                                (Pattern.points model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                listboxMsg
                                data.listbox
                                (Those.toList data.thosePoints)
                    in
                    ( { model
                        | dialog =
                            Tool <|
                                MirrorAt
                                    { data
                                        | listbox = newListbox
                                        , thosePoints = Those.fromList newPoints
                                    }
                      }
                    , Cmd.map ListboxPointsMsg listboxCmd
                    )

                _ ->
                    ( model, Cmd.none )

        DropdownLineSegmentMsg dropdownMsg ->
            case model.dialog of
                Tool (CutAlongLineSegment data) ->
                    let
                        ( newDropdown, dropdownCmd, newLineSegment ) =
                            Dropdown.update dropdownUpdateConfig
                                (Pattern.lineSegments model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                dropdownMsg
                                data.dropdownLineSegment
                                data.thatLineSegment
                    in
                    ( { model
                        | dialog =
                            Tool <|
                                CutAlongLineSegment
                                    { data
                                        | dropdownLineSegment = newDropdown
                                        , thatLineSegment = newLineSegment
                                    }
                      }
                    , Cmd.map DropdownLineSegmentMsg dropdownCmd
                    )

                _ ->
                    ( model, Cmd.none )

        DropdownDetailMsg dropdownMsg ->
            case model.dialog of
                Tool (CutAlongLineSegment data) ->
                    let
                        ( newDropdown, dropdownCmd, newDetail ) =
                            Dropdown.update dropdownUpdateConfig
                                (Pattern.details model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                dropdownMsg
                                data.dropdownDetail
                                data.thatDetail
                    in
                    ( { model
                        | dialog =
                            Tool <|
                                CutAlongLineSegment
                                    { data
                                        | dropdownDetail = newDropdown
                                        , thatDetail = newDetail
                                    }
                      }
                    , Cmd.map DropdownDetailMsg dropdownCmd
                    )

                _ ->
                    ( model, Cmd.none )

        DropdownCircleAMsg dropdownMsg ->
            let
                updateCircleA toTool data =
                    let
                        ( newDropdown, dropdownCmd, newMaybeThatCircle ) =
                            Dropdown.update dropdownUpdateConfig
                                (Pattern.circles model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                dropdownMsg
                                data.dropdownCircleA
                                data.maybeThatCircleA
                    in
                    ( { model
                        | dialog =
                            toTool
                                { data
                                    | dropdownCircleA = newDropdown
                                    , maybeThatCircleA = newMaybeThatCircle
                                }
                      }
                    , Cmd.map DropdownCircleAMsg dropdownCmd
                    )
            in
            case model.dialog of
                Tool (CreatePoint name (CircleCircle data)) ->
                    updateCircleA (Tool << CreatePoint name << CircleCircle) data

                Tool (EditPoint thatPoint (CircleCircle data)) ->
                    updateCircleA (Tool << EditPoint thatPoint << CircleCircle) data

                _ ->
                    ( model, Cmd.none )

        DropdownCircleBMsg dropdownMsg ->
            let
                updateCircleB toTool data =
                    let
                        ( newDropdown, dropdownCmd, newMaybeThatCircle ) =
                            Dropdown.update dropdownUpdateConfig
                                (Pattern.circles model.pattern
                                    |> List.map (Tuple.first >> Listbox.option)
                                )
                                dropdownMsg
                                data.dropdownCircleB
                                data.maybeThatCircleB
                    in
                    ( { model
                        | dialog =
                            toTool
                                { data
                                    | dropdownCircleB = newDropdown
                                    , maybeThatCircleB = newMaybeThatCircle
                                }
                      }
                    , Cmd.map DropdownCircleBMsg dropdownCmd
                    )
            in
            case model.dialog of
                Tool (CreatePoint name (CircleCircle data)) ->
                    updateCircleB (Tool << CreatePoint name << CircleCircle) data

                Tool (EditPoint thatPoint (CircleCircle data)) ->
                    updateCircleB (Tool << EditPoint thatPoint << CircleCircle) data

                _ ->
                    ( model, Cmd.none )

        FirstChanged newFirst ->
            let
                updateFirst toTool data =
                    ( { model | dialog = toTool { data | first = newFirst } }
                    , Cmd.none
                    )
            in
            case model.dialog of
                Tool (CreatePoint name (CircleCircle data)) ->
                    updateFirst (Tool << CreatePoint name << CircleCircle) data

                Tool (EditPoint thatPoint (CircleCircle data)) ->
                    updateFirst (Tool << EditPoint thatPoint << CircleCircle) data

                _ ->
                    ( model, Cmd.none )

        --
        CancelClicked ->
            ( { model | dialog = NoDialog }
            , Cmd.none
            )

        CreateClicked ->
            let
                insertSimpleDistance constructor name data =
                    case data.maybeThatAnchorA of
                        Nothing ->
                            ( model, Cmd.none )

                        Just thatAnchor ->
                            constructor model.pattern thatAnchor data.distance
                                |> Maybe.map (insertPoint name model)
                                |> Maybe.withDefault ( model, Cmd.none )
            in
            case model.dialog of
                Tool (CreatePoint name pointData) ->
                    case pointData of
                        LeftOf data ->
                            insertSimpleDistance Pattern.leftOf name data

                        RightOf data ->
                            insertSimpleDistance Pattern.rightOf name data

                        Above data ->
                            insertSimpleDistance Pattern.above name data

                        Below data ->
                            insertSimpleDistance Pattern.below name data

                        AtAngle data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.atAngle model.pattern
                                        thatAnchor
                                        data.angle
                                        data.distance
                                        |> Maybe.map (insertPoint name model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        BetweenRatio data ->
                            Maybe.map2
                                (\thatAnchorA thatAnchorB ->
                                    Pattern.betweenRatio model.pattern
                                        thatAnchorA
                                        thatAnchorB
                                        data.ratio
                                        |> Maybe.map (insertPoint name model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatAnchorA
                                data.maybeThatAnchorB
                                |> Maybe.withDefault ( model, Cmd.none )

                        BetweenLength data ->
                            Maybe.map2
                                (\thatAnchorA thatAnchorB ->
                                    Pattern.betweenLength model.pattern
                                        thatAnchorA
                                        thatAnchorB
                                        data.length
                                        |> Maybe.map (insertPoint name model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatAnchorA
                                data.maybeThatAnchorB
                                |> Maybe.withDefault ( model, Cmd.none )

                        CircleCircle data ->
                            Maybe.map2
                                (\thatCircleA thatCircleB ->
                                    (if data.first then
                                        Pattern.firstCircleCircle model.pattern
                                            thatCircleA
                                            thatCircleB

                                     else
                                        Pattern.secondCircleCircle model.pattern
                                            thatCircleA
                                            thatCircleB
                                    )
                                        |> Maybe.map (insertPoint name model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatCircleA
                                data.maybeThatCircleB
                                |> Maybe.withDefault ( model, Cmd.none )

                Tool (EditPoint _ _) ->
                    ( model, Cmd.none )

                Tool (CenteredAt data) ->
                    case data.maybeThatAnchorA of
                        Nothing ->
                            ( model, Cmd.none )

                        Just thatAnchor ->
                            Pattern.centeredAt model.pattern thatAnchor data.radius
                                |> Maybe.map (insertCircle data.name model)
                                |> Maybe.withDefault ( model, Cmd.none )

                Tool (ThroughTwoPoints data) ->
                    case ( data.maybeThatAnchorA, data.maybeThatAnchorB ) of
                        ( Just thatAnchorA, Just thatAnchorB ) ->
                            let
                                newLine =
                                    Pattern.ThroughTwoPoints
                                        thatAnchorA
                                        thatAnchorB

                                newPattern =
                                    Pattern.insertLine
                                        (if data.name == "" then
                                            Nothing

                                         else
                                            Just data.name
                                        )
                                        newLine
                                        model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , dialog = NoDialog
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Tool (FromTo data) ->
                    case ( data.maybeThatAnchorA, data.maybeThatAnchorB ) of
                        ( Just thatAnchorA, Just thatAnchorB ) ->
                            let
                                newLineSegment =
                                    Pattern.FromTo
                                        thatAnchorA
                                        thatAnchorB

                                newPattern =
                                    Pattern.insertLineSegment
                                        (if data.name == "" then
                                            Nothing

                                         else
                                            Just data.name
                                        )
                                        newLineSegment
                                        model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , dialog = NoDialog
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Tool (MirrorAt { thatLine, thosePoints }) ->
                    case thatLine of
                        Just line ->
                            let
                                newTransformation =
                                    Pattern.MirrorAt line thosePoints

                                newPattern =
                                    Pattern.insertTransformation newTransformation model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , dialog = NoDialog
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Tool (CutAlongLineSegment { thatLineSegment, thatDetail }) ->
                    case ( thatLineSegment, thatDetail ) of
                        ( Just lineSegment, Just detail ) ->
                            let
                                newTransformation =
                                    Pattern.CutAlongLineSegment lineSegment detail

                                newPattern =
                                    Pattern.insertTransformation newTransformation model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , dialog = NoDialog
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Tool (CounterClockwise targets) ->
                    let
                        newDetail =
                            targets
                                |> Pattern.CounterClockwise

                        newPattern =
                            Pattern.insertDetail newDetail model.pattern
                    in
                    ( { model
                        | pattern = newPattern
                        , dialog = NoDialog
                      }
                    , safePattern (Pattern.encode newPattern)
                    )

                CreateVariable { name, value } ->
                    let
                        newPattern =
                            Pattern.insertVariable name value model.pattern
                    in
                    ( { model
                        | pattern = newPattern
                        , dialog = NoDialog
                      }
                    , safePattern (Pattern.encode newPattern)
                    )

                NoDialog ->
                    ( model, Cmd.none )

        UpdateClicked ->
            case model.dialog of
                Tool (EditPoint thatPoint pointData) ->
                    case pointData of
                        LeftOf data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.leftOf model.pattern thatAnchor data.distance
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        RightOf data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.rightOf model.pattern thatAnchor data.distance
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        Above data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.above model.pattern thatAnchor data.distance
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        Below data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.below model.pattern thatAnchor data.distance
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        AtAngle data ->
                            case data.maybeThatAnchorA of
                                Nothing ->
                                    ( model, Cmd.none )

                                Just thatAnchor ->
                                    Pattern.atAngle model.pattern
                                        thatAnchor
                                        data.angle
                                        data.distance
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )

                        BetweenRatio data ->
                            Maybe.map2
                                (\thatAnchorA thatAnchorB ->
                                    Pattern.betweenRatio model.pattern
                                        thatAnchorA
                                        thatAnchorB
                                        data.ratio
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatAnchorA
                                data.maybeThatAnchorB
                                |> Maybe.withDefault ( model, Cmd.none )

                        BetweenLength data ->
                            Maybe.map2
                                (\thatAnchorA thatAnchorB ->
                                    Pattern.betweenLength model.pattern
                                        thatAnchorA
                                        thatAnchorB
                                        data.length
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatAnchorA
                                data.maybeThatAnchorB
                                |> Maybe.withDefault ( model, Cmd.none )

                        CircleCircle data ->
                            Maybe.map2
                                (\thatCircleA thatCircleB ->
                                    (if data.first then
                                        Pattern.firstCircleCircle model.pattern
                                            thatCircleA
                                            thatCircleB

                                     else
                                        Pattern.secondCircleCircle model.pattern
                                            thatCircleA
                                            thatCircleB
                                    )
                                        |> Maybe.map (updatePoint thatPoint model)
                                        |> Maybe.withDefault ( model, Cmd.none )
                                )
                                data.maybeThatCircleA
                                data.maybeThatCircleB
                                |> Maybe.withDefault ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        -- PATTERN
        PointHovered newHoveredPoint ->
            ( { model | hoveredPoint = newHoveredPoint }
            , Cmd.none
            )

        -- STORAGE
        ClearPatternClicked ->
            let
                newPattern =
                    defaultPattern
            in
            ( { model
                | pattern = newPattern
                , dialog = NoDialog
              }
            , safePattern (Pattern.encode newPattern)
            )

        PatternReceived value ->
            case Decode.decodeValue Pattern.decoder value of
                Err error ->
                    let
                        newPattern =
                            defaultPattern
                    in
                    ( { model | pattern = newPattern }
                    , safePattern (Pattern.encode newPattern)
                    )

                Ok newPattern ->
                    ( { model | pattern = newPattern }
                    , Cmd.none
                    )

        ViewportReceived value ->
            case Decode.decodeValue viewportDecoder value of
                Err error ->
                    ( model
                    , safeViewport (encodeViewport model)
                    )

                Ok { zoom, center } ->
                    ( { model
                        | zoom = zoom
                        , center = center
                      }
                    , Cmd.none
                    )

        ToolbarToggleClicked ->
            ( { model | rightToolbarVisible = not model.rightToolbarVisible }
            , Cmd.none
            )

        VariablesRulerClicked ->
            ( { model | variablesVisible = not model.variablesVisible }
            , Cmd.none
            )

        VariableCreateClicked ->
            ( { model | dialog = CreateVariable { name = "", value = "" } }
            , Browser.Dom.focus "name-input"
                |> Task.attempt (\_ -> NoOp)
            )

        VariableNameChanged newName ->
            case model.dialog of
                CreateVariable data ->
                    ( { model | dialog = CreateVariable { data | name = newName } }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        VariableValueChanged newValue ->
            case model.dialog of
                CreateVariable data ->
                    ( { model | dialog = CreateVariable { data | value = newValue } }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        PointsRulerClicked ->
            ( { model | pointsVisible = not model.pointsVisible }
            , Cmd.none
            )


updateDropdownAnchorA model toTool dropdownMsg data =
    let
        ( newDropdown, dropdownCmd, newMaybeThatAnchor ) =
            Dropdown.update dropdownUpdateConfig
                (Pattern.points model.pattern
                    |> List.map (Tuple.first >> Listbox.option)
                )
                dropdownMsg
                data.dropdownAnchorA
                data.maybeThatAnchorA

        newTool =
            toTool
                { data
                    | dropdownAnchorA = newDropdown
                    , maybeThatAnchorA = newMaybeThatAnchor
                }
    in
    ( { model | dialog = Tool newTool }
    , Cmd.map DropdownAnchorAMsg dropdownCmd
    )


updateDropdownAnchorB model toTool dropdownMsg data =
    let
        ( newDropdown, dropdownCmd, newMaybeThatAnchor ) =
            Dropdown.update dropdownUpdateConfig
                (Pattern.points model.pattern
                    |> List.map (Tuple.first >> Listbox.option)
                )
                dropdownMsg
                data.dropdownAnchorB
                data.maybeThatAnchorB

        newTool =
            toTool
                { data
                    | dropdownAnchorB = newDropdown
                    , maybeThatAnchorB = newMaybeThatAnchor
                }
    in
    ( { model | dialog = Tool newTool }
    , Cmd.map DropdownAnchorBMsg dropdownCmd
    )


insertPoint name model newPoint =
    let
        newPattern =
            Pattern.insertPoint
                (if name == "" then
                    Nothing

                 else
                    Just name
                )
                newPoint
                model.pattern
    in
    ( { model
        | pattern = newPattern
        , dialog = NoDialog
      }
    , safePattern (Pattern.encode newPattern)
    )


updatePoint thatPoint model newPoint =
    let
        newPattern =
            Pattern.updatePoint thatPoint newPoint model.pattern
    in
    ( { model
        | pattern = newPattern
        , dialog = NoDialog
      }
    , safePattern (Pattern.encode newPattern)
    )


insertCircle name model newCircle =
    let
        newPattern =
            Pattern.insertCircle
                (if name == "" then
                    Nothing

                 else
                    Just name
                )
                newCircle
                model.pattern
    in
    ( { model
        | pattern = newPattern
        , dialog = NoDialog
      }
    , safePattern (Pattern.encode newPattern)
    )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ patternReceived PatternReceived
        , viewportReceived ViewportReceived
        , Browser.Events.onResize WindowResized
        , case model.maybeDrag of
            Nothing ->
                Sub.none

            Just _ ->
                Sub.batch
                    [ Browser.Events.onMouseMove <|
                        Decode.map MouseMove <|
                            Decode.map2 Position
                                (Decode.field "screenX" Decode.float)
                                (Decode.field "screenY" Decode.float)
                    , Browser.Events.onMouseUp <|
                        Decode.map MouseUp <|
                            Decode.map2 Position
                                (Decode.field "screenX" Decode.float)
                                (Decode.field "screenY" Decode.float)
                    ]
        , case model.dialog of
            NoDialog ->
                Sub.none

            _ ->
                Browser.Events.onKeyDown
                    (Decode.field "key" Decode.string
                        |> Decode.andThen
                            (\key ->
                                case key of
                                    "Escape" ->
                                        Decode.succeed CancelClicked

                                    _ ->
                                        Decode.fail "not handling that key here"
                            )
                    )
        ]


onUrlRequest urlRequest =
    NoOp


onUrlChange url =
    NoOp
