#include "stdafx.h"

DECLARE_COMPONENT_VERSION(
    "Mac Graphic EQ",
    "0.1.0",
    "31-band graphic equalizer for foobar2000 Mac with persistent settings and an embeddable layout control."
);

VALIDATE_COMPONENT_FILENAME("foo_dsp_macgeq.component");

FOOBAR2000_IMPLEMENT_CFG_VAR_DOWNGRADE;
