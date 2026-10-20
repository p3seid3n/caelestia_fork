import QtQuick

// Material 3 "emphasized decelerate" motion, the same feel as Caelestia's Anim.
NumberAnimation {
    duration: 500
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
}
