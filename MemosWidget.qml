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
    property bool loadingMore: false
    property string lastError: ""
    property string nextToken: ""
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

    function fetchPage(pageToken, append) {
        if (!configured) {
            memos = [];
            nextToken = "";
            lastError = "";
            return;
        }
        const gen = ++epoch;
        loading = !append;
        loadingMore = append;
        // ponytail: token rides in curl argv (same-user /proc visible), swap for `sh -c` + env or --config when it matters
        Proc.runCommand(null, ["curl", "-sS", "--connect-timeout", "5", "--max-time", "15",
            "-H", "Authorization: Bearer " + token,
            baseUrl + "/api/memos?pageSize=" + maxMemos + (pageToken.length > 0 ? "&pageToken=" + pageToken : "")], function(out, code) {
            if (gen !== epoch)
                return;
            loading = false;
            loadingMore = false;
            if (code !== 0) {
                lastError = "Request failed (curl exit " + code + ")";
                return;
            }
            try {
                const data = JSON.parse(out);
                const list = (data.memos || []).filter(m => m.state !== "ARCHIVED");
                memos = append ? memos.concat(list) : list;
                nextToken = String(data.nextPageToken || "");
                lastError = "";
            } catch (e) {
                lastError = "Bad response from " + baseUrl;
            }
        }, 0, 20000);
    }

    function refresh() {
        fetchPage("", false);
    }

    function loadMore() {
        if (!configured || loading || loadingMore || nextToken.length === 0)
            return;
        fetchPage(nextToken, true);
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

                    footer: StyledRect {
                        width: list.width
                        height: visible ? moreRow.implicitHeight + Theme.spacingM * 2 : 0
                        visible: root.nextToken.length > 0 || root.loadingMore
                        radius: Theme.cornerRadius
                        color: moreArea.containsMouse && !root.loadingMore ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            id: moreRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DIcon {
                                name: root.loadingMore ? "progress_activity" : "expand_more"
                                size: Theme.fontSizeMedium
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.loadingMore ? "Loading…" : "Load " + root.maxMemos + " more"
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: moreArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.loadingMore
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.loadMore()
                        }
                    }

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

                            StyledText {
                                width: parent.width - Theme.spacingL
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
