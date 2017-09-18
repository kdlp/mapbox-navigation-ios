import Foundation
import CoreLocation
import OSRMTextInstructions
import MapboxDirections
import AVFoundation

/**
 Formatter for creating speech strings.
 */
@objc(MBSpokenInstructionFormatter)
public class SpokenInstructionFormatter: NSObject {
    
    let routeStepFormatter = RouteStepFormatter()
    let maneuverVoiceDistanceFormatter = SpokenDistanceFormatter(approximate: true)
    
    public override init() {
        maneuverVoiceDistanceFormatter.unitStyle = .long
        maneuverVoiceDistanceFormatter.numberFormatter.locale = .nationalizedCurrent
    }
    
    /**
     Creates a string used for announcing a step.
     
     If `markUpWithSSML` is true, the string will contain [SSML](https://developer.amazon.com/public/solutions/alexa/alexa-skills-kit/docs/speech-synthesis-markup-language-ssml-reference). Your speech synthesizer should accept this type of string. See `PolleyVoiceController`.
     */
    public func string(routeProgress: RouteProgress, userDistance: CLLocationDistance, markUpWithSSML: Bool) -> String {
        return attributedString(routeProgress: routeProgress, userDistance: userDistance, markUpWithSSML: markUpWithSSML).string
    }
    
    /**
     Creates a string used for announcing a step.
     
     If `markUpWithSSML` is true, the string will contain [SSML](https://developer.amazon.com/public/solutions/alexa/alexa-skills-kit/docs/speech-synthesis-markup-language-ssml-reference). Your speech synthesizer should accept this type of string. See `PolleyVoiceController`.
    */
    public func attributedString(routeProgress: RouteProgress, userDistance: CLLocationDistance, markUpWithSSML: Bool) -> NSAttributedString {
        let alertLevel = routeProgress.currentLegProgress.alertUserLevel
        
        let escapeIfNecessary = {(distance: NSAttributedString) -> NSAttributedString in
            return markUpWithSSML ? NSAttributedString(string: distance.string.addingXMLEscapes) : distance
        }
        
        // If the current step arrives at a waypoint, the upcoming step is part of the next leg.
        let upcomingLegIndex = routeProgress.currentLegProgress.currentStep.maneuverType == .arrive ? routeProgress.legIndex + 1 :routeProgress.legIndex
        // Even if the next waypoint and the waypoint after that have the same coordinates, there will still be a step in between the two arrival steps. So the upcoming and follow-on steps are guaranteed to be part of the same leg.
        let followOnLegIndex = upcomingLegIndex
        
        // Handle arriving at the final destination
        //
        let numberOfLegs = routeProgress.route.legs.count
        guard let followOnInstruction = routeStepFormatter.attributedString(for: routeProgress.currentLegProgress.followOnStep, legIndex: followOnLegIndex, numberOfLegs: numberOfLegs, markUpWithSSML: markUpWithSSML) else {
            let upComingStepInstruction = routeStepFormatter.attributedString(for: routeProgress.currentLegProgress.upComingStep, legIndex: upcomingLegIndex, numberOfLegs: numberOfLegs, markUpWithSSML: markUpWithSSML)!
            var text: NSAttributedString
            if alertLevel == .arrive {
                text = upComingStepInstruction
            } else {
                let phrase = escapeIfNecessary(NSAttributedString(string: routeStepFormatter.instructions.phrase(named: .instructionWithDistance)))
                text = phrase.replacingTokens { (tokenType) -> NSAttributedString in
                    switch tokenType {
                    case .firstInstruction:
                        return upComingStepInstruction
                    case .distance:
                        return escapeIfNecessary(NSAttributedString(string: maneuverVoiceDistanceFormatter.string(from: userDistance)))
                    default:
                        fatalError("Unexpected token \(tokenType)")
                    }
                }
            }
            
            return text
        }
        
        // If there is no `upComingStep`, there definitely should not be a followOnStep.
        // This should be caught above.
        let upComingInstruction = routeStepFormatter.attributedString(for: routeProgress.currentLegProgress.upComingStep, legIndex: upcomingLegIndex, numberOfLegs: numberOfLegs, markUpWithSSML: markUpWithSSML)!
        let upcomingStepDuration = routeProgress.currentLegProgress.upComingStep!.expectedTravelTime
        let currentInstruction = routeStepFormatter.attributedString(for: routeProgress.currentLegProgress.currentStep, legIndex: routeProgress.legIndex, numberOfLegs: numberOfLegs, markUpWithSSML: markUpWithSSML)
        let step = routeProgress.currentLegProgress.currentStep
        var text: NSAttributedString
        
        // Prevent back to back instructions by adding a little more wiggle room
        let linkedInstructionMultiplier = RouteControllerHighAlertInterval * RouteControllerLinkedInstructionBufferMultiplier
        
        // We only want to announce this special departure announcement once.
        // Once it has been announced, all subsequnt announcements will not have an alert level of low
        // since the user will be approaching the maneuver location.
        let isStartingDeparture = routeProgress.currentLegProgress.currentStep.maneuverType == .depart && (alertLevel == .depart || alertLevel == .low)
        let formattedDistance = escapeIfNecessary(NSAttributedString(string: maneuverVoiceDistanceFormatter.string(from: userDistance)))
        if let currentInstruction = currentInstruction, isStartingDeparture {
            if routeProgress.currentLegProgress.currentStep.distance > RouteControllerMinDistanceForContinueInstruction {
                text = currentInstruction
            } else if upcomingStepDuration > linkedInstructionMultiplier {
                // If the upcoming step is an .exitRoundabout or .exitRotary, don't link the instruction
                if let followOnStep = routeProgress.currentLegProgress.followOnStep, followOnStep.maneuverType == .exitRoundabout || followOnStep.maneuverType == .exitRotary {
                    text = upComingInstruction
                } else {
                    let phrase = escapeIfNecessary(NSAttributedString(string: routeStepFormatter.instructions.phrase(named: .twoInstructionsWithDistance)))
                    text = phrase.replacingTokens { (tokenType) -> NSAttributedString in
                        switch tokenType {
                        case .firstInstruction:
                            return currentInstruction
                        case .secondInstruction:
                            return upComingInstruction
                        case .distance:
                            return formattedDistance
                        default:
                            fatalError("Unexpected token \(tokenType)")
                        }
                    }
                }
            } else {
                text = upComingInstruction
            }
        } else if routeProgress.currentLegProgress.currentStep.distance > RouteControllerMinDistanceForContinueInstruction && routeProgress.currentLegProgress.alertUserLevel == .low {
            if isStartingDeparture && upcomingStepDuration < linkedInstructionMultiplier {
                let phrase = escapeIfNecessary(NSAttributedString(string: routeStepFormatter.instructions.phrase(named: .twoInstructionsWithDistance)))
                text = phrase.replacingTokens { (tokenType) -> NSAttributedString in
                    switch tokenType {
                    case .firstInstruction:
                        return currentInstruction!
                    case .secondInstruction:
                        return upComingInstruction
                    case .distance:
                        return formattedDistance
                    default:
                        fatalError("Unexpected token \(tokenType)")
                    }
                }
            } else if let roadDescription = step.roadDescription(markedUpWithSSML: markUpWithSSML) {
                let format = NSLocalizedString("CONTINUE_ON_ROAD", bundle: .mapboxCoreNavigation, value: "Continue on %@ for %@", comment: "Format for speech string after completing a maneuver and starting a new step; 1 = way name; 2 = distance")
                text = NSAttributedString(string: String.localizedStringWithFormat(format, "{way_name}", "{distance}")).replacingTokens { (tokenType) in
                    switch tokenType {
                    case .wayName:
                        let roadDescription = NSMutableAttributedString(string: roadDescription)
                        if #available(iOS 10.0, *), let phoneticName = step.phoneticNames?.first {
                            return roadDescription.pronounced(phoneticName)
                        }
                        return roadDescription
                    case .distance:
                        return formattedDistance
                    default:
                        fatalError("Unexpected token \(tokenType)")
                    }
                }
            } else {
                let format = NSLocalizedString("CONTINUE", bundle: .mapboxCoreNavigation, value: "Continue for %@", comment: "Format for speech string after completing a maneuver and starting a new step; 1 = distance")
                text = NSAttributedString(string: String.localizedStringWithFormat(format, "{distance}")).replacingTokens { (tokenType) -> NSAttributedString in
                    switch tokenType {
                    case .distance:
                        return formattedDistance
                    default:
                        fatalError("Unexpected token \(tokenType)")
                    }
                }
            }
        } else if alertLevel == .high && upcomingStepDuration < linkedInstructionMultiplier {
            // If the upcoming step is an .exitRoundabout or .exitRotary, don't link the instruction
            if let followOnStep = routeProgress.currentLegProgress.followOnStep, followOnStep.maneuverType == .exitRoundabout || followOnStep.maneuverType == .exitRotary {
                text = upComingInstruction
            } else {
                let phrase = escapeIfNecessary(NSAttributedString(string: routeStepFormatter.instructions.phrase(named: .twoInstructions)))
                text = phrase.replacingTokens { (tokenType) -> NSAttributedString in
                    switch tokenType {
                    case .firstInstruction:
                        return upComingInstruction
                    case .secondInstruction:
                        return followOnInstruction
                    default:
                        fatalError("Unexpected token \(tokenType)")
                    }
                }
            }
        } else if alertLevel != .high {
            let phrase = escapeIfNecessary(NSAttributedString(string: routeStepFormatter.instructions.phrase(named: .instructionWithDistance)))
            text = phrase.replacingTokens { (tokenType) -> NSAttributedString in
                switch tokenType {
                case .firstInstruction:
                    return upComingInstruction
                case .distance:
                    return formattedDistance
                default:
                    fatalError("Unexpected token \(tokenType)")
                }
            }
        } else {
            text = upComingInstruction
        }
        
        return text
    }
}
