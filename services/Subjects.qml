pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// School subjects for the Calendar tab, found in schulNetz timetables (portal.sbl.ch) by course code:
// "E-2e-FiB" is subject E, "EH-2e-FiB" (Halbklasse) and "CP" (Praktikum) join their base subject when
// the same teacher gives them, "fCR" is a Freifach. Names, colours and hiding can be changed by the
// user and are kept in ~/.local/state/caelestia/calendar-subjects.json.
//
// Colours follow Material You: every subject keeps its own hue (Maths blue, German red, ... like the
// student planner), harmonised towards the wallpaper's primary colour and toned for light or dark mode.
Singleton {
    id: root

    // Course codes of Basel-Landschaft Gymnasien. Subject names stay German: they are the school's names.
    readonly property var known: ({
            D: ["Deutsch", "D", "menu_book"],
            E: ["Englisch", "E", "translate"],
            F: ["Französisch", "F", "translate"],
            I: ["Italienisch", "I", "translate"],
            S: ["Spanisch", "S", "translate"],
            L: ["Latein", "L", "history_edu"],
            GR: ["Griechisch", "Gr", "history_edu"],
            RU: ["Russisch", "Ru", "translate"],
            CN: ["Chinesisch", "Cn", "translate"],
            M: ["Mathematik", "M", "functions"],
            AM: ["Anwendungen der Mathematik", "AM", "calculate"],
            P: ["Physik", "P", "rocket_launch"],
            C: ["Chemie", "C", "science"],
            B: ["Biologie", "B", "eco"],
            G: ["Geschichte", "G", "history_edu"],
            PB: ["Politische Bildung", "PB", "account_balance"],
            GG: ["Geografie", "GG", "public"],
            ET: ["Ethik", "Et", "psychology"],
            RE: ["Religion", "Re", "psychology"],
            PH: ["Philosophie", "Ph", "psychology"],
            PP: ["Philosophie / Psychologie", "PP", "psychology"],
            WR: ["Wirtschaft und Recht", "WR", "payments"],
            W: ["Wirtschaft", "W", "payments"],
            IN: ["Informatik", "In", "computer"],
            BG: ["Bildnerisches Gestalten", "BG", "brush"],
            MU: ["Musik", "Mu", "music_note"],
            SP: ["Sport", "Sp", "sports_soccer"],
            TH: ["Theater", "Th", "theater_comedy"],
            KS: ["Klassenstunde", "KS", "groups"],
            MA: ["Maturaarbeit", "MA", "stars"]
        })

    // Hues (0..1) per subject, after the student planner's Google-like colours.
    readonly property var preferredHue: ({
            M: 0.64,
            AM: 0.68,
            D: 0.0,
            E: 0.56,
            F: 0.8,
            G: 0.07,
            PB: 0.92,
            GG: 0.36,
            B: 0.42,
            C: 0.04,
            P: 0.09,
            IN: 0.48,
            BG: 0.97,
            SP: 0.13,
            ET: 0.75,
            MU: 0.2
        })

    // id -> {id, name, short, icon, codes: [], hue, hidden, teacher}
    property var subjects: ({})

    // Course code -> subject id.
    readonly property var codeIndex: {
        const idx = {};
        for (const id in subjects)
            for (const code of subjects[id].codes)
                idx[code] = id;
        return idx;
    }

    // Subjects sorted by name, for pickers and the settings list.
    readonly property var list: Object.values(subjects).sort((a, b) => a.name.localeCompare(b.name))

    readonly property var hiddenIds: Object.values(subjects).filter(s => s.hidden).map(s => s.id)

    function subjectOf(code: string): var {
        const id = codeIndex[code];
        return id ? subjects[id] : null;
    }

    function idOf(code: string): string {
        return codeIndex[code] ?? "";
    }

    function nameOf(id: string): string {
        return subjects[id]?.name ?? "";
    }

    // ---- colours

    function harmonisedHue(hue: real): real {
        const primary = Colours.palette.m3primary.hslHue;
        if (primary < 0)
            return hue;
        let diff = primary - hue;
        if (diff > 0.5)
            diff -= 1;
        if (diff < -0.5)
            diff += 1;
        // Like Material's harmonize(): move up to 15° towards the source colour.
        const shift = Math.sign(diff) * Math.min(Math.abs(diff) * 0.5, 15 / 360);
        return (hue + shift + 1) % 1;
    }

    // Accent: dots, bars and outlines.
    function colourOf(id: string): color {
        const s = subjects[id];
        if (!s)
            return Colours.palette.m3outline;
        return Qt.hsla(harmonisedHue(s.hue), 0.62, Colours.light ? 0.42 : 0.72, 1);
    }

    // Filled blocks (timetable lessons) and the text on them.
    function containerOf(id: string): color {
        const s = subjects[id];
        if (!s)
            return Colours.palette.m3surfaceContainerHighest;
        return Qt.hsla(harmonisedHue(s.hue), 0.42, Colours.light ? 0.86 : 0.27, 1);
    }

    function onContainerOf(id: string): color {
        const s = subjects[id];
        if (!s)
            return Colours.palette.m3onSurface;
        return Qt.hsla(harmonisedHue(s.hue), 0.55, Colours.light ? 0.18 : 0.9, 1);
    }

    // ---- editing

    function update(id: string, changes: var): void {
        if (!subjects[id])
            return;
        const next = Object.assign({}, subjects);
        next[id] = Object.assign({}, subjects[id], changes);
        subjects = next;
        saveTimer.restart();
    }

    function rename(id: string, name: string): void {
        if (name.trim() !== "")
            update(id, {
                name: name.trim()
            });
    }

    function nextColour(id: string): void {
        const s = subjects[id];
        if (s)
            update(id, {
                hue: (s.hue + 1 / 12) % 1
            });
    }

    function setHidden(id: string, hidden: bool): void {
        update(id, {
            hidden: hidden
        });
    }

    function resetAll(): void {
        subjects = {};
        saveTimer.restart();
    }

    // Adds subjects for course codes that are new, from [{code, teacher}] of a timetable. Existing
    // subjects (and the user's names and colours) are never changed.
    function detect(courses: var): void {
        const result = Object.assign({}, subjects);
        const mapped = {};
        for (const id in result)
            for (const c of result[id].codes)
                mapped[c] = id;

        const all = [];
        const seen = {};
        for (const c of courses) {
            if (!c.code || seen[c.code])
                continue;
            seen[c.code] = true;
            all.push(c);
        }

        let changed = false;
        const ensure = (id, name, short, icon, teacher) => {
            if (!result[id]) {
                const hue = preferredHue[id] ?? freeHueIn(result);
                result[id] = {
                    id: id,
                    name: name,
                    short: short,
                    icon: icon,
                    codes: [],
                    hue: hue,
                    hidden: false,
                    teacher: teacher ?? ""
                };
                changed = true;
            }
        };
        const attach = (id, code) => {
            if (!result[id].codes.includes(code)) {
                result[id] = Object.assign({}, result[id], {
                    codes: result[id].codes.concat([code])
                });
                changed = true;
            }
            mapped[code] = id;
        };

        // 1) known codes first, so variants have something to join
        for (const c of all) {
            if (mapped[c.code])
                continue;
            const k = known[c.code];
            if (k) {
                ensure(c.code, k[0], k[1], k[2], c.teacher);
                attach(c.code, c.code);
            }
        }
        // 2) Freifächer, variants and unknown codes
        for (const c of all) {
            if (mapped[c.code])
                continue;
            const code = c.code;
            if (code.startsWith("f")) {
                ensure(code, "Freifach " + code.slice(1), code.slice(1), "star", c.teacher);
                attach(code, code);
                continue;
            }
            const stripped = code.replace(/[HPL]$/, "");
            if (stripped !== code && mapped[stripped] && all.some(o => o.code === stripped && o.teacher && o.teacher === c.teacher)) {
                attach(mapped[stripped], code);
                continue;
            }
            const sibling = all.find(o => o.code !== code && o.teacher && o.teacher === c.teacher && o.code[0] === code[0] && mapped[o.code]);
            if (sibling) {
                attach(mapped[sibling.code], code);
                continue;
            }
            if (stripped !== code && known[stripped]) {
                const k = known[stripped];
                ensure(stripped, k[0], k[1], k[2], c.teacher);
                attach(stripped, code);
                continue;
            }
            ensure(code, code, code.slice(0, 3), "school", c.teacher);
            attach(code, code);
        }

        if (changed) {
            subjects = result;
            saveTimer.restart();
        }
    }

    function freeHueIn(map: var): real {
        const taken = Object.values(map).map(s => s.hue);
        let hue = 0.11;
        for (let i = 0; i < 64; i++) {
            hue = (0.11 + i * 0.618034) % 1;
            if (taken.every(t => Math.min(Math.abs(t - hue), 1 - Math.abs(t - hue)) > 0.04))
                break;
        }
        return hue;
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                subjects: Object.values(root.subjects)
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/calendar-subjects.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const map = {};
                for (const s of c.subjects ?? []) {
                    if (typeof s.id !== "string" || typeof s.name !== "string" || !Array.isArray(s.codes))
                        continue;
                    map[s.id] = {
                        id: s.id,
                        name: s.name,
                        short: String(s.short ?? s.id),
                        icon: String(s.icon ?? "school"),
                        codes: s.codes.filter(x => typeof x === "string"),
                        hue: typeof s.hue === "number" ? ((s.hue % 1) + 1) % 1 : 0.5,
                        hidden: s.hidden === true,
                        teacher: String(s.teacher ?? "")
                    };
                }
                root.subjects = map;
            } catch (error) {
                console.warn("Subjects: could not parse calendar-subjects.json:", error);
            }
        }
    }
}
