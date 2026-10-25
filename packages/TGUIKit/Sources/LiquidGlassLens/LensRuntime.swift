import AppKit
import ObjectiveC
import QuartzCore

final class LensRuntime {
    static let shared: LensRuntime? = {
        guard #available(macOS 26.0, *) else {
            return nil
        }
        return LensRuntime()
    }()

    private let layerTypes: [String: CALayer.Type]
    private let effectTypes: [String: NSObject.Type]
    private let filterClass: NSObjectProtocol
    private let filterSelector = NSSelectorFromString("filterWithName:")

    private init?() {
        let layers = ["CABackdropLayer", "CAPortalLayer", "CASDFLayer", "CASDFElementLayer"]
        let effects = ["CASDFOutputEffect", "CASDFGlassDisplacementEffect", "CASDFKeyFillHighlightEffect"]
        var layerTypes: [String: CALayer.Type] = [:]
        var effectTypes: [String: NSObject.Type] = [:]
        for name in layers {
            guard let type = NSClassFromString(name) as? CALayer.Type else {
                return nil
            }
            layerTypes[name] = type
        }
        for name in effects {
            guard let type = NSClassFromString(name) as? NSObject.Type else {
                return nil
            }
            effectTypes[name] = type
        }
        guard let filterType = NSClassFromString("CAFilter"),
              let filterClass = filterType as AnyObject as? NSObjectProtocol,
              let factory = class_getClassMethod(filterType, filterSelector),
              Self.matches(factory, result: "@", arguments: ["@"]),
              Self.supports(filterType, setters: ["name": "@"]),
              Self.supports(layerTypes["CABackdropLayer"]!, setters: ["scale": "d"]),
              Self.supports(layerTypes["CAPortalLayer"]!, setters: ["sourceLayer": "@", "hidesSourceLayer": "B", "matchesPosition": "B", "matchesTransform": "B"]),
              Self.supports(layerTypes["CASDFLayer"]!, setters: ["effect": "@", "smoothness": "d"]),
              Self.supports(layerTypes["CASDFElementLayer"]!, setters: ["mode": "@", "operation": "@"]),
              Self.supports(effectTypes["CASDFOutputEffect"]!, setters: ["minimum": "d", "maximum": "d"]),
              Self.supports(effectTypes["CASDFGlassDisplacementEffect"]!, setters: ["height": "d", "curvature": "d", "angle": "d", "maskOffset": "d"]),
              Self.supports(effectTypes["CASDFKeyFillHighlightEffect"]!, setters: [
                "keyColor": "^{CGColor", "fillColor": "^{CGColor", "keyHeight": "d", "fillHeight": "d",
                "keyAngle": "d", "fillAngle": "d", "keySpread": "d", "fillSpread": "d",
                "keyAmount": "d", "fillAmount": "d", "diffuseAmountScale": "d", "curvature": "d",
              ]) else {
            return nil
        }
        self.layerTypes = layerTypes
        self.effectTypes = effectTypes
        self.filterClass = filterClass
        guard makeFilter("glassBackground", inputs: LensSurface.backgroundInputs) != nil,
              makeFilter("glassForeground", inputs: LensSurface.foregroundInputs) != nil,
              makeFilter("gaussianBlur", inputs: ["inputRadius", "inputNormalizeEdges"]) != nil,
              makeFilter("colorMatrix", inputs: ["inputColorMatrix", "inputPremultipliedValues"]) != nil,
              makeFilter("vibrantColorMatrix", inputs: ["inputColorMatrix", "inputClamp"]) != nil,
              makeFilter("displacementMap", inputs: ["inputAmount", "inputSourceSublayerName"]) != nil else {
            return nil
        }
    }

    private static func supports(_ type: AnyClass, setters: [String: String]) -> Bool {
        for (key, argument) in setters {
            let selector = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            guard let method = class_getInstanceMethod(type, selector), matches(method, result: "v", arguments: [argument]) else {
                return false
            }
        }
        return true
    }

    private static func matches(_ method: Method, result: String, arguments: [String]) -> Bool {
        guard method_getNumberOfArguments(method) == arguments.count + 2 else {
            return false
        }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType).hasPrefix(result) else {
            return false
        }
        for (index, expected) in arguments.enumerated() {
            guard let argument = method_copyArgumentType(method, UInt32(index + 2)) else {
                return false
            }
            let actual = String(cString: argument)
            free(argument)
            guard actual.hasPrefix(expected) else {
                return false
            }
        }
        return true
    }

    func layer(_ name: String) -> CALayer {
        let layer = layerTypes[name]!.init()
        layer.anchorPoint = .zero
        layer.masksToBounds = false
        return layer
    }

    func effect(_ name: String) -> NSObject {
        return effectTypes[name]!.init()
    }

    func makeFilter(_ name: String, inputs: Set<String>) -> NSObject? {
        guard let filter = filterClass.perform(filterSelector, with: name)?.takeUnretainedValue() as? NSObject,
              filter.responds(to: NSSelectorFromString("inputKeys")),
              let keys = filter.value(forKey: "inputKeys") as? [String], inputs.isSubset(of: Set(keys)) else {
            return nil
        }
        return filter
    }

    func shape(size: CGSize, radius: CGFloat, effect: NSObject, name: String) -> CALayer {
        let field = layer("CASDFLayer")
        field.name = name
        field.frame = CGRect(origin: .zero, size: size)
        field.setValue(effect, forKey: "effect")
        field.setValue(0.0, forKey: "smoothness")
        let element = layer("CASDFElementLayer")
        element.frame = field.bounds
        element.cornerRadius = radius
        element.setValue("bounds", forKey: "mode")
        element.setValue("union", forKey: "operation")
        field.addSublayer(element)
        return field
    }
}
