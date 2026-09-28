#include "realtimeaudio.h"

#include <QAudioDevice>
#include <QMediaDevices>
#include <QtMath>

#include <algorithm>
#include <cmath>
#include <QCoreApplication>
#include <QFile>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>

namespace {
// Generous and fixed: readData runs on the audio thread and must not allocate.
constexpr int kMaxBlockFrames = 16384;
constexpr int kSampleRate = 44100;
constexpr int kChannels = 2;
} // namespace

/* ---- SynthDevice --------------------------------------------------------- */

SynthDevice::SynthDevice(QObject *parent)
    : QIODevice(parent) {
    m_scratch.assign(kMaxBlockFrames * kChannels, 0.0f);
    m_tapWanted = !qEnvironmentVariableIsEmpty("EXO_TAP");
}

SynthDevice::~SynthDevice() {
    if (m_tap) std::fclose(m_tap);
}

void SynthDevice::setFormat(const QAudioFormat &format) {
    m_format = format;
    m_synth.setSampleRate(format.sampleRate());
}

// Lifecycle tracing, to a FILE rather than to logging.
//
// The engine's lifetime has to be observable from outside the process: if it is
// torn down while the user expects music, the only symptom is that the sound stops,
// which is indistinguishable from a dozen other causes. Neither channel that looks
// obvious works here - qml6 drops console.log entirely, and the Quickshell message
// handler only forwards NAMED logging categories, so both qInfo and qWarning from
// this module are silently discarded in the shell.
//
// So: append to a file, and only when the sentinel below exists. Nothing is written
// in normal use, and the trace can be turned on for any host without touching its
// environment.
static void lifecycle(const char *fmt, ...) {
    static const bool wanted = QFile::exists(QStringLiteral("/tmp/exo-audio-trace"));
    if (!wanted) return;
    QFile f(QStringLiteral("/tmp/exo-audio-life.log"));
    if (!f.open(QIODevice::Append | QIODevice::Text)) return;
    va_list args;
    va_start(args, fmt);
    const QString line = QString::vasprintf(fmt, args) + QLatin1Char('\n');
    va_end(args);
    f.write(line.toUtf8());
}
void SynthDevice::setTones(const std::vector<exo::Tone> &tones) {
    // Takes effect on the next block: the kernel slews gains, so a bank change
    // swells rather than clicks.
    m_synth.setTones(tones);
}

void SynthDevice::setShape(const exo::Shape &shape) {
    m_synth.setShape(shape);
}

void SynthDevice::setRunning(bool running) {
    m_pendingStop = false;
    m_synth.start();
    Q_UNUSED(running);
}

void SynthDevice::requestStop() {
    m_pendingStop = true;
    m_synth.requestStop();
}

bool SynthDevice::isSilent() const {
    return m_synth.isSilent();
}

qint64 SynthDevice::bytesAvailable() const {
    // Endless: report enough that the sink always believes there is more.
    return kMaxBlockFrames * kChannels * int(sizeof(float)) + QIODevice::bytesAvailable();
}

qint64 SynthDevice::writeData(const char *, qint64) {
    return 0;
}

qint64 SynthDevice::readData(char *data, qint64 maxSize) {
    if (!m_format.isValid() || maxSize <= 0) return 0;

    const int bytesPerFrame = m_format.bytesPerFrame();
    if (bytesPerFrame <= 0) return 0;

    int frames = int(maxSize / bytesPerFrame);
    frames = std::min(frames, kMaxBlockFrames);
    if (frames <= 0) return 0;

    m_synth.render(m_scratch.data(), frames);
    m_frames += frames;

    if (m_tapWanted) {
        if (!m_tapOpened) {
            m_tapOpened = true;
            const QByteArray path = qgetenv("EXO_TAP");
            m_tap = std::fopen(path.constData(), "wb");
        }
        if (m_tap) std::fwrite(m_scratch.data(), sizeof(float), std::size_t(frames) * kChannels, m_tap);
    }

    // Write EXACTLY the format the sink was told to expect. Getting this wrong is
    // not a cosmetic error: the sink consumes by bytesPerFrame, so writing 16-bit
    // samples into a stream declared Int32 makes it drain this device twice as
    // fast as it should. The device then starves and plays ~50% silence - periodic
    // dropouts that sound like a buffering problem and are really a format one.
    // That is exactly what shipped first: "anything not Float is Int16" is only
    // correct for devices whose preferred format happens to be Int16.
    const int count = frames * kChannels;
    switch (m_format.sampleFormat()) {
    case QAudioFormat::Float: {
        std::memcpy(data, m_scratch.data(), std::size_t(count) * sizeof(float));
        break;
    }
    case QAudioFormat::Int16: {
        qint16 *out = reinterpret_cast<qint16 *>(data);
        for (int i = 0; i < count; ++i) {
            const double v = std::max(-32768.0, std::min(32767.0, double(m_scratch[i]) * 32767.0));
            out[i] = qint16(std::lround(v));
        }
        break;
    }
    case QAudioFormat::Int32: {
        qint32 *out = reinterpret_cast<qint32 *>(data);
        for (int i = 0; i < count; ++i) {
            const double v = std::max(-2147483648.0,
                                      std::min(2147483647.0, double(m_scratch[i]) * 2147483647.0));
            out[i] = qint32(std::lround(v));
        }
        break;
    }
    case QAudioFormat::UInt8: {
        quint8 *out = reinterpret_cast<quint8 *>(data);
        for (int i = 0; i < count; ++i) {
            const double v = std::max(0.0, std::min(255.0, double(m_scratch[i]) * 127.0 + 128.0));
            out[i] = quint8(std::lround(v));
        }
        break;
    }
    default:
        // Unknown format: silence is better than mis-declared bytes, because the
        // sink's byte accounting stays consistent with what it was handed.
        std::memset(data, 0, std::size_t(frames) * bytesPerFrame);
        break;
    }
    return qint64(frames) * bytesPerFrame;
}

/* ---- RealtimeAudio ------------------------------------------------------- */

RealtimeAudio::RealtimeAudio(QObject *parent)
    : QObject(parent) {
    lifecycle("RealtimeAudio created (pid %d)", int(QCoreApplication::applicationPid()));
    m_format.setSampleRate(kSampleRate);
    m_format.setChannelCount(kChannels);
    m_format.setSampleFormat(QAudioFormat::Float);

    m_poll.setInterval(400);
    connect(&m_poll, &QTimer::timeout, this, &RealtimeAudio::poll);

    m_releaseTimer.setSingleShot(true);
    connect(&m_releaseTimer, &QTimer::timeout, this, [this]() {
        if (m_sink) m_sink->stop();
        if (m_device) m_device->setRunning(false);
        m_detail = QStringLiteral("released");
        setStatus(QStringLiteral("idle"));
    });
}

RealtimeAudio::~RealtimeAudio() {
    // The marker that matters: if this appears while the user expects music, the
    // engine was torn down rather than stopped.
    lifecycle("RealtimeAudio DESTROYED (running=%d)", int(m_running));
    if (m_sink) m_sink->stop();
    delete m_sink;
    delete m_device;
}

void RealtimeAudio::setStatus(const QString &status) {
    if (m_status == status) return;
    m_status = status;
    emit changed();
}

void RealtimeAudio::setTones(const QVariantList &tones) {
    if (!m_device) {
        m_device = new SynthDevice(this);
        m_device->setFormat(m_format);
    }
    m_tones = tones;
    std::vector<exo::Tone> bank;
    bank.reserve(std::size_t(tones.size()));
    for (const QVariant &entry : tones) {
        const QVariantMap map = entry.toMap();
        exo::Tone tone;
        tone.frequency = map.value(QStringLiteral("frequency")).toDouble();
        tone.amplitude = map.value(QStringLiteral("amplitude")).toDouble();
        if (tone.frequency > 0.0 && tone.amplitude > 0.0) bank.push_back(tone);
    }
    m_device->setTones(bank);
    m_voices = int(m_device->synth().voices().size());
    if (m_voices > m_peakVoices) m_peakVoices = m_voices;
}

void RealtimeAudio::setShape(const QVariantMap &shape) {
    if (!m_device) {
        m_device = new SynthDevice(this);
        m_device->setFormat(m_format);
    }
    m_shapeMap = shape;
    exo::Shape s;
    const auto num = [&shape](const char *key, double fallback) {
        const QVariant v = shape.value(QLatin1String(key));
        return v.isValid() ? v.toDouble() : fallback;
    };
    s.attackMs = num("attackMs", s.attackMs);
    s.releaseMs = num("releaseMs", s.releaseMs);
    s.lowpassHz = num("lowpassHz", s.lowpassHz);
    s.reverbMix = num("reverbMix", s.reverbMix);
    s.reverbPreset = int(num("reverbPreset", s.reverbPreset));
    s.tremoloRateHz = num("tremoloRateHz", s.tremoloRateHz);
    s.tremoloDepth = num("tremoloDepth", s.tremoloDepth);
    s.width = num("width", s.width);
    s.unisonVoices = int(num("unisonVoices", s.unisonVoices));
    s.detuneCents = num("detuneCents", s.detuneCents);
    s.enrichment = num("enrichment", s.enrichment);
    s.partials = int(num("partials", s.partials));
    s.partialTilt = num("partialTilt", s.partialTilt);
    m_device->setShape(s);
}

void RealtimeAudio::start() {
    if (m_running) return;
    if (!m_device) {
        m_device = new SynthDevice(this);
        m_device->setFormat(m_format);
    }

    const QAudioDevice output = QMediaDevices::defaultAudioOutput();
    if (output.isNull()) {
        setStatus(QStringLiteral("error: no audio output"));
        return;
    }
    // Start from what the device prefers and only deviate when asked. A stream at
    // a different rate than the device means a resampler in the path, so the
    // default is the device's own - the properties exist so the alternative can be
    // tested rather than assumed.
    QAudioFormat want = output.preferredFormat();
    if (m_requestedFormatName == QLatin1String("float")) want.setSampleFormat(QAudioFormat::Float);
    else if (m_requestedFormatName == QLatin1String("int16")) want.setSampleFormat(QAudioFormat::Int16);
    else if (m_requestedFormatName == QLatin1String("int32")) want.setSampleFormat(QAudioFormat::Int32);
    if (m_requestedRate > 0) want.setSampleRate(m_requestedRate);
    want.setChannelCount(kChannels);          // the kernel always renders stereo

    if (!output.isFormatSupported(want)) {
        // Keep the stereo request, take the device's own rate and format.
        QAudioFormat fallback = output.preferredFormat();
        fallback.setChannelCount(kChannels);
        if (output.isFormatSupported(fallback)) want = fallback;
    }
    m_format = want;
    m_device->setFormat(m_format);

    delete m_sink;
    m_sink = new QAudioSink(output, m_format, this);
    connect(m_sink, &QAudioSink::stateChanged, this, [this](QAudio::State state) {
        lifecycle("sink state -> %d (error %d, running=%d)",
                  int(state), m_sink ? int(m_sink->error()) : -1, int(m_running));
        if (state == QAudio::StoppedState && m_sink && m_sink->error() != QAudio::NoError) {
            setStatus(QStringLiteral("error: sink stopped"));
        }
    });

    // A QIODevice passed to QAudioSink::start() must be OPEN, or the sink never
    // calls readData and the stream silently produces nothing.
    if (!m_device->isOpen()) m_device->open(QIODevice::ReadOnly);

    m_device->setRunning(true);
    m_sink->start(m_device);
    m_releaseTimer.stop();
    m_peakVoices = 0;
    lifecycle("releasing (fade out), then stop");
    // Wall clock vs audio the device has actually consumed. If the stream ever
    // runs dry the sink goes idle and stops consuming, so this lag grows; a
    // healthy stream settles at the sink's own buffer depth and stays there.
    m_maxLagSeconds = 0.0;
    m_elapsed.start();
    m_running = true;
    lifecycle("start() -> playing");
    m_detail = QStringLiteral("%1 Hz \u00B7 %2 ch").arg(m_format.sampleRate()).arg(m_format.channelCount());
    setStatus(QStringLiteral("playing"));
    m_poll.start();
}

void RealtimeAudio::stop() {
    if (!m_running) return;
    m_running = false;
    if (m_device) m_device->requestStop();
    // Keep the device open for the release, or the tail is simply cut off.
    m_releaseTimer.start(3000);
    setStatus(QStringLiteral("idle"));
    m_poll.stop();
}

void RealtimeAudio::poll() {
    if (!m_device) return;
    const qint64 frames = m_device->framesGenerated();
    const double seconds = double(frames) / double(m_format.sampleRate());
    m_voices = int(m_device->synth().voices().size());
    if (m_voices > m_peakVoices) m_peakVoices = m_voices;
    // How far behind wall clock the device has fallen, at its worst. This is the
    // delivery-side counterpart to the voice high-water mark: it turns "choppy"
    // into a number even when the synthesis itself is producing cleanly.
    if (m_elapsed.isValid()) {
        const double wall = m_elapsed.elapsed() / 1000.0;
        const double played = m_sink ? m_sink->processedUSecs() / 1000000.0 : 0.0;
        const double lag = wall - played;
        if (lag > m_maxLagSeconds) m_maxLagSeconds = lag;
    }

    const char *stateName = "none";
    if (m_sink) {
        switch (m_sink->state()) {
        case QAudio::ActiveState: stateName = "active"; break;
        case QAudio::SuspendedState: stateName = "suspended"; break;
        case QAudio::StoppedState: stateName = "stopped"; break;
        case QAudio::IdleState: stateName = "idle"; break;
        }
    }
    const double bufMs = m_sink ? (m_sink->bufferSize() / double(m_format.bytesPerFrame()) / m_format.sampleRate() * 1000.0) : 0.0;
    const char *fmtName = "?";
    switch (m_format.sampleFormat()) {
    case QAudioFormat::Float: fmtName = "F32"; break;
    case QAudioFormat::Int16: fmtName = "S16"; break;
    case QAudioFormat::Int32: fmtName = "S32"; break;
    case QAudioFormat::UInt8: fmtName = "U8"; break;
    default: break;
    }
    const int preferred = QMediaDevices::defaultAudioOutput().preferredFormat().sampleRate();
    // The device's own rate is only interesting when it differs from what we got.
    const QString rateNote = (preferred == m_format.sampleRate())
        ? QStringLiteral("%1 Hz %9").arg(m_format.sampleRate()).arg(QLatin1String(fmtName))
        : QStringLiteral("%1 Hz %9 (dev %10)").arg(m_format.sampleRate()).arg(QLatin1String(fmtName)).arg(preferred);
    m_detail = QStringLiteral("%11 \u00B7 %2 ch \u00B7 %3 \u00B7 live %4s \u00B7 %5 voices (peak %6) \u00B7 lag %7s \u00B7 buf %8ms")
                   .arg(m_format.sampleRate())
                   .arg(m_format.channelCount())
                   .arg(QLatin1String(stateName))
                   .arg(seconds, 0, 'f', 1)
                   .arg(m_voices)
                   .arg(m_peakVoices)
                   .arg(m_maxLagSeconds, 0, 'f', 2)
                   .arg(bufMs, 0, 'f', 0)
                   .arg(rateNote);
    if (frames != m_lastFrames) {
        m_lastFrames = int(frames);
        emit changed();
    }
}