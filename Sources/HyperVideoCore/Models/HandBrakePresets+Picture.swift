import Foundation

extension HandBrakePresets {
    static func applyPicture(_ p: Fields, to s: inout EncodeSettings, notes: inout [String]) {
        s.maxResolution = maxResolution(height: p.int("PictureHeight"))
        (s.rotation, s.flipHorizontal) = rotation(p.string("PictureRotate"))
        s.pictureOptions.cropMode = cropMode(p)
        if s.pictureOptions.cropMode == .custom {
            s.crop = Crop(top: p.int("PictureTopCrop"), bottom: p.int("PictureBottomCrop"),
                          left: p.int("PictureLeftCrop"), right: p.int("PictureRightCrop"))
        }
        s.pictureOptions.allowUpscaling = p.bool("PictureAllowUpscaling") ?? false
        s.pictureOptions.anamorphic = anamorphic(p.string("PicturePAR"), notes: &notes)
        s.pictureOptions.padding = padding(p, notes: &notes)
    }

    /// HandBrake 1.10 values: 0 Automatic, 1 Conservative, 2 None, 3 Custom.
    static func cropMode(_ p: Fields) -> CropMode {
        switch p.optionalInt("PictureCropMode") {
        case 0: .automatic
        case 1: .conservative
        case 2: .none
        case 3: .custom
        default: p.bool("PictureAutoCrop") == true ? .automatic : .custom
        }
    }

    static func anamorphic(_ value: String?, notes: inout [String]) -> Anamorphic {
        switch value {
        case "auto", "loose": return .automatic
        case "custom":
            notes.append("Custom pixel aspect isn't available, so it uses Automatic.")
            return .automatic
        default: return .none
        }
    }

    static func padding(_ p: Fields, notes: inout [String]) -> Padding {
        var padding = Padding()
        switch p.string("PicturePadMode") {
        case "letterbox": padding.mode = .letterbox
        case "pillarbox": padding.mode = .pillarbox
        case "fill": padding.mode = .both
        case "custom":
            padding.mode = .both
            notes.append("Custom border sizes aren't available, so it fills the frame.")
        default: padding.mode = .none
        }
        guard let color = p.string("PicturePadColor") else { return padding }
        applyColor(color, to: &padding, notes: &notes)
        return padding
    }

    private static func applyColor(_ color: String, to padding: inout Padding, notes: inout [String]) {
        switch color.lowercased() {
        case "black": padding.color = .black
        case "white": padding.color = .white
        case "slategray", "gray", "grey": padding.color = .gray
        case "darkslategray", "darkgray", "darkgrey": padding.color = .darkGray
        default:
            if let hex = sixDigitHex(color) {
                padding.color = .custom
                padding.customHex = hex
            } else {
                notes.append("The \(color) border colour isn't available, so it uses Black.")
            }
        }
    }

    /// Only exact six-digit hex strings ("#RRGGBB", "0xRRGGBB" or bare) count as colours.
    static func sixDigitHex(_ value: String) -> String? {
        var hex = value
        for prefix in ["#", "0x", "0X"] where hex.hasPrefix(prefix) {
            hex = String(hex.dropFirst(prefix.count))
            break
        }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex.uppercased()
    }
}
