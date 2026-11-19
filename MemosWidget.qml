import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string baseUrl: String(pluginData.baseUrl || "").replace(/\/+$/, "")
    property string token: String(pluginData.token || "")
    property int refreshMinutes: Math.max(1, parseInt(pluginData.refreshMinutes || "10", 10))
    property int maxMemos: Math.min(50, Math.max(1, parseInt(pluginData.maxMemos || "10", 10)))
    property bool showSnippet: pluginData.showSnippet ?? false

    property var memos: []
    property bool loading: false
    property string lastError: ""
    property int epoch: 0

    readonly property bool configured: baseUrl.length > 0 && token.length > 0
    readonly property string latestSnippet: memos.length > 0 ? snippet(memos[0]) : ""

    function snippet(memo) {
        if (!memo)
            return "";
        const text = String(memo.snippet || memo.content || "").replace(/[#*`>]/g, "").replace(/\s+/g, " ").trim();
        return text;
    }

    function timeAgo(iso) {
        if (!iso)
            return "";
        const t = Date.parse(iso);
        if (isNaN(t))
            return "";
        const mins = Math.floor((Date.now() - t) / 60000);
        if (mins < 1)
            return "now";
        if (mins < 60)
            return mins + "m";
        if (mins < 1440)
            return Math.floor(mins / 60) + "h";
        if (mins < 2880)
            return "yesterday";
        if (mins < 43200)
            return Math.floor(mins / 1440) + "d";
        return Qt.formatDate(new Date(t), "d MMM");
    }

    // image attachments need an authed fetch, so curl them into a local cache and point Image at the file
    property string cacheDir: "/tmp/dms-memos-cache"
    property var imgPaths: ({})

    function images(memo) {
        const att = (memo && memo.attachments) ? memo.attachments : [];
        return att.filter(a => String(a.type || "").indexOf("image/") === 0);
    }

    function docs(memo) {
        const att = (memo && memo.attachments) ? memo.attachments : [];
        return att.filter(a => String(a.type || "").indexOf("image/") !== 0);
    }

    function attachPath(a) {
        const uid = String(a.name || "").replace(/^attachments\//, "").replace(/[^A-Za-z0-9]/g, "");
        const fn = String(a.filename || "file").replace(/[^A-Za-z0-9._-]/g, "_");
        return cacheDir + "/" + uid + "_" + fn;
    }

    function cacheImages(list) {
        const wanted = [];
        list.forEach(m => images(m).slice(0, 1).forEach(a => {
            if (!imgPaths[a.name])
                wanted.push(a);
        }));
        wanted.slice(0, 20).forEach(a => {
            const p = attachPath(a);
            const url = baseUrl + "/file/attachments/" + String(a.name).replace(/^attachments\//, "") + "/" + a.filename;
            Proc.runCommand(null, ["curl", "-sS", "--max-time", "25", "-H", "Authorization: Bearer " + token, "-o", p, url], function(out, code) {
                if (code !== 0)
                    return;
                const next = Object.assign({}, imgPaths);
                next[a.name] = "file://" + p;
                imgPaths = next;
            }, 0, 30000);
        });
    }

    function refresh() {
        if (!configured) {
            memos = [];
            lastError = "";
            return;
        }
        const gen = ++epoch;
        loading = true;
        Quickshell.execDetached(["mkdir", "-p", cacheDir]);
        // pinned memos can be older than the recent window, so they need their own request
        getJson(baseUrl + "/api/memos?pageSize=10&filter=" + encodeURIComponent("pinned"), function (pinCode, pins) {
            if (gen !== epoch)
                return;
            getJson(baseUrl + "/api/memos?pageSize=" + maxMemos, function (code, data) {
                if (gen !== epoch)
                    return;
                loading = false;
                if (code !== 0 || !data) {
                    lastError = "Request failed (curl exit " + code + ")";
                    return;
                }
                const keep = arr => (arr || []).filter(m => m.state !== "ARCHIVED");
                const byTime = (a, b) => String(b.createTime).localeCompare(String(a.createTime));
                const pinned = keep(pinCode === 0 && pins ? pins.memos : []).sort(byTime);
                const seen = {};
                pinned.forEach(m => seen[m.name] = true);
                const list = pinned.concat(keep(data.memos).filter(m => !seen[m.name]).sort(byTime));
                memos = list;
                lastError = "";
                root.cacheImages(list);
            });
        });
    }

    // ponytail: token rides in curl argv (same-user /proc visible), swap for `sh -c` + env or --config when it matters
    function getJson(url, cb) {
        Proc.runCommand(null, ["curl", "-sS", "--connect-timeout", "5", "--max-time", "15",
            "-H", "Authorization: Bearer " + token, url], function (out, code) {
            if (code !== 0)
                return cb(code, null);
            try {
                cb(0, JSON.parse(out));
            } catch (e) {
                cb(-1, null);
            }
        }, 0, 20000);
    }

    function copyMemo(memo) {
        const text = snippet(memo);
        if (!text)
            return;
        Quickshell.execDetached(["wl-copy", text]);
        ToastService.showInfo("Memo copied");
        root.closePopout();
    }

    function openMemo(memo) {
        if (!memo || !memo.name)
            return;
        Quickshell.execDetached(["xdg-open", baseUrl + "/memos/" + String(memo.name).replace(/^memos\//, "")]);
        root.closePopout();
    }

    onTokenChanged: refresh()
    onBaseUrlChanged: refresh()

    // pluginData arrives async after mount; poll once shortly after
    Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.refreshMinutes * 60000
        running: root.configured
        repeat: true
        onTriggered: root.refresh()
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: "sticky_note_2"
                size: root.iconSize
                color: root.lastError.length > 0 ? Theme.error : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.showSnippet && root.latestSnippet.length > 0
                text: root.latestSnippet.length > 28 ? root.latestSnippet.substring(0, 28) + "…" : root.latestSnippet
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !(root.showSnippet && root.latestSnippet.length > 0)
                text: root.memos.length.toString()
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: verticalCol.implicitWidth
            implicitHeight: verticalCol.implicitHeight

            Column {
                id: verticalCol
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DIcon {
                    name: "sticky_note_2"
                    size: root.iconSize
                    color: root.lastError.length > 0 ? Theme.error : Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.memos.length.toString()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Memos"
            detailsText: root.configured ? (root.loading ? "Refreshing…" : root.memos.length + " recent") : "Set server and token in settings"
            showCloseButton: true

            Item {
                width: parent.width
                height: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.lastError.length > 0
                    text: root.lastError
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.configured && root.memos.length === 0 && root.lastError.length === 0
                    text: root.loading ? "Loading…" : "No memos"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                ListView {
                    id: list
                    anchors.fill: parent
                    visible: root.memos.length > 0
                    clip: true
                    spacing: Theme.spacingS
                    model: root.memos

                    delegate: StyledRect {
                        required property var modelData
                        width: list.width
                        height: memoCol.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: memoArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Column {
                            id: memoCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingXS

                            Image {
                                id: thumb
                                readonly property var att: root.images(modelData)
                                visible: att.length > 0
                                width: parent.width - Theme.spacingL
                                height: visible ? Math.min(200, width * 0.62) : 0
                                source: visible ? (root.imgPaths[att[0].name] || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: Math.round(width)
                                sourceSize.height: Math.round(height)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 4
                                    visible: thumb.status !== Image.Ready
                                    color: Theme.surfaceContainerHighest

                                    DIcon {
                                        anchors.centerIn: parent
                                        name: "image"
                                        size: Theme.iconSizeLarge
                                        color: Theme.surfaceVariantText
                                    }
                                }
                            }

                            Row {
                                readonly property var att: root.docs(modelData)
                                visible: att.length > 0
                                width: parent.width - Theme.spacingL
                                spacing: Theme.spacingS

                                DIcon {
                                    name: root.docs(modelData).length > 0 && String(root.docs(modelData)[0].type).indexOf("pdf") >= 0 ? "picture_as_pdf" : "description"
                                    size: Theme.fontSizeLarge
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    width: parent.width - Theme.fontSizeLarge - Theme.spacingS
                                    text: root.docs(modelData).map(a => a.filename).join("  ·  ")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width - Theme.spacingL
                                visible: text.length > 0 && root.images(modelData).length === 0
                                text: root.snippet(modelData)
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: root.timeAgo(modelData.createTime) + (modelData.pinned ? "  ·  pinned" : "")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall - 1
                            }
                        }

                        MouseArea {
                            id: memoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyMemo(modelData)
                        }

                        DIcon {
                            id: openIcon
                            name: "open_in_new"
                            size: Theme.fontSizeMedium
                            color: openArea.containsMouse ? Theme.primary : Theme.surfaceVariantText
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter

                            MouseArea {
                                id: openArea
                                anchors.fill: parent
                                anchors.margins: -Theme.spacingXS
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openMemo(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 420
    popoutHeight: 480
}
