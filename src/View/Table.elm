module View.Table exposing
    ( column
    , columnActions
    , columnFloat
    , table
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

import Design
import Element exposing (Column, Element)
import Element.Font as Font
import View.Input


table :
    { data : List record
    , columns : List (Column record msg)
    }
    -> Element msg
table =
    Element.table
        [ Element.spacing Design.xSmall ]



---- COLUMNS


column :
    { label : String
    , recordToString : record -> String
    }
    -> Column record msg
column { label, recordToString } =
    { header = Element.el [ Font.size 12 ] (Element.text label)
    , width = Element.fill
    , view =
        \record ->
            Element.el [ Font.size 14 ] <|
                Element.text (recordToString record)
    }


columnFloat :
    { label : String
    , recordToFloat : record -> Maybe Float
    }
    -> Column record msg
columnFloat { label, recordToFloat } =
    { header =
        Element.el [ Font.size 12 ] <|
            Element.el [ Element.alignRight ]
                (Element.text label)
    , width = Element.px 35
    , view =
        \record ->
            case recordToFloat record of
                Nothing ->
                    Element.none

                Just float ->
                    Element.el [ Font.size 14 ] <|
                        Element.el [ Element.alignRight ] <|
                            Element.text <|
                                String.fromInt <|
                                    round float
    }


columnActions :
    { onEditPress : record -> Maybe msg
    , onRemovePress : record -> Maybe msg
    }
    -> Column record msg
columnActions { onEditPress, onRemovePress } =
    { header = Element.none
    , width = Element.shrink
    , view =
        \record ->
            Element.row
                [ Element.paddingEach
                    { left = 5
                    , right = 0
                    , top = 0
                    , bottom = 0
                    }
                , Element.spacing 10
                ]
                [ View.Input.btnIcon
                    { onPress = onEditPress record
                    , icon = "edit"
                    }
                , View.Input.btnIcon
                    { onPress = onRemovePress record
                    , icon = "trash"
                    }
                ]
    }
