#include "plugin.h"

#include <qqml.h>

#include "realtimeaudio.h"

void ExoAudioPlugin::registerTypes(const char *uri) {
    qmlRegisterType<RealtimeAudio>(uri, 1, 0, "RealtimeAudio");
}