import AppKit
import SwiftUI

struct CameraRawDetailControls: View {
    @Bindable var session: EditorSession
    private var settings: FilterSettings { session.filterEdit?.settings ?? FilterSettings() }
    private var raw: CameraRawSettings { settings.cameraRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sharpening").font(.subheadline)
            sharpenSlider("Amount", \.sharpenAmount, range: CameraRawDetailSettings.sharpenAmountRange, decimals: 0, reset: 0,
                          help: String(localized: "Controls how strong the sharpening is."))
            sharpenSlider("Radius", \.sharpenRadius, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 10,
                          help: String(localized: "How far from each edge the sharpening reaches, in pixels."))
            sharpenSlider("Detail", \.sharpenDetail, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 25,
                          help: String(localized: "Emphasizes fine texture over broader edges."))
            sharpenSlider("Masking", \.sharpenMasking, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 0,
                          maskingPreview: true, help: String(localized: "Limits sharpening to stronger edges. Hold Option to see the mask."))
            Text("Noise Reduction").font(.subheadline)
            slider("Luminance", \.noiseLuminance, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 0,
                   help: String(localized: "Smooths grain and noise in brightness."))
            Group {
                slider("Luminance Detail", \.noiseLuminanceDetail, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 50,
                       help: String(localized: "Preserves fine texture while luminance noise is reduced."))
                slider("Luminance Contrast", \.noiseLuminanceContrast, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 0,
                       help: String(localized: "Keeps local contrast after luminance smoothing."))
            }
            .opacity(raw.detail.noiseLuminance > 0 ? 1 : 0.45)
            .disabled(raw.detail.noiseLuminance <= 0)
            slider("Color", \.noiseColor, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 0,
                   help: String(localized: "Smooths colored speckles."))
            Group {
                slider("Color Detail", \.noiseColorDetail, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 50,
                       help: String(localized: "Preserves colored edges while color noise is reduced."))
                slider("Color Smoothness", \.noiseColorSmoothness, range: CameraRawDetailSettings.unitRange, decimals: 0, reset: 50,
                       help: String(localized: "Makes the color smoothing softer or tighter."))
            }
            .opacity(raw.detail.noiseColor > 0 ? 1 : 0.45)
            .disabled(raw.detail.noiseColor <= 0)
        }
    }

    private func sharpenSlider(_ title: LocalizedStringKey, _ key: WritableKeyPath<CameraRawDetailSettings, Double>, range: ClosedRange<Double>,
                               decimals: Int, reset: Double, maskingPreview: Bool = false, help: String) -> some View {
        let step = pow(10, Double(decimals))
        let value = raw.detail[keyPath: key]
        return HStack(spacing: 10) {
            Text(title).frame(minWidth: CameraRawControls.labelWidth, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1 / step,
                            value: Binding(get: { raw.detail[keyPath: key] },
                                           set: { assignDetail(key, $0, maskingPreview: false) }), range: range)
            CameraRawSlider(value: value, range: range, track: .plain, help: help,
                            onChange: { rawValue in
                                let stepped = (rawValue * step).rounded() / step
                                assignDetail(key, stepped, maskingPreview: maskingPreview)
                            },
                            onReset: { assignDetail(key, reset, maskingPreview: false) })
            TextField(title, value: Binding(get: { raw.detail[keyPath: key] }, set: { assignDetail(key, $0, maskingPreview: false) }),
                      format: .number.precision(.fractionLength(0...decimals)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).help(help)
        }
    }

    private func slider(_ title: LocalizedStringKey, _ key: WritableKeyPath<CameraRawDetailSettings, Double>, range: ClosedRange<Double>,
                        decimals: Int, reset: Double, help: String) -> some View {
        sharpenSlider(title, key, range: range, decimals: decimals, reset: reset, help: help)
    }

    private func assignDetail(_ key: WritableKeyPath<CameraRawDetailSettings, Double>, _ newValue: Double, maskingPreview: Bool) {
        if maskingPreview {
            session.filterEdit?.cameraRawSharpenMask = NSEvent.modifierFlags.contains(.option)
        } else {
            session.filterEdit?.cameraRawSharpenMask = false
        }
        update { settings in settings.cameraRaw.detail[keyPath: key] = newValue }
    }

    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: session.filterEdit?.preview ?? true)
    }
}

struct CameraRawOpticsControls: View {
    @Bindable var session: EditorSession
    private var settings: FilterSettings { session.filterEdit?.settings ?? FilterSettings() }
    private var raw: CameraRawSettings { settings.cameraRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Remove Chromatic Aberration", isOn: binding(\.removeChromaticAberration))
                .help("Pulls red and blue fringes apart toward the center to reduce color edging.")
            Toggle("Enable Lens Profile Corrections", isOn: binding(\.enableLensProfile))
                .help("Applies generic profile strength when camera metadata is not available.")
            if raw.optics.enableLensProfile {
                Text("No lens metadata on this layer. Profile sliders set generic correction strength.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                opticsSlider("Distortion", \.profileDistortion, range: CameraRawOpticsSettings.unitRange, reset: 100,
                             help: String(localized: "How much of the profile distortion correction is applied."))
                opticsSlider("Vignetting", \.profileVignetting, range: CameraRawOpticsSettings.unitRange, reset: 100,
                             help: String(localized: "How much of the profile vignetting correction is applied."))
            }
            Text("Manual").font(.subheadline)
            opticsSlider("Distortion", \.distortion, range: CameraRawOpticsSettings.toneRange, reset: 0,
                         help: String(localized: "Straightens barrel or pincushion bending."))
            HStack(spacing: 10) {
                Text("Defringe").frame(minWidth: CameraRawControls.labelWidth, alignment: .leading)
                    .help("Click a purple or green fringe to set its hue range.")
                Button {
                    session.filterEdit?.samplesDefringe.toggle()
                    session.brushRevision += 1
                } label: {
                    Image(systemName: "eyedropper")
                }
                .buttonStyle(.borderless)
                .tint(session.filterEdit?.samplesDefringe == true ? Color.accentColor : Color.secondary)
                .help("Click a purple or green fringe to set its hue range.")
            }
            if session.filterEdit?.samplesDefringe == true {
                Text("Click the fringe on the layer. Click the eyedropper again to stop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            opticsSlider("Purple Amount", \.purpleAmount, range: CameraRawOpticsSettings.unitRange, reset: 0,
                         help: String(localized: "Weakens purple fringes inside the purple hue range."))
            hueRange("Purple Hue", low: \.purpleHueLow, high: \.purpleHueHigh, resetLow: 270, resetHigh: 310,
                     help: String(localized: "Hue range where purple defringe runs."))
            opticsSlider("Green Amount", \.greenAmount, range: CameraRawOpticsSettings.unitRange, reset: 0,
                         help: String(localized: "Weakens green fringes inside the green hue range."))
            hueRange("Green Hue", low: \.greenHueLow, high: \.greenHueHigh, resetLow: 60, resetHigh: 120,
                     help: String(localized: "Hue range where green defringe runs."))
            opticsSlider("Vignetting", \.vignetteAmount, range: CameraRawOpticsSettings.toneRange, reset: 0,
                         help: String(localized: "Brightens or darkens the corners to counter lens falloff."))
            opticsSlider("Midpoint", \.vignetteMidpoint, range: CameraRawOpticsSettings.unitRange, reset: 50,
                         help: String(localized: "Moves the vignette correction inward or outward."))
        }
    }

    private func binding(_ key: WritableKeyPath<CameraRawOpticsSettings, Bool>) -> Binding<Bool> {
        Binding(get: { raw.optics[keyPath: key] }, set: { newValue in update { $0.cameraRaw.optics[keyPath: key] = newValue } })
    }

    private func opticsSlider(_ title: LocalizedStringKey, _ key: WritableKeyPath<CameraRawOpticsSettings, Double>, range: ClosedRange<Double>,
                              reset: Double, help: String) -> some View {
        let value = raw.optics[keyPath: key]
        return HStack(spacing: 10) {
            Text(title).frame(minWidth: CameraRawControls.labelWidth, alignment: .leading).help(help)
                .scrubbable(sensitivity: 1,
                            value: Binding(get: { raw.optics[keyPath: key] },
                                           set: { newValue in update { $0.cameraRaw.optics[keyPath: key] = newValue } }), range: range)
            CameraRawSlider(value: value, range: range, track: .plain, help: help,
                            onChange: { rawValue in
                                let stepped = range.lowerBound < 0 ? rawValue : rawValue.rounded()
                                update { $0.cameraRaw.optics[keyPath: key] = stepped }
                            },
                            onReset: { update { $0.cameraRaw.optics[keyPath: key] = reset } })
            TextField(title, value: Binding(get: { raw.optics[keyPath: key] }, set: { newValue in update { $0.cameraRaw.optics[keyPath: key] = newValue } }),
                      format: .number.precision(.fractionLength(0)))
                .frame(width: 56).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).help(help)
        }
    }

    private func hueRange(_ title: LocalizedStringKey, low: WritableKeyPath<CameraRawOpticsSettings, Double>,
                          high: WritableKeyPath<CameraRawOpticsSettings, Double>,
                          resetLow: Double, resetHigh: Double, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).help(help)
            HStack(spacing: 8) {
                Text("Low").font(.caption2).help("Start of the hue range, in degrees.")
                CameraRawSlider(value: raw.optics[keyPath: low], range: CameraRawOpticsSettings.hueRange, track: .plain,
                                help: String(localized: "Start of the hue range, in degrees."),
                                onChange: { value in update { $0.cameraRaw.optics[keyPath: low] = value.rounded() } },
                                onReset: { update { $0.cameraRaw.optics[keyPath: low] = resetLow } })
                Text("High").font(.caption2).help("End of the hue range, in degrees.")
                CameraRawSlider(value: raw.optics[keyPath: high], range: CameraRawOpticsSettings.hueRange, track: .plain,
                                help: String(localized: "End of the hue range, in degrees."),
                                onChange: { value in update { $0.cameraRaw.optics[keyPath: high] = value.rounded() } },
                                onReset: { update { $0.cameraRaw.optics[keyPath: high] = resetHigh } })
            }
        }
        .padding(.leading, CameraRawControls.labelWidth + 10)
    }

    private func update(_ change: (inout FilterSettings) -> Void) {
        var value = settings
        change(&value)
        session.updateFilter(value, preview: session.filterEdit?.preview ?? true)
    }
}
