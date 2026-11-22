pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    readonly property var colors: MaterialTheme.palette
    property var queues: []
    property var draft: null
    property bool working: false
    property string status: ""
    property bool failed: false
    readonly property var weekdays: [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")]

    function setStatus(message, error) {
        status = message
        failed = error
    }

    function load() {
        working = true
        const previous = draft ? draft.name : ""
        engine.request({query: "glass-queues"}, function(result, error) {
            working = false
            if (error || !result) {
                setStatus(error || qsTr("Could not read the download queues."), true)
                return
            }
            queues = result.queues || []
            const index = queues.findIndex(queue => queue.name === previous)
            choose(index >= 0 ? index : 0)
        })
    }

    function choose(index) {
        draft = queues[index] ? JSON.parse(JSON.stringify(queues[index])) : null
        if (draft) choice.currentIndex = index
    }

    function update(key, value) {
        if (draft) draft = Object.assign({}, draft, {schedule: Object.assign({}, draft.schedule, {[key]: value})})
    }

    function timeText(time) {
        return time ? time.map(value => String(value).padStart(2, "0")).join(":") : ""
    }

    function parseTime(text) {
        if (!text.trim()) return null
        if (!/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(text))
            throw new Error(qsTr("Use 24-hour times in HH:MM or HH:MM:SS format."))
        const parts = text.split(":").map(Number)
        if (parts.length === 2) parts.push(0)
        return parts
    }

    function scheduleAction(save) {
        if (!draft || working) return
        let command
        if (save) {
            try {
                const once = dateField.text.trim()
                const attempts = retryField.text.trim()
                if (once && !/^\d{4}-\d{2}-\d{2}$/.test(once))
                    throw new Error(qsTr("Use YYYY-MM-DD for a one-time date."))
                if (attempts && (!/^\d+$/.test(attempts) || Number(attempts) > 4294967295))
                    throw new Error(qsTr("Enter a valid whole number of retries."))
                const schedule = Object.assign({}, draft.schedule, {
                    start_at: parseTime(startTime.text.trim()),
                    stop_at: parseTime(stopTime.text.trim()),
                    once: once ? once.split("-").map(Number) : null,
                    retries: attempts ? Number(attempts) : null,
                    open_when_done: completionFile.text.trim() || null
                })
                command = {action: "glass-schedule", queue: JSON.stringify({
                    name: draft.name, files_at_once: simultaneous.value, schedule: schedule
                })}
            } catch (error) {
                setStatus(String(error.message || error), true)
                return
            }
        } else {
            command = {action: root.running ? "stop_queue" : "start_queue", queue: draft.name}
        }
        working = true
        engine.request(command, function(result, error) {
            working = false
            if (error || !result) {
                setStatus(error || qsTr("The queue action could not be completed."), true)
                return
            }
            setStatus(save ? qsTr("Schedule saved.") : qsTr("Queue updated."), false)
            engine.refresh()
            load()
        })
    }

    readonly property bool running: Boolean(draft && engine.dashboard &&
        (engine.dashboard.queues || []).some(queue => queue.name === draft.name && queue.running))
    Component.onCompleted: load()

    component ScheduleInput: TextField {
        color: root.colors.text
        placeholderTextColor: root.colors.muted
        selectByMouse: true
        background: GlassSurface { role: "field" }
    }

    Label {
        text: qsTr("Queue schedule")
        color: root.colors.text
        font.weight: Font.DemiBold
    }

    GlassComboBox {
        id: choice
        Layout.fillWidth: true
        model: root.queues
        textRole: "name"
        enabled: !root.working && count > 0
        Accessible.name: qsTr("Queue")
        onActivated: root.choose(index)
    }

    Label {
        Layout.fillWidth: true
        visible: !root.draft && !root.working
        text: qsTr("No queues are available.")
        color: root.colors.muted
    }

    GridLayout {
        Layout.fillWidth: true
        visible: Boolean(root.draft)
        enabled: !root.working
        columns: 2
        columnSpacing: 12
        rowSpacing: 8

        Label { text: qsTr("Simultaneous downloads"); color: root.colors.text }
        SpinBox {
            id: simultaneous
            Layout.fillWidth: true
            from: 1
            to: 128
            value: root.draft ? root.draft.files_at_once : 4
            editable: true
            Accessible.name: qsTr("Simultaneous downloads")
            onValueModified: if (root.draft) root.draft.files_at_once = value
        }

        Label { text: qsTr("Start at"); color: root.colors.text }
        ScheduleInput {
            id: startTime
            Layout.fillWidth: true
            placeholderText: qsTr("HH:MM:SS")
            text: root.draft ? root.timeText(root.draft.schedule.start_at) : ""
            Accessible.name: qsTr("Start time")
            onTextEdited: if (root.draft && (!text || /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(text))) {
                root.draft.schedule.start_at = root.parseTime(text)
            }
        }

        Label { text: qsTr("Stop at"); color: root.colors.text }
        ScheduleInput {
            id: stopTime
            Layout.fillWidth: true
            placeholderText: qsTr("HH:MM:SS")
            text: root.draft ? root.timeText(root.draft.schedule.stop_at) : ""
            Accessible.name: qsTr("Stop time")
            onTextEdited: if (root.draft && (!text || /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(text))) {
                root.draft.schedule.stop_at = root.parseTime(text)
            }
        }

        Label { text: qsTr("One-time date"); color: root.colors.text }
        ScheduleInput {
            id: dateField
            Layout.fillWidth: true
            placeholderText: qsTr("YYYY-MM-DD")
            Accessible.name: qsTr("One-time date")
            text: root.draft && root.draft.schedule.once
                ? root.draft.schedule.once.map((value, index) => String(value).padStart(index ? 2 : 4, "0")).join("-") : ""
            onTextEdited: if (root.draft && (!text || /^\d{4}-\d{2}-\d{2}$/.test(text))) {
                root.draft.schedule.once = text ? text.split("-").map(Number) : null
            }
        }

        Label { text: qsTr("Retries per failed file"); color: root.colors.text }
        ScheduleInput {
            id: retryField
            Layout.fillWidth: true
            placeholderText: qsTr("Blank means unlimited")
            Accessible.name: qsTr("Retries per failed file")
            inputMethodHints: Qt.ImhDigitsOnly
            text: root.draft ? String(root.draft.schedule.retries ?? "") : ""
            onTextEdited: if (root.draft && (!text || /^\d+$/.test(text))) {
                root.draft.schedule.retries = text ? Number(text) : null
            }
        }

        Label { text: qsTr("Open after completion"); color: root.colors.text }
        ScheduleInput {
            id: completionFile
            Layout.fillWidth: true
            placeholderText: qsTr("File path")
            Accessible.name: qsTr("File to open after completion")
            text: root.draft ? root.draft.schedule.open_when_done || "" : ""
            onTextEdited: if (root.draft) root.draft.schedule.open_when_done = text || null
        }

        Label { text: qsTr("Computer action"); color: root.colors.text }
        GlassComboBox {
            id: powerAction
            Layout.fillWidth: true
            readonly property var values: [null, "ShutDown", "Sleep", "Hibernate"]
            model: [qsTr("No action"), qsTr("Shut down"), qsTr("Sleep"), qsTr("Hibernate")]
            currentIndex: root.draft ? values.indexOf(root.draft.schedule.turn_off) : 0
            Accessible.name: qsTr("Computer action after completion")
            onActivated: root.update("turn_off", values[index])
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: Boolean(root.draft)
        enabled: !root.working
        spacing: 6

        Repeater {
            model: root.weekdays
            delegate: CheckBox {
                required property int index
                required property string modelData
                text: modelData
                palette.windowText: root.colors.text
                checked: Boolean(root.draft && root.draft.schedule.days[index])
                onToggled: {
                    if (!root.draft) return
                    const days = root.draft.schedule.days.slice()
                    days[index] = checked
                    root.update("days", days)
                }
            }
        }
    }

    Repeater {
        model: [
            {key: "start_on_startup", text: qsTr("Start this queue when Auralis opens")},
            {key: "wake", text: qsTr("Wake the computer to run this queue")},
            {key: "hang_up", text: qsTr("Disconnect dial-up when done")},
            {key: "exit_when_done", text: qsTr("Exit Auralis when done")},
            {key: "force_close", text: qsTr("Force applications to close. Unsaved work may be lost.")}
        ]
        delegate: CheckBox {
            required property var modelData
            visible: Boolean(root.draft) && (modelData.key !== "force_close" || Boolean(root.draft.schedule.turn_off))
            enabled: !root.working
            text: modelData.text
            palette.windowText: root.colors.text
            checked: Boolean(root.draft && root.draft.schedule[modelData.key])
            onToggled: root.update(modelData.key, checked)
        }
    }

    RowLayout {
        visible: Boolean(root.draft)
        GlassButton {
            text: root.running ? qsTr("Stop queue") : qsTr("Start queue")
            enabled: !root.working
            onClicked: root.scheduleAction(false)
        }
        GlassButton {
            text: qsTr("Save schedule")
            enabled: !root.working
            onClicked: root.scheduleAction(true)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.status.length > 0
        text: root.status
        color: root.failed ? root.colors.destructive : root.colors.muted
        wrapMode: Text.WordWrap
    }
}
