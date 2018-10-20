module Circle2d.Extra exposing
    ( Intersection(..)
    , intersectionCircle
    )

import Circle2d exposing (Circle2d)
import Point2d exposing (Point2d)


type Intersection
    = NoIntersection
    | OnePoint Point2d
    | TwoPoints Point2d Point2d


intersectionCircle : Circle2d -> Circle2d -> Intersection
intersectionCircle circle1 circle2 =
    let
        ( x1, y1 ) =
            circle1
                |> Circle2d.centerPoint
                |> Point2d.coordinates

        ( x2, y2 ) =
            circle2
                |> Circle2d.centerPoint
                |> Point2d.coordinates

        r1 =
            Circle2d.radius circle1

        r2 =
            Circle2d.radius circle2

        distance =
            Point2d.distanceFrom
                (Circle2d.centerPoint circle1)
                (Circle2d.centerPoint circle2)

        a =
            2 * (x2 - x1)

        b =
            2 * (y2 - y1)

        c =
            squared r1
                - squared x1
                - squared y1
                - squared r2
                + squared x2
                + squared y2

        cPrim =
            c - a * x1 - b * y1

        underRoot =
            squared r1 * (squared a + squared b) - squared cPrim

        squared f =
            f * f
    in
    if underRoot > 0 then
        let
            root =
                sqrt underRoot

            denominator =
                squared a + squared b
        in
        TwoPoints
            (Point2d.fromCoordinates
                ( x1 + (a * cPrim + b * root) / denominator
                , y1 + (b * cPrim - a * root) / denominator
                )
            )
            (Point2d.fromCoordinates
                ( x1 + (a * cPrim - b * root) / denominator
                , y1 + (b * cPrim + a * root) / denominator
                )
            )

    else if underRoot == 0 then
        let
            denominator =
                squared a + squared b
        in
        OnePoint
            (Point2d.fromCoordinates
                ( x1 + a * cPrim / denominator
                , y1 + b * cPrim / denominator
                )
            )

    else
        NoIntersection