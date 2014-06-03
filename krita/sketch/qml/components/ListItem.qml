/* This file is part of the KDE project
 * Copyright (C) 2012 Arjen Hiemstra <ahiemstra@heimr.nl>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

import QtQuick 1.1

Item {
    id: base;

    property alias title: title.text;
    property alias description: description.text;
    property alias gradient: background.gradient;
    property alias image: image;
    property alias imageShadow: imageShadow.visible;

    signal clicked();

    width: Constants.GridWidth > 1 ? Constants.GridWidth * 4 : 1;
    height: Constants.GridHeight > 1 ? Constants.GridHeight * 1.75 : 1;

    Rectangle {
        id: background;

        anchors {
            fill: parent;
            leftMargin: Constants.GridWidth * 0.25;
            rightMargin: Constants.GridWidth * 0.25;
            topMargin: Constants.GridHeight * 0.25;
            bottomMargin: Constants.GridHeight * 0.25;
        }

        gradient: Gradient {
            GradientStop { position: 0; color: Settings.theme.color("components/listItem/background/start"); }
            GradientStop { position: 0.4; color: Settings.theme.color("components/listItem/background/stop"); }
        }

        Shadow { anchors.top: parent.bottom; width: parent.width; height: Constants.GridHeight / 8; }

        Image {
            id: image

            anchors {
                left: parent.left;
                leftMargin: Constants.GridWidth * 0.125;
                top: parent.top;
                topMargin: Constants.GridHeight * 0.25;
                bottom: parent.bottom;
                bottomMargin: Constants.GridHeight * 0.25;
            }

            width: Constants.GridWidth * 0.5;

            asynchronous: true;
            fillMode: Image.PreserveAspectFit;
            clip: true;
            smooth: true;

            sourceSize.width: width > height ? height : width;
            sourceSize.height: width > height ? height : width;
        }

        Shadow {
            id: imageShadow;

            visible: false;

            anchors.horizontalCenter: image.horizontalCenter;
            anchors.top: image.bottom;

            width: image.width;
            height: Constants.GridHeight / 8;
        }

        Label {
            id: title;

            anchors {
                top: description.text != "" ? parent.top : undefined;
                verticalCenter: description.text != "" ? undefined : parent.verticalCenter;
                topMargin: Constants.GridHeight * 0.25;
                left: image.source != "" ? image.right : parent.left;
                leftMargin: Constants.GridWidth * 0.25;
                right: parent.right;
                rightMargin: Constants.GridWidth * 0.25;
            }

            verticalAlignment: Text.AlignTop;
            color: Settings.theme.color("components/listItem/title");
        }

        Label {
            id: description;

            anchors {
                bottom: parent.bottom;
                bottomMargin:Constants.GridHeight * 0.25;
                left: image.source != "" ? image.right : parent.left;
                leftMargin: Constants.GridWidth * 0.25;
                right: parent.right;
                rightMargin: Constants.GridWidth * 0.25;
            }

            color: Settings.theme.color("components/listItem/description");
            font: Settings.theme.font("small");
            verticalAlignment: Text.AlignBottom;
        }
    }

    MouseArea {
        anchors.fill: parent;
        onClicked: {
            base.clicked();
        }
    }
}
