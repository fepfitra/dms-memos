import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "memosWidget"

    StyledText {
        width: parent.width
        text: "Memos"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Reads a Memos server over its REST API. Token: Memos → Settings → Access tokens."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "baseUrl"
        description: "Server URL"
        label: "Server URL"
        placeholder: "https://memos.example.com"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "token"
        description: "Access token, sent as Bearer"
        label: "Access token"
        placeholder: "paste token"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "refreshMinutes"
        description: "Poll interval in minutes"
        label: "Refresh interval"
        placeholder: "10"
        defaultValue: "10"
    }

    StringSetting {
        settingKey: "maxMemos"
        description: "How many recent memos to fetch (1-50)"
        label: "Memos to show"
        placeholder: "10"
        defaultValue: "10"
    }

    ToggleSetting {
        settingKey: "showSnippet"
        label: "Show latest memo text in the bar"
        description: "Off: show the memo count instead"
        defaultValue: false
    }
}
