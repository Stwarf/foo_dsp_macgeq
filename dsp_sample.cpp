#include "stdafx.h"
#include "dsp_sample.h"

#include <SDK/cfg_var.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <cmath>
#include <mutex>
#include <vector>

#ifdef __APPLE__
service_ptr ConfigureMacGEQDSP(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback);
#endif

namespace macgeq {
namespace {

cfg_struct_t<EqSettings> cfg_settings(cfg_guid_v2, default_settings());
std::mutex g_settings_mutex;
std::once_flag g_settings_loaded;
EqSettings g_cached_settings = default_settings();
std::atomic<t_uint64> g_settings_generation { 1 };

void ensure_settings_loaded() {
    std::call_once(g_settings_loaded, [] {
        std::lock_guard<std::mutex> lock(g_settings_mutex);
        g_cached_settings = cfg_settings.get();
    });
}

}

struct Biquad {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
    double z1 = 0.0, z2 = 0.0;

    void set_peak(double sampleRate, double frequency, double gainDb, double q) {
        if (std::abs(gainDb) < 0.001 || sampleRate <= 0 || frequency <= 0 || frequency >= sampleRate * 0.49) {
            b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0;
            return;
        }

        const double a = std::pow(10.0, gainDb / 40.0);
        const double w0 = 2.0 * M_PI * frequency / sampleRate;
        const double alpha = std::sin(w0) / (2.0 * q);
        const double cosw0 = std::cos(w0);

        const double rawB0 = 1.0 + alpha * a;
        const double rawB1 = -2.0 * cosw0;
        const double rawB2 = 1.0 - alpha * a;
        const double rawA0 = 1.0 + alpha / a;
        const double rawA1 = -2.0 * cosw0;
        const double rawA2 = 1.0 - alpha / a;

        b0 = rawB0 / rawA0;
        b1 = rawB1 / rawA0;
        b2 = rawB2 / rawA0;
        a1 = rawA1 / rawA0;
        a2 = rawA2 / rawA0;
    }

    audio_sample process(audio_sample input) {
        const double out = b0 * input + z1;
        z1 = b1 * input - a1 * out + z2;
        z2 = b2 * input - a2 * out;
        return (audio_sample) out;
    }

    void clear() {
        z1 = 0.0;
        z2 = 0.0;
    }
};

size_t active_band_count(BandMode mode) {
    return mode == BandMode::Visual ? 18 : band_count;
}

const std::array<float, band_count> & band_frequencies(BandMode mode) {
    static const std::array<float, band_count> freqs31 = {
        20.0f, 25.0f, 31.5f, 40.0f, 50.0f, 63.0f, 80.0f, 100.0f,
        125.0f, 160.0f, 200.0f, 250.0f, 315.0f, 400.0f, 500.0f,
        630.0f, 800.0f, 1000.0f, 1250.0f, 1600.0f, 2000.0f, 2500.0f,
        3150.0f, 4000.0f, 5000.0f, 6300.0f, 8000.0f, 10000.0f,
        12500.0f, 16000.0f, 20000.0f
    };
    static const std::array<float, band_count> freqsVisual = {
        55.0f, 77.0f, 110.0f, 156.0f, 220.0f, 311.0f, 440.0f, 622.0f,
        880.0f, 1200.0f, 1800.0f, 2500.0f, 3500.0f, 5000.0f, 7000.0f,
        10000.0f, 14000.0f, 20000.0f,
        0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 0.0f
    };
    return mode == BandMode::Visual ? freqsVisual : freqs31;
}

const char * band_mode_name(BandMode mode) {
    return mode == BandMode::Visual ? "18 bands" : "31 bands";
}

EqSettings default_settings() {
    EqSettings settings = {};
    settings.enabled = false;
    settings.bandMode = BandMode::ThirtyOne;
    settings.preampDb = 0.0f;
    return settings;
}

EqSettings get_settings() {
    ensure_settings_loaded();
    std::lock_guard<std::mutex> lock(g_settings_mutex);
    return g_cached_settings;
}

void set_settings(const EqSettings & settings) {
    ensure_settings_loaded();
    EqSettings clipped = settings;
    if (clipped.bandMode != BandMode::ThirtyOne && clipped.bandMode != BandMode::Visual) {
        clipped.bandMode = BandMode::ThirtyOne;
    }
    clipped.preampDb = std::clamp(clipped.preampDb, -24.0f, 12.0f);
    for (float & gain : clipped.gainsDb) gain = std::clamp(gain, -12.0f, 12.0f);
    {
        std::lock_guard<std::mutex> lock(g_settings_mutex);
        g_cached_settings = clipped;
    }
    g_settings_generation.fetch_add(1, std::memory_order_release);
    cfg_settings = clipped;
}

void reset_settings() {
    set_settings(default_settings());
}

t_uint64 get_settings_generation() {
    ensure_settings_loaded();
    return g_settings_generation.load(std::memory_order_acquire);
}

void make_preset(dsp_preset & out) {
    dsp_preset_builder builder;
    builder << (t_uint32) 1;
    builder.finish(dsp_guid, out);
}

}

class dsp_macgeq : public dsp_impl_base {
public:
    dsp_macgeq(const dsp_preset &) {}

    static GUID g_get_guid() { return macgeq::dsp_guid; }
    static void g_get_name(pfc::string_base & out) { out = "Mac Graphic EQ"; }

    bool on_chunk(audio_chunk * chunk, abort_callback &) {
        const t_uint64 generation = macgeq::get_settings_generation();
        const unsigned sampleRate = chunk->get_sample_rate();
        const unsigned channels = chunk->get_channels();
        if (generation != m_settingsGeneration) {
            m_currentSettings = macgeq::get_settings();
            m_settingsGeneration = generation;
            m_sampleRate = 0;
        }
        if (!m_currentSettings.enabled || chunk->is_empty()) return true;

        if (sampleRate != m_sampleRate || channels != m_channels) {
            rebuild_filters(m_currentSettings, sampleRate, channels);
        }

        audio_sample * data = chunk->get_data();
        const t_size samples = chunk->get_sample_count();
        const audio_sample preamp = (audio_sample) audio_math::gain_to_scale(m_currentSettings.preampDb);

        for (t_size frame = 0; frame < samples; ++frame) {
            for (unsigned ch = 0; ch < channels; ++ch) {
                audio_sample v = data[frame * channels + ch] * preamp;
                auto & filters = m_filters[ch];
                for (auto & filter : filters) v = filter.process(v);
                data[frame * channels + ch] = v;
            }
        }
        return true;
    }

    void on_endofplayback(abort_callback &) {}
    void on_endoftrack(abort_callback &) {}
    void flush() {
        for (auto & channel : m_filters) {
            for (auto & filter : channel) filter.clear();
        }
    }
    double get_latency() { return 0; }
    bool need_track_change_mark() { return false; }

    static bool g_get_default_preset(dsp_preset & out) {
        macgeq::make_preset(out);
        return true;
    }

#ifdef __APPLE__
    static service_ptr g_show_config_popup(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback) {
        return ConfigureMacGEQDSP(parent, callback);
    }
#endif
    static bool g_have_config_popup() { return true; }

private:
    using ChannelFilters = std::array<macgeq::Biquad, macgeq::band_count>;

    void rebuild_filters(const macgeq::EqSettings & settings, unsigned sampleRate, unsigned channels) {
        m_sampleRate = sampleRate;
        m_channels = channels;
        m_filters.assign(channels, ChannelFilters {});

        const auto & freqs = macgeq::band_frequencies(settings.bandMode);
        const size_t activeBands = macgeq::active_band_count(settings.bandMode);
        const double q = settings.bandMode == macgeq::BandMode::Visual ? 2.871 : 4.318;
        for (auto & channel : m_filters) {
            for (size_t band = 0; band < activeBands; ++band) {
                channel[band].set_peak(sampleRate, freqs[band], settings.gainsDb[band], q);
            }
        }
    }

    unsigned m_sampleRate = 0;
    unsigned m_channels = 0;
    t_uint64 m_settingsGeneration = 0;
    macgeq::EqSettings m_currentSettings = {};
    std::vector<ChannelFilters> m_filters;
};

static dsp_factory_t<dsp_macgeq> g_dsp_macgeq_factory;
