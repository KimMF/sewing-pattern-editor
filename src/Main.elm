port module Main exposing (main)

import Axis2d exposing (Axis2d)
import Browser exposing (Document)
import Browser.Navigation exposing (Key)
import Circle2d
import Element exposing (Element)
import Element.Background as Background
import Element.Border as Border
import Element.Input as Input
import Geometry.Svg as Svg
import Json.Decode as Decode
import Json.Encode exposing (Value)
import LineSegment2d
import Pattern exposing (Detail, Line, Pattern, Point)
import Point2d exposing (Point2d)
import Polygon2d exposing (Polygon2d)
import Store exposing (Entry)
import Svg exposing (Svg)
import Svg.Attributes as Attributes
import Svg.Events
import That exposing (That)
import Those exposing (Those)
import Url exposing (Url)
import Vector2d


main : Program {} Model Msg
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



---- MODEL


type alias Model =
    { pattern : Pattern
    , tool : Maybe Tool
    , hoveredPoint : Maybe (That Point)
    }


type Tool
    = -- POINTS
      LeftOf String (Maybe (That Point)) String
    | RightOf String (Maybe (That Point)) String
    | Above String (Maybe (That Point)) String
    | Below String (Maybe (That Point)) String
    | AtAngle
      -- LINES
    | ThroughTwoPoints (Maybe (That Point)) (Maybe (That Point))
      -- TRANSFORMATIONS
    | MirrorAt (Maybe (That Line)) (Those Point)
      -- DETAILS
    | CounterClockwise (List (That Point))


selectedPointsFromTool : Tool -> Those Point
selectedPointsFromTool tool =
    case tool of
        LeftOf _ point _ ->
            point
                |> maybeToList
                |> Those.fromList

        RightOf _ point _ ->
            point
                |> maybeToList
                |> Those.fromList

        Above _ point _ ->
            point
                |> maybeToList
                |> Those.fromList

        Below _ point _ ->
            point
                |> maybeToList
                |> Those.fromList

        AtAngle ->
            Those.fromList []

        ThroughTwoPoints pointA pointB ->
            [ pointA, pointB ]
                |> List.filterMap identity
                |> Those.fromList

        MirrorAt _ targets ->
            targets

        CounterClockwise targets ->
            Those.fromList targets


selectedLinesFromTool : Tool -> Those Line
selectedLinesFromTool tool =
    let
        empty =
            Those.fromList []
    in
    case tool of
        LeftOf _ _ _ ->
            empty

        RightOf _ _ _ ->
            empty

        Above _ _ _ ->
            empty

        Below _ _ _ ->
            empty

        AtAngle ->
            empty

        ThroughTwoPoints pointA pointB ->
            empty

        MirrorAt line _ ->
            line
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


init : {} -> Url -> Key -> ( Model, Cmd Msg )
init flags url key =
    ( { pattern =
            Pattern.empty
                |> Pattern.insertPoint (Just "origin") Pattern.Origin
      , tool = Nothing
      , hoveredPoint = Nothing
      }
    , requestPattern ()
    )



---- VIEW


view : Model -> Document Msg
view model =
    { title = "Sewing Pattern Editor"
    , body =
        [ Element.layout
            [ Element.width Element.fill
            , Element.height Element.fill
            ]
            (viewEditor model)
        ]
    }


viewEditor : Model -> Element Msg
viewEditor model =
    let
        selectedPoints =
            model.tool
                |> Maybe.map selectedPointsFromTool
                |> Maybe.withDefault (Those.fromList [])

        selectedLines =
            model.tool
                |> Maybe.map selectedLinesFromTool
                |> Maybe.withDefault (Those.fromList [])
    in
    Element.row
        [ Element.height Element.fill
        , Element.width Element.fill
        ]
        [ Element.el
            [ Element.width Element.fill
            , Element.height Element.fill
            ]
            (Element.html <|
                Svg.svg
                    [ Attributes.viewBox "-320 -320 640 640" ]
                    (drawPattern
                        model.hoveredPoint
                        selectedPoints
                        selectedLines
                        model.pattern
                    )
            )
        , Element.column
            [ Element.height Element.fill
            , Border.color (Element.rgb 0.3 0.3 0.3)
            , Border.width 1
            ]
            [ Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ button "left of" LeftOfClicked
                , button "right of" RightOfClicked
                , button "above" AboveClicked
                , button "below" BelowClicked
                , button "at angle" AtAngleClicked
                ]
            , Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ button "through two points" ThroughTwoPointsClicked
                ]
            , Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ button "mirror at" MirrorAtClicked
                ]
            , Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ button "counter clockwise" CounterClockwiseClicked
                ]
            , horizontalLine
            , Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ button "clear pattern" ClearPatternClicked
                ]
            , horizontalLine
            , Element.el
                [ Element.height Element.fill ]
                (model.tool
                    |> Maybe.map
                        (viewTool
                            model.pattern
                            (Pattern.points model.pattern)
                            (Pattern.lines model.pattern)
                        )
                    |> Maybe.withDefault Element.none
                )
            , horizontalLine
            , Element.row
                [ Element.padding 10
                , Element.spacing 5
                ]
                [ Element.paragraph []
                    [ Element.text <|
                        case model.hoveredPoint of
                            Nothing ->
                                "Hover over points to get more information."

                            Just thatPoint ->
                                thatPoint
                                    |> Pattern.getPoint model.pattern
                                    |> Debug.toString
                    ]
                ]
            ]
        ]


viewTool :
    Pattern
    -> List ( That Point, Entry Point )
    -> List ( That Line, Entry Line )
    -> Tool
    -> Element Msg
viewTool pattern points lines tool =
    let
        pointOption ( thatPoint, { name } ) =
            Input.option thatPoint (Element.text (Maybe.withDefault "<unnamed>" name))

        lineOption ( thatLine, { name } ) =
            Input.option thatLine (Element.text (Maybe.withDefault "<unnamed>" name))

        simpleDistanceTool name anchor distance =
            Element.column
                [ Element.padding 10
                , Element.spacing 10
                ]
                [ Input.text []
                    { onChange = Just NameChanged
                    , text = name
                    , placeholder = Nothing
                    , label = Input.labelAbove [] (Element.text "name")
                    }
                , anchorSelection anchor "anchor" AnchorChanged
                , Input.text []
                    { onChange = Just DistanceChanged
                    , text = distance
                    , placeholder = Nothing
                    , label = Input.labelAbove [] (Element.text "distance")
                    }
                , button "create" CreateClicked
                ]

        anchorSelection anchor label msg =
            Input.radio []
                { onChange = Just msg
                , selected = anchor
                , label = Input.labelAbove [] (Element.text label)
                , options = List.map pointOption points
                }
    in
    case tool of
        LeftOf name anchor distance ->
            simpleDistanceTool name anchor distance

        RightOf name anchor distance ->
            simpleDistanceTool name anchor distance

        Above name anchor distance ->
            simpleDistanceTool name anchor distance

        Below name anchor distance ->
            simpleDistanceTool name anchor distance

        AtAngle ->
            Debug.todo ""

        ThroughTwoPoints anchorA anchorB ->
            Element.column
                [ Element.padding 10
                , Element.spacing 10
                ]
                [ anchorSelection anchorA "anchor a" AnchorAChanged
                , anchorSelection anchorB "anchor b" AnchorBChanged
                , button "create" CreateClicked
                ]

        MirrorAt line targets ->
            let
                pointCheckbox ( thatPoint, { name } ) =
                    Input.checkbox []
                        { onChange = Just (PointChecked thatPoint)
                        , icon = Nothing
                        , checked = Those.member thatPoint targets
                        , label =
                            Input.labelRight [] <|
                                Element.text (Maybe.withDefault "<unnamed>" name)
                        }
            in
            Element.column
                [ Element.padding 10
                , Element.spacing 10
                ]
                [ Input.radio []
                    { onChange = Just LineChanged
                    , selected = line
                    , label = Input.labelAbove [] (Element.text "line")
                    , options = List.map lineOption lines
                    }
                , Element.text "targets"
                , Element.column [] <|
                    List.map pointCheckbox points
                , button "create" CreateClicked
                ]

        CounterClockwise targets ->
            let
                pointButton ( thatPoint, { name } ) =
                    button (Maybe.withDefault "<unnamed>" name) (PointAdded thatPoint)
            in
            Element.column
                [ Element.padding 10
                , Element.spacing 10
                ]
                [ Element.text
                    (targets
                        |> List.filterMap (Pattern.getPoint pattern)
                        |> List.map (.name >> Maybe.withDefault "<unnamed>")
                        |> String.join ", "
                    )
                , Element.column [] <|
                    List.map pointButton points
                , button "create" CreateClicked
                ]


button : String -> msg -> Element msg
button label msg =
    Input.button
        [ Background.color (Element.rgb 0.9 0.9 0.9)
        , Element.padding 10
        ]
        { onPress = Just msg
        , label = Element.text label
        }


horizontalLine : Element msg
horizontalLine =
    Element.el
        [ Element.height (Element.px 1)
        , Element.width Element.fill
        , Background.color (Element.rgb 0.3 0.3 0.3)
        ]
        Element.none



---- SVG


drawPattern : Maybe (That Point) -> Those Point -> Those Line -> Pattern -> List (Svg Msg)
drawPattern hoveredPoint selectedPoints selectedLines pattern =
    let
        ( geometry, problems ) =
            Pattern.geometry pattern
    in
    List.concat
        [ List.map drawDetail geometry.details
        , List.map (drawLine selectedLines) geometry.lines
        , List.map (drawPoint pattern hoveredPoint selectedPoints) geometry.points
        ]


drawPoint : Pattern -> Maybe (That Point) -> Those Point -> ( That Point, Maybe String, Point2d ) -> Svg Msg
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
                        Just (Pattern.LeftOf thatAnchorPoint distance) ->
                            drawAnchorLine thatAnchorPoint distance <|
                                \float -> Vector2d.fromComponents ( -1 * float, 0 )

                        Just (Pattern.RightOf thatAnchorPoint distance) ->
                            drawAnchorLine thatAnchorPoint distance <|
                                \float -> Vector2d.fromComponents ( float, 0 )

                        Just (Pattern.Above thatAnchorPoint distance) ->
                            drawAnchorLine thatAnchorPoint distance <|
                                \float -> Vector2d.fromComponents ( 0, -1 * float )

                        Just (Pattern.Below thatAnchorPoint distance) ->
                            drawAnchorLine thatAnchorPoint distance <|
                                \float -> Vector2d.fromComponents ( 0, float )

                        _ ->
                            Svg.text ""
                    , case
                        hoveredPoint
                            |> Maybe.map (Pattern.getPointGeometries pattern)
                      of
                        Nothing ->
                            Svg.text ""

                        Just point2ds ->
                            point2ds
                                |> List.map
                                    (Svg.circle2d [ Attributes.fill "blue" ]
                                        << Circle2d.withRadius 2
                                    )
                                |> Svg.g []
                    ]
            else
                Svg.text ""

        drawAnchorLine thatAnchorPoint distance toDirection =
            Maybe.map2 (drawDashedLine toDirection)
                (Pattern.getPointGeometry pattern thatAnchorPoint)
                (Pattern.computeLength pattern distance)
                |> Maybe.withDefault (Svg.text "")

        drawDashedLine toDirection p2d float =
            let
                otherPoint =
                    Point2d.translateBy (toDirection float) p2d
            in
            Svg.g
                []
                [ Svg.lineSegment2d
                    [ Attributes.stroke "blue"
                    , Attributes.strokeDasharray "4"
                    ]
                    (LineSegment2d.fromEndpoints
                        ( p2d, otherPoint )
                    )
                ]
    in
    Svg.g []
        [ Svg.circle2d
            [ Attributes.fill "black" ]
            (Circle2d.withRadius 2 point2d)
        , if selected then
            Svg.circle2d
                [ Attributes.stroke "blue"
                , Attributes.fill "none"
                ]
                (Circle2d.withRadius 5 point2d)
          else
            Svg.g [] []
        , helper
        , maybeName
            |> Maybe.map
                (\name ->
                    Svg.text_
                        [ Attributes.x (String.fromFloat x)
                        , Attributes.y (String.fromFloat y)
                        , Attributes.dy "-5"
                        , Attributes.style "font: 10px sans-serif;"
                        , Attributes.textAnchor "middle"
                        ]
                        [ Svg.text name ]
                )
            |> Maybe.withDefault (Svg.text "")
        , Svg.circle2d
            [ Attributes.fill "transparent"
            , Svg.Events.onMouseOver (PointHovered (Just thatPoint))
            , Svg.Events.onMouseOut (PointHovered Nothing)
            ]
            (Circle2d.withRadius 5 point2d)
        ]


drawLine : Those Line -> ( That Line, Maybe String, Axis2d ) -> Svg msg
drawLine selectedLines ( thatLine, maybeName, axis2d ) =
    let
        selected =
            Those.member thatLine selectedLines
    in
    Svg.lineSegment2d
        [ Attributes.stroke <|
            if selected then
                "blue"
            else
                "black"
        ]
        (LineSegment2d.fromEndpoints
            ( Point2d.along axis2d -1000
            , Point2d.along axis2d 1000
            )
        )


drawDetail : ( That Detail, Maybe String, Polygon2d ) -> Svg msg
drawDetail ( thatDetail, maybeName, polygon2d ) =
    Svg.polygon2d
        [ Attributes.fill "lightGrey" ]
        polygon2d



---- UPDATE


type Msg
    = NoOp
      -- POINTS
    | LeftOfClicked
    | RightOfClicked
    | AboveClicked
    | BelowClicked
    | AtAngleClicked
      -- LINES
    | ThroughTwoPointsClicked
      -- TRANSFORMATIONS
    | MirrorAtClicked
      -- DETAILS
    | CounterClockwiseClicked
      --
    | NameChanged String
    | AnchorChanged (That Point)
    | AnchorAChanged (That Point)
    | AnchorBChanged (That Point)
    | DistanceChanged String
    | LineChanged (That Line)
    | PointChecked (That Point) Bool
    | PointAdded (That Point)
      --
    | CreateClicked
      -- PATTERN
    | PointHovered (Maybe (That Point))
      -- STORAGE
    | ClearPatternClicked
    | PatternReceived Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        -- POINTS
        LeftOfClicked ->
            ( { model | tool = Just (LeftOf "" Nothing "") }
            , Cmd.none
            )

        RightOfClicked ->
            ( { model | tool = Just (RightOf "" Nothing "") }
            , Cmd.none
            )

        AboveClicked ->
            ( { model | tool = Just (Above "" Nothing "") }
            , Cmd.none
            )

        BelowClicked ->
            ( { model | tool = Just (Below "" Nothing "") }
            , Cmd.none
            )

        AtAngleClicked ->
            ( { model | tool = Just AtAngle }
            , Cmd.none
            )

        -- LINES
        ThroughTwoPointsClicked ->
            ( { model | tool = Just (ThroughTwoPoints Nothing Nothing) }
            , Cmd.none
            )

        -- TRANSFORMATIONS
        MirrorAtClicked ->
            ( { model | tool = Just (MirrorAt Nothing Those.none) }
            , Cmd.none
            )

        -- DETAILS
        CounterClockwiseClicked ->
            ( { model | tool = Just (CounterClockwise []) }
            , Cmd.none
            )

        -- TOOL PARAMETERS
        NameChanged newName ->
            case model.tool of
                Just (LeftOf _ anchor distance) ->
                    ( { model | tool = Just (LeftOf newName anchor distance) }
                    , Cmd.none
                    )

                Just (RightOf _ anchor distance) ->
                    ( { model | tool = Just (RightOf newName anchor distance) }
                    , Cmd.none
                    )

                Just (Above _ anchor distance) ->
                    ( { model | tool = Just (Above newName anchor distance) }
                    , Cmd.none
                    )

                Just (Below _ anchor distance) ->
                    ( { model | tool = Just (Below newName anchor distance) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AnchorChanged newAnchor ->
            case model.tool of
                Just (LeftOf name anchor distance) ->
                    ( { model | tool = Just (LeftOf name (Just newAnchor) distance) }
                    , Cmd.none
                    )

                Just (RightOf name anchor distance) ->
                    ( { model | tool = Just (RightOf name (Just newAnchor) distance) }
                    , Cmd.none
                    )

                Just (Above name anchor distance) ->
                    ( { model | tool = Just (Above name (Just newAnchor) distance) }
                    , Cmd.none
                    )

                Just (Below name anchor distance) ->
                    ( { model | tool = Just (Below name (Just newAnchor) distance) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AnchorAChanged newAnchorA ->
            case model.tool of
                Just (ThroughTwoPoints anchorA anchorB) ->
                    ( { model | tool = Just (ThroughTwoPoints (Just newAnchorA) anchorB) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AnchorBChanged newAnchorB ->
            case model.tool of
                Just (ThroughTwoPoints anchorA anchorB) ->
                    ( { model | tool = Just (ThroughTwoPoints anchorA (Just newAnchorB)) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        DistanceChanged newDistance ->
            case model.tool of
                Just (LeftOf name anchor distance) ->
                    ( { model | tool = Just (LeftOf name anchor newDistance) }
                    , Cmd.none
                    )

                Just (RightOf name anchor distance) ->
                    ( { model | tool = Just (RightOf name anchor newDistance) }
                    , Cmd.none
                    )

                Just (Above name anchor distance) ->
                    ( { model | tool = Just (Above name anchor newDistance) }
                    , Cmd.none
                    )

                Just (Below name anchor distance) ->
                    ( { model | tool = Just (Below name anchor newDistance) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        LineChanged newLine ->
            case model.tool of
                Just (MirrorAt line targets) ->
                    ( { model | tool = Just (MirrorAt (Just newLine) targets) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        PointChecked thatPoint checked ->
            case model.tool of
                Just (MirrorAt line targets) ->
                    ( { model
                        | tool =
                            Just <|
                                MirrorAt line <|
                                    if checked then
                                        Those.insert thatPoint targets
                                    else
                                        Those.remove thatPoint targets
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        PointAdded thatPoint ->
            case model.tool of
                Just (CounterClockwise targets) ->
                    ( { model | tool = Just (CounterClockwise (thatPoint :: targets)) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        --
        CreateClicked ->
            let
                insertSimpleDistance constructor name anchor distance =
                    case ( anchor, String.toFloat distance ) of
                        ( Just thatPoint, Just by ) ->
                            let
                                newPoint =
                                    constructor thatPoint
                                        (Pattern.Length (Pattern.exprFromFloat by))

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
                                , tool = Nothing
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                lastState =
                    Pattern.lastState model.pattern
            in
            case model.tool of
                Just (LeftOf name anchor distance) ->
                    insertSimpleDistance Pattern.LeftOf name anchor distance

                Just (RightOf name anchor distance) ->
                    insertSimpleDistance Pattern.RightOf name anchor distance

                Just (Above name anchor distance) ->
                    insertSimpleDistance Pattern.Above name anchor distance

                Just (Below name anchor distance) ->
                    insertSimpleDistance Pattern.Below name anchor distance

                Just (ThroughTwoPoints anchorA anchorB) ->
                    case ( anchorA, anchorB ) of
                        ( Just thatPointA, Just thatPointB ) ->
                            let
                                newPoint =
                                    Pattern.ThroughTwoPoints
                                        thatPointA
                                        thatPointB

                                newPattern =
                                    Pattern.insertLine newPoint model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , tool = Nothing
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Just (MirrorAt line targets) ->
                    case line of
                        Just thatLine ->
                            let
                                newTransformation =
                                    Pattern.MirrorAt thatLine targets

                                newPattern =
                                    Pattern.insertTransformation newTransformation model.pattern
                            in
                            ( { model
                                | pattern = newPattern
                                , tool = Nothing
                              }
                            , safePattern (Pattern.encode newPattern)
                            )

                        _ ->
                            ( model, Cmd.none )

                Just (CounterClockwise targets) ->
                    let
                        newDetail =
                            targets
                                |> Pattern.CounterClockwise

                        newPattern =
                            Pattern.insertDetail newDetail model.pattern
                    in
                    ( { model
                        | pattern = newPattern
                        , tool = Nothing
                      }
                    , safePattern (Pattern.encode newPattern)
                    )

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
                    Pattern.empty
                        |> Pattern.insertPoint (Just "origin") Pattern.Origin
            in
            ( { model
                | pattern = newPattern
                , tool = Nothing
              }
            , safePattern (Pattern.encode newPattern)
            )

        PatternReceived value ->
            case Decode.decodeValue Pattern.decoder value of
                Err error ->
                    Debug.todo (Decode.errorToString error)

                Ok newPattern ->
                    ( { model | pattern = newPattern }
                    , Cmd.none
                    )


subscriptions : Model -> Sub Msg
subscriptions model =
    patternReceived PatternReceived


onUrlRequest urlRequest =
    NoOp


onUrlChange url =
    NoOp
