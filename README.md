# Mac Graphic EQ for foobar2000

This is a foobar2000 macOS component that provides:

- A DSP named `Mac Graphic EQ`
- A visual graphic EQ that can be embedded in the foobar2000 main UI
- 31-band and 18-band modes
- A screenshot-style dark EQ surface with draggable band handles
- Persistent global settings
- An `On` checkbox that bypasses processing when off
- Preset load/save buttons and auto preamp leveling
- A foobar2000 Preferences page under the DSP section
- A macOS layout element matching `macgeq`, `graphic-eq`, or `Mac Graphic EQ`

The DSP implementation is a practical RBJ-style peaking-filter graphic EQ. It is not a direct port of `foo_dsp_xgeq` because public source for that Windows component was not found during setup.

## Build

Place the foobar2000 SDK next to this repo as `../sdk`, then build the SDK support libraries and component:

```sh
xcodebuild -project ../sdk/pfc/pfc.xcodeproj -target pfc-Mac -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/Debug" build
xcodebuild -project ../sdk/foobar2000/shared/shared.xcodeproj -target shared -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/Debug" build
xcodebuild -project ../sdk/foobar2000/SDK/foobar2000_SDK.xcodeproj -target foobar2000_SDK -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/Debug" build
xcodebuild -project ../sdk/foobar2000/helpers/foobar2000_SDK_helpers.xcodeproj -target foobar2000_SDK_helpers -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/Debug" build
xcodebuild -project ../sdk/foobar2000/foobar2000_component_client/foobar2000_component_client.xcodeproj -target foobar2000_component_client -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/Debug" build
xcodebuild -project foo_dsp_macgeq.xcodeproj -target foo_dsp_macgeq -configuration Debug build
```

The built component is:

```text
build/Debug/foo_dsp_macgeq.component
```

Install it to:

```text
~/Library/foobar2000-v2/user-components/foo_dsp_macgeq/foo_dsp_macgeq.component
```

## foobar2000 Mac layout

After installing the component and restarting foobar2000, add the UI with one of these layout names:

```text
macgeq
```

or:

```text
graphic-eq
```

The DSP must also be added to the active DSP chain for audio processing. The embedded UI controls the same persistent settings as the DSP.
