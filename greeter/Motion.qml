import QtQuick

// Copy of Caelestia's motion tokens (Anim.qml + default config), so the greeter moves
// exactly like the shell. type: "fastSpatial" | "defaultSpatial" | "fastEffects" | "defaultEffects"
// | "emphasized" (Anim.EmphasizedLarge) | "standard" (Anim.Standard) | "standardLarge" (Anim.StandardLarge)
NumberAnimation {
    property string type: "defaultSpatial"

    readonly property var curves: ({
            fastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1],
            defaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1],
            fastEffects: [0.31, 0.94, 0.34, 1, 1, 1],
            defaultEffects: [0.34, 0.8, 0.34, 1, 1, 1],
            emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
            standard: [0.2, 0, 0, 1, 1, 1],
            standardLarge: [0.2, 0, 0, 1, 1, 1]
        })
    readonly property var durations: ({
            fastSpatial: 350,
            defaultSpatial: 500,
            fastEffects: 150,
            defaultEffects: 200,
            emphasized: 600,
            standard: 400,
            standardLarge: 600
        })

    duration: durations[type] ?? 400
    easing.type: Easing.BezierSpline
    easing.bezierCurve: curves[type] ?? [0.2, 0, 0, 1, 1, 1]
}
