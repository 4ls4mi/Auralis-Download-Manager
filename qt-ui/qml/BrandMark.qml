import QtQuick

Item {
    implicitWidth: 23
    implicitHeight: 23
    Accessible.ignored: true

    Image {
        anchors.fill: parent
        source: "qrc:/auralis/auralis.png"
        fillMode: Image.PreserveAspectFit
        mipmap: true
    }
}
