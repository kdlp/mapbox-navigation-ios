import Foundation
import MapboxDirections
import OSRMTextInstructions
import AVFoundation

extension NSAttributedString {
    @available(iOS 10.0, *)
    func pronounced(_ pronunciation: String) -> NSAttributedString {
        let phoneticWords = pronunciation.components(separatedBy: " ")
        let phoneticString = NSMutableAttributedString()
        for (word, phoneticWord) in zip(string.components(separatedBy: " "), phoneticWords) {
            // AVSpeechSynthesizer doesn’t recognize some common IPA symbols.
            let phoneticWord = phoneticWord.byReplacing([("ɡ", "g"), ("ɹ", "r")])
            if phoneticString.length > 0 {
                phoneticString.append(NSAttributedString(string: " "))
            }
            phoneticString.append(NSAttributedString(string: word, attributes: [
                AVSpeechSynthesisIPANotationAttribute: phoneticWord,
            ]))
        }
        return phoneticString
    }
}

@objc(MBRouteStepFormatter)
public class RouteStepFormatter: Formatter {
    let instructions = OSRMInstructionFormatter(version: "v5")
    
    /**
     Return an instruction as a `String`.
     */
    public override func string(for obj: Any?) -> String? {
        return string(for: obj, legIndex: nil, numberOfLegs: nil, markUpWithSSML: false)
    }
    
    /**
     Returns an instruction describing the given route step.
     
     - parameter obj: The route step to describe.
     - parameter legIndex: The zero-based index of the leg containing the route step in the route.
     - parameter numberOfLegs: The number of legs in the route.
     - parameter markUpWithSSML: If `true`, the returned string is marked up as [SSML](https://www.w3.org/TR/speech-synthesis/).
     - returns: A string describing the route step, possibly marked up as SSML.
     */
    public func string(for obj: Any?, legIndex: Int?, numberOfLegs: Int?, markUpWithSSML: Bool) -> String? {
        guard let step = obj as? RouteStep else {
            return nil
        }
        
        let modifyValueByKey = { (key: OSRMTextInstructions.TokenType, value: String) -> String in
            if key == .wayName || key == .rotaryName, let phoneticName = step.phoneticNames?.first {
                return value.withSSMLPhoneme(ipaNotation: phoneticName)
            }
            
            switch key {
            case .wayName, .destination, .rotaryName, .code:
                var value = value
                value.enumerateSubstrings(in: value.wholeRange, options: [.byWords, .reverse]) { (substring, substringRange, enclosingRange, stop) in
                    guard var substring = substring?.addingXMLEscapes else {
                        return
                    }
                    
                    if substring.containsDecimalDigit {
                        substring = substring.asSSMLAddress
                    }
                    value.replaceSubrange(substringRange, with: substring)
                }
                return value
            default:
                return value
            }
        }
        
        return instructions.string(for: step, legIndex: legIndex, numberOfLegs: numberOfLegs, roadClasses: step.intersections?.first?.outletRoadClasses, modifyValueByKey: markUpWithSSML ? modifyValueByKey : nil)
        
    }
    
    /**
     Returns an instruction describing the given route step as an attributed string.
     
     Road names may be given an attribute indicating their pronunciations.
     
     - parameter obj: The route step to describe.
     - parameter attrs: Attributes to apply to the entire string.
     - parameter legIndex: The zero-based index of the leg containing the route step in the route.
     - parameter numberOfLegs: The number of legs in the route.
     - parameter modifyValueByKey: A closure that runs once for each token in the instruction’s template string.
     - returns: An attributed string describing the route step.
     */
    public func attributedString(for obj: Any, withDefaultAttributes attrs: [String : Any]? = nil, legIndex: Int?, numberOfLegs: Int?, modifyValueByKey: ((TokenType, NSAttributedString) -> NSAttributedString)?) -> NSAttributedString? {
        guard let step = obj as? RouteStep else {
            return nil
        }
        
        return instructions.attributedString(for: step, withDefaultAttributes: attrs, legIndex: legIndex, numberOfLegs: numberOfLegs, roadClasses: step.intersections?.first?.outletRoadClasses) { (key, value) -> NSAttributedString in
            // As of iOS 10, AVSpeechSynthesizer can’t handle an IPA notation attribute that spans multiple words.
            if #available(iOS 10.0, *), key == .wayName || key == .rotaryName, let phoneticName = step.phoneticNames?.first {
                return value.pronounced(phoneticName)
            }
            return value
        }
    }
    
    func attributedString(for obj: Any?, withDefaultAttributes attrs: [String : Any]? = nil, legIndex: Int?, numberOfLegs: Int?, markUpWithSSML: Bool) -> NSAttributedString? {
        guard let obj = obj else {
            return nil
        }
        
        if markUpWithSSML {
            if let ssmlString = string(for: obj, legIndex: legIndex, numberOfLegs: numberOfLegs, markUpWithSSML: true) {
                return NSAttributedString(string: ssmlString, attributes: attrs)
            } else {
                return nil
            }
        } else {
            return attributedString(for: obj, withDefaultAttributes: attrs, legIndex: legIndex, numberOfLegs: numberOfLegs) { (_, value) in
                return value
            }
        }
    }
    
    public override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        return false
    }
}
