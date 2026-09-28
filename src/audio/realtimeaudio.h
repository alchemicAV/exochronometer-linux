// RealtimeAudio - the QML type the app and the panel actually use for sound.
//
// It owns a QAudioSink fed by a QIODevice that synthesises on demand, so playback
// is continuous: no buffer to render, no loop to restart, no latency before the
// first sample, and a knob moved mid-stream is heard immediately.
//
// Qt6 exposes no raw-sample sink to QML at all - AudioEngine, AudioSink,
// AudioBufferOutput and AudioSource all live behind the C++ API - which is why
// this file exists rather than a QML-only implementation.

#pragma once

#include <QAudioFormat>
#include <QAudioSink>
#include <QIODevice>
#include <QElapsedTimer>
#include <QMutex>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <vector>

#include "exosynth.h"

/// Pull source: the sink calls readData() as it needs audio and this fills it
/// from the kernel. `bytesAvailable` reports a generous amount so the sink keeps
/// pulling from what is an endless signal.
class SynthDevice : public QIODevice {
    Q_OBJECT

public:
    explicit SynthDevice(QObject *parent = nullptr);
    ~SynthDevice() override;

    void setFormat(const QAudioFormat &format);
    void setTones(const std::vector<exo::Tone> &tones);
    void setShape(const exo::Shape &shape);
    void setRunning(bool running);
    void requestStop();
    bool isSilent() const;

    exo::Synth &synth() { return m_synth; }
    const exo::Synth &synth() const { return m_synth; }

    qint64 framesGenerated() const { return m_frames; }

    qint64 readData(char *data, qint64 maxSize) override;
    qint64 writeData(const char *data, qint64 maxSize) override;
    qint64 bytesAvailable() const override;
    bool isSequential() const override { return true; }

private:
    exo::Synth m_synth;
    QAudioFormat m_format;
    std::vector<float> m_scratch;
    QMutex m_mutex;
    qint64 m_frames = 0;
    // Debug tap: when EXO_TAP is set, every block readData produces is appended
    // there as raw float32. Comparing that file against a recording of the device
    // says whether a dropout is in the production or on the way out - the one
    // question an internal counter cannot answer.
    bool m_tapWanted = false;
    bool m_tapOpened = false;
    FILE *m_tap = nullptr;
    bool m_pendingStop = false;
};

/// The QML element: `RealtimeAudio { }`.
class RealtimeAudio : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool running READ running NOTIFY changed)
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(int voices READ voices NOTIFY changed)
    Q_PROPERTY(int sampleRate READ sampleRate NOTIFY changed)
    Q_PROPERTY(int channels READ channels NOTIFY changed)
    // Output format. Defaults follow whatever the DEVICE prefers, which keeps a
    // resampler out of the path; these exist so the choice can be tested and
    // overridden rather than assumed.
    Q_PROPERTY(int requestedRate READ requestedRate WRITE setRequestedRate)
    Q_PROPERTY(QString requestedFormatName READ requestedFormatName WRITE setRequestedFormatName)
    Q_PROPERTY(QVariantList tones READ tones WRITE setTones)
    Q_PROPERTY(QVariantMap shape READ shape WRITE setShape)

public:
    explicit RealtimeAudio(QObject *parent = nullptr);
    ~RealtimeAudio() override;

    bool running() const { return m_running; }
    bool playing() const { return m_running; }
    QString status() const { return m_status; }
    QString detail() const { return m_detail; }
    int voices() const { return m_voices; }
    int requestedRate() const { return m_requestedRate; }
    void setRequestedRate(int rate) { m_requestedRate = rate; }
    QString requestedFormatName() const { return m_requestedFormatName; }
    void setRequestedFormatName(const QString &name) { m_requestedFormatName = name; }
    int sampleRate() const { return m_format.sampleRate(); }
    int channels() const { return m_format.channelCount(); }

    QVariantList tones() const { return m_tones; }
    QVariantMap shape() const { return m_shapeMap; }
    void setTones(const QVariantList &tones);
    void setShape(const QVariantMap &shape);

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();

signals:
    void changed();

private slots:
    void poll();

private:
    void setStatus(const QString &status);

    SynthDevice *m_device = nullptr;
    QAudioSink *m_sink = nullptr;
    QAudioFormat m_format;
    QTimer m_poll;
    QTimer m_releaseTimer;
    bool m_running = false;
    QString m_status = QStringLiteral("idle");
    QString m_detail;
    int m_requestedRate = 0;              // 0 = whatever the device prefers
    QString m_requestedFormatName;        // "float" / "int16" / empty = preferred
    int m_voices = 0;
    int m_peakVoices = 0;
    QElapsedTimer m_elapsed;
    double m_maxLagSeconds = 0.0;
    int m_lastFrames = 0;
    QVariantList m_tones;
    QVariantMap m_shapeMap;
};