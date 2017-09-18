import Foundation
import AWSPolly
import AVFoundation
import MapboxCoreNavigation

/**
 `PollyVoiceController` extends the default `RouteVoiceController` by providing support for AWSPolly. `RouteVoiceController` will be used as a fallback during poor network conditions.
 */
@objc(MBPollyVoiceController)
public class PollyVoiceController: RouteVoiceController {
    
    /**
     Forces Polly voice to always be of specified type. If not set, a localized voice will be used.
     */
    public var globalVoiceId: AWSPollyVoiceId?
    
    /**
     `regionType` specifies what AWS region to use for Polly.
     */
    public var regionType: AWSRegionType = .USEast1
    
    /**
     `identityPoolId` is a required value for using AWS Polly voice instead of iOS's built in AVSpeechSynthesizer.
     You can get a token here: http://docs.aws.amazon.com/mobile/sdkforios/developerguide/cognito-auth-aws-identity-for-ios.html
     */
    public var identityPoolId: String
    
    /**
     Number of seconds a Polly request can wait before it is canceled and the default speech synthesizer speaks the instruction.
     */
    public var timeoutIntervalForRequest:TimeInterval = 2
    
    var pollyTask: URLSessionDataTask?
    
    let sessionConfiguration = URLSessionConfiguration.default
    var urlSession: URLSession
    
    public init(identityPoolId: String) {
        self.identityPoolId = identityPoolId
        
        let credentialsProvider = AWSCognitoCredentialsProvider(regionType: regionType, identityPoolId: identityPoolId)
        let configuration = AWSServiceConfiguration(region: regionType, credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        
        sessionConfiguration.timeoutIntervalForRequest = timeoutIntervalForRequest;
        urlSession = URLSession(configuration: sessionConfiguration)
        
        super.init()
    }
    
    public override func speak(for routeProgress: RouteProgress, userDistance: CLLocationDistance) {
        let text = spokenInstructionFormatter.string(routeProgress: routeProgress, userDistance: userDistance, markUpWithSSML: true)
        assert(!text.isEmpty)
        
        let input = AWSPollySynthesizeSpeechURLBuilderRequest()
        input.textType = .ssml
        input.outputFormat = .mp3
        
        let langs = Locale.preferredLocalLanguageCountryCode.components(separatedBy: "-")
        let langCode = langs[0]
        var countryCode = ""
        if langs.count > 1 {
            countryCode = langs[1]
        }
        
        switch (langCode, countryCode) {
        case ("de", _):
            input.voiceId = .marlene
        case ("en", "CA"):
            input.voiceId = .joanna
        case ("en", "GB"):
            input.voiceId = .brian
        case ("en", "AU"):
            input.voiceId = .nicole
        case ("en", "IN"):
            input.voiceId = .raveena
        case ("en", _):
            input.voiceId = .joanna
        case ("es", _):
            input.voiceId = .miguel
        case ("fr", _):
            input.voiceId = .celine
        case ("it", _):
            input.voiceId = .giorgio
        case ("nl", _):
            input.voiceId = .lotte
        case ("ru", _):
            input.voiceId = .maxim
        case ("sv", _):
            input.voiceId = .astrid
        default:
            print("Voice \(langCode)-\(countryCode) not found")
            super.speak(for: routeProgress, userDistance: userDistance)
            return
        }
        
        if let voiceId = globalVoiceId {
            input.voiceId = voiceId
        }
        
        input.text = "<speak><amazon:effect name=\"drc\"><prosody volume='\(instructionVoiceVolume)' rate='\(instructionVoiceSpeedRate)'>\(text)</prosody></amazon:effect></speak>"
        
        let builder = AWSPollySynthesizeSpeechURLBuilder.default().getPreSignedURL(input)
        builder.continueWith { [weak self] (awsTask: AWSTask<NSURL>) -> Any? in
            guard let strongSelf = self else {
                return nil
            }
            
            strongSelf.handle(awsTask, for: routeProgress, userDistance: userDistance)
            
            return nil
        }
    }
    
    /**
     Speak using a fallback mechanism that doesn’t involve Polly.
     
     This method exists because it isn’t possible to refer to super inside a closure.
     */
    func speakWithoutPolly(for routeProgress: RouteProgress, userDistance: CLLocationDistance) {
        super.speak(for: routeProgress, userDistance: userDistance)
    }
    
    func handle(_ awsTask: AWSTask<NSURL>, for routeProgress: RouteProgress, userDistance: CLLocationDistance) {
        if let error = awsTask.error {
            print(error)
            speakWithoutPolly(for: routeProgress, userDistance: userDistance)
            return
        }
        
        guard !awsTask.isCancelled else {
            return
        }
        
        guard let url = awsTask.result else {
            print("No polly response")
            speakWithoutPolly(for: routeProgress, userDistance: userDistance)
            return
        }
        
        pollyTask = urlSession.dataTask(with: url as URL) { [weak self] (data, response, error) in
            guard let strongSelf = self else { return }
            
            // If the task is canceled, don't speak.
            // But if it's some sort of other error, use fallback voice.
            if let error = error as? URLError, error.code == .cancelled {
                return
            } else if let error = error {
                print(error)
                strongSelf.speakWithoutPolly(for: routeProgress, userDistance: userDistance)
                return
            }
            
            guard let data = data else { return }
            
            DispatchQueue.main.async {
                do {
                    strongSelf.audioPlayer = try AVAudioPlayer(data: data)
                    strongSelf.audioPlayer?.delegate = self
                    
                    if let audioPlayer = strongSelf.audioPlayer {
                        try strongSelf.duckAudio()
                        audioPlayer.volume = strongSelf.volume
                        audioPlayer.play()
                    }
                } catch {
                    print(error)
                    strongSelf.speakWithoutPolly(for: routeProgress, userDistance: userDistance)
                }
            }

        }
        pollyTask?.resume()
        return
    }
}
