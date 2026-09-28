// The QML module that gives QML a real-time audio sink.
//
// Qt6 exposes no raw-sample output to QML, so the instrument's sound has to come
// from C++. Registering it as a proper QML module means both hosts import it the
// same way: the standalone window, and the Omarchy panel inside Quickshell.
#pragma once

#include <QQmlExtensionPlugin>

class ExoAudioPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlExtensionInterface")

public:
    void registerTypes(const char *uri) override;
};