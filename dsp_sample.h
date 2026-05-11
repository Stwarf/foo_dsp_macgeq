#pragma once

#include <array>

namespace macgeq {

static constexpr size_t band_count = 31;

enum class BandMode : t_uint32 {
    ThirtyOne = 0,
    Visual = 1,
};

struct EqSettings {
    bool enabled = false;
    BandMode bandMode = BandMode::ThirtyOne;
    float preampDb = 0.0f;
    float gainsDb[band_count] = {};
};

static constexpr GUID dsp_guid = { 0xaa2b0596, 0x3ca5, 0x4544, { 0x9b, 0x55, 0x35, 0xd5, 0x0f, 0xbb, 0xce, 0xb1 } };
static constexpr GUID cfg_guid = { 0x1d9fdfdc, 0x6cac, 0x4218, { 0x92, 0x32, 0x11, 0x13, 0xa7, 0xab, 0x79, 0xf1 } };
static constexpr GUID cfg_guid_v2 = { 0x7733d8e4, 0x7754, 0x4d44, { 0x91, 0x35, 0xba, 0xa5, 0xcd, 0x4a, 0xd7, 0xc8 } };
static constexpr GUID ui_guid = { 0xb6575597, 0x9bff, 0x4d0b, { 0x81, 0x03, 0x95, 0xc0, 0x2b, 0x92, 0x93, 0x3f } };
static constexpr GUID preferences_guid = { 0xd36c3d83, 0x6079, 0x47d6, { 0x94, 0xaf, 0x91, 0x4b, 0x91, 0xc8, 0x1f, 0x9d } };

size_t active_band_count(BandMode mode);
const std::array<float, band_count> & band_frequencies(BandMode mode);
const char * band_mode_name(BandMode mode);

EqSettings default_settings();
EqSettings get_settings();
void set_settings(const EqSettings & settings);
void reset_settings();
t_uint64 get_settings_generation();

void make_preset(dsp_preset & out);

}
