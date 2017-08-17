//
//  ViewController.swift
//  VRCameraApp
//
//  Created by yuhoshino on 2017/08/09.
//  Copyright © 2017 yuhoshino. All rights reserved.
//

import UIKit
import Photos
import AVFoundation
import AudioToolbox

private func AudioQueueInputCallback(
    _ inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef,
    inStartTime: UnsafePointer<AudioTimeStamp>,
    inNumberPacketDescriptions: UInt32,
    inPacketDescs: UnsafePointer<AudioStreamPacketDescription>?)
{
    // Do nothing, because not recoding.
}

class ViewController: UIViewController {
    
    let screenWidth = UIScreen.main.bounds.size.width
    let screenHeight = UIScreen.main.bounds.size.height
    
    let captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice?
    
    @IBOutlet var touchView: UIView!
    @IBOutlet var leftEyeImageView: UIImageView!
    @IBOutlet var rightEyeImageView: UIImageView!
    @IBOutlet weak var EyeSplitLine: UIView!
    
    let filterNames: [String] = ["CIComicEffect",
                                 "CILineOverlay",
                                 "CISpotColor",
                                 "CIColorInvert",
                                 "CIEdgeWork",
                                 "CIEdges",
                                 "CIHeightFieldFromMask",
                                 "CIColorMonochrome"]
    var currentFilterIndex = 0
    var currentFilterName: String = ""
    var player: AVAudioPlayer?
    var vrMode = true

    @IBOutlet weak var helpMenuButton: UIButton!
    
    var voiceCommandTimer: Timer!
    var voiceCommandQueue: AudioQueueRef!
    var isVoiceCommandFinished = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.currentFilterName = filterNames[currentFilterIndex]

        self.setupEyeFrame()
        self.checkCameraAvailability()
        self.setupVoiceCommand()
    }
    
    private func setupVoiceCommand() {
        var dataFormat = AudioStreamBasicDescription(mSampleRate: 44100.0,
                                                     mFormatID: kAudioFormatLinearPCM,
                                                     mFormatFlags: AudioFormatFlags(kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
                                                     mBytesPerPacket: 2,
                                                     mFramesPerPacket: 1,
                                                     mBytesPerFrame: 2,
                                                     mChannelsPerFrame: 1,
                                                     mBitsPerChannel: 16,
                                                     mReserved: 0)
        
        var audioQueue: AudioQueueRef? = nil
        var error = noErr
        error = AudioQueueNewInput(&dataFormat,
                                   AudioQueueInputCallback,
                                   UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                   .none,
                                   .none,
                                   0,
                                   &audioQueue)
        if error == noErr {
            self.voiceCommandQueue = audioQueue
        }
        AudioQueueStart(self.voiceCommandQueue, nil)
        
        
        // Enable level meter
        var enabledLevelMeter: UInt32 = 1
        AudioQueueSetProperty(self.voiceCommandQueue, kAudioQueueProperty_EnableLevelMetering, &enabledLevelMeter, UInt32(MemoryLayout<UInt32>.size))
        
        self.voiceCommandTimer = Timer.scheduledTimer(timeInterval: 0.05,
                                          target: self,
                                          selector: #selector(detectVolume(_:)),
                                          userInfo: nil,
                                          repeats: true)
        self.voiceCommandTimer.fire()
    }
    
    @objc func detectVolume(_ timer: Timer) {
        // Get level
        var levelMeter = AudioQueueLevelMeterState()
        var propertySize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size)
        
        AudioQueueGetProperty(
            self.voiceCommandQueue,
            kAudioQueueProperty_CurrentLevelMeterDB,
            &levelMeter,
            &propertySize)
        if levelMeter.mPeakPower >= -10.0 {
            if !self.isVoiceCommandFinished {
                self.isVoiceCommandFinished = true
                self.changeFilter()
                self.playSound(name: "poyo")
                let when = DispatchTime.now() + 1.5
                DispatchQueue.main.asyncAfter(deadline: when, execute: {
                    self.isVoiceCommandFinished = false
                })
            }
        }
    }
    
    @IBAction func showHelpMenu(_ sender: UIButton) {
        let alert = UIAlertController(title: "使い方",
                                      message: "１回タップでフィルターを切り替え\n2回タップでVR/通常モードを切り替え\n映像画面を長押しで写真を撮る",
                                      preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: UIAlertActionStyle.cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func checkCameraAvailability() {
        if AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) ==  AVAuthorizationStatus.authorized {
            self.setupCaptureDevice()
        } else {
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (granted: Bool) -> Void in
                if granted == true {
                    self.setupCaptureDevice()
                } else {
                    let alert = UIAlertController(title: "カメラが有効になっていません", message: "「設定」→「プライバシー」→「カメラ」→「VRカメラ」を有効にしてください", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "閉じる", style: UIAlertActionStyle.cancel, handler: { _ in
                        self.checkCameraAvailability()
                    }))
                    self.present(alert, animated: true, completion: nil)
                }
            })
        }
    }
    
    func setupCaptureDevice() {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        let device = AVCaptureDevice.defaultDevice(withDeviceType: AVCaptureDeviceType.builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back)
        captureDevice = device
        
        if(captureDevice != nil) {
            beginSession()
        }
    }
    
    func setupEyeFrame() {
        self.rightEyeImageView.frame = CGRect(x: 0, y: 0, width: screenWidth/2, height: screenHeight)
        self.leftEyeImageView.frame = CGRect(x: screenWidth/2, y: 0, width: screenWidth/2, height: screenHeight)
        self.EyeSplitLine.frame = CGRect(x: screenWidth/2 - 1, y: 0, width: 2, height: screenHeight)
    }

    func beginSession() {
        try! captureSession.addInput(AVCaptureDeviceInput(device: captureDevice!))
        let videoOutput = AVCaptureVideoDataOutput()
        let videoQueue = DispatchQueue(label: "video")
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        captureSession.addOutput(videoOutput)
        captureSession.startRunning()
        self.setupGestureRecognizers()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        return
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
    
        let previewLayer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let ciImage = CIImage(cvPixelBuffer: previewLayer!)
        let ciFilter: CIFilter = CIFilter(name: currentFilterName)!
        
        ciFilter.setValue(ciImage, forKey: kCIInputImageKey)
        if(currentFilterName == "CIEdgeWork") {
            ciFilter.setValue(8.0, forKey: "inputRadius")
        } else if (currentFilterName == "CIEdges") {
            ciFilter.setValue(10.0, forKey: "inputIntensity")
        } else if (currentFilterName == "CIColorMonochrome") {
            ciFilter.setValue(CIColor(red: 0.75, green: 0.75, blue: 0.75), forKey: "inputColor")
            ciFilter.setValue(1.0, forKey: "inputIntensity")
        }
        
        let ciContext:CIContext = CIContext(options: nil)
        let cgimg:CGImage = ciContext.createCGImage(ciFilter.outputImage!, from:ciFilter.outputImage!.extent)!
        let image2 : UIImage = UIImage(cgImage: cgimg, scale: 1.0, orientation: UIImageOrientation.up)
        DispatchQueue.main.async {
            if(self.currentFilterName == "CIEdgeWork") {
                // Change BackgroundColor to Black
                self.leftEyeImageView.backgroundColor = UIColor.black
                self.rightEyeImageView.backgroundColor = UIColor.black
            } else {
                // Set BackgroundColor to white
                self.leftEyeImageView.backgroundColor = UIColor.white
                self.rightEyeImageView.backgroundColor = UIColor.white
            }
            self.leftEyeImageView.image = image2
            self.rightEyeImageView.image = image2
        }
    }
}


// MARK: - TouchGestures

extension ViewController {
    
    func setupGestureRecognizers() {
        let singleTapGesture: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.numberOfTouchesRequired = 1
        
        let doubleTapGesture: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        
        let longPressGesture: UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(sender:)))
        longPressGesture.numberOfTouchesRequired = 1

        singleTapGesture.require(toFail: doubleTapGesture)
        longPressGesture.require(toFail: singleTapGesture)
        
        self.touchView.addGestureRecognizer(singleTapGesture)
        self.touchView.addGestureRecognizer(doubleTapGesture)
        self.touchView.addGestureRecognizer(longPressGesture)
    }
    
    @objc func didSingleTap(_ : UITapGestureRecognizer?) {
        // シングルタップ
        changeFilter()
        playSound(name: "poyo")
    }
    
    func changeFilter() {
        // フィルターを変更する
        currentFilterIndex += 1
        let index: Int = currentFilterIndex % filterNames.count
        currentFilterName = filterNames[index]
    }
    
    @objc func didDoubleTap(_: UITapGestureRecognizer) {
        // タプルタップ
        playSound(name: "switch_vr_normal_mode")
        self.switchVrNormalMode()
    }
    
    func switchVrNormalMode() {
        if(vrMode) {
            // TODO: switch to Single Mode
            self.rightEyeImageView.alpha = 0
            self.leftEyeImageView.frame = UIScreen.main.bounds
            self.EyeSplitLine.alpha = 0
        } else {
            // TODO: switch to VR Mode
            self.leftEyeImageView.frame = CGRect(x: screenWidth/2, y: 0, width: screenWidth/2, height: screenHeight)
            self.rightEyeImageView.alpha = 1.0
            self.EyeSplitLine.alpha = 1.0
        }
        vrMode = !vrMode
    }
    
    @objc func didLongPress(sender: UILongPressGestureRecognizer) {
        if (sender.state == .began){
            playSound(name: "screenshot")
            self.screenShotMethod()
        }
    }
    
    func playSound(name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        
        do {
//            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
//            try AVAudioSession.sharedInstance().setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            guard let player = player else { return }
            if(!player.isPlaying) {
                player.play()
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1, execute: { 
                    self.player?.stop()
                })
            }
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    func showErrorWithPhotoLibraryPermission() {
        let alert = UIAlertController(title: "エラー:写真を保存できません。",
                                      message: "「設定」→「プライバシー」→「写真」→「VRカメラ」をオンにしてください",
                                      preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "閉じる", style: UIAlertActionStyle.cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func screenShotMethod() {
        let photos = PHPhotoLibrary.authorizationStatus()
        if(photos == .denied || photos == .restricted) {
            self.showErrorWithPhotoLibraryPermission()
            return
        }

        self.helpMenuButton.isHidden = true
        
        if (vrMode) {
            self.rightEyeImageView.alpha = 0
            self.leftEyeImageView.frame = UIScreen.main.bounds
            self.EyeSplitLine.alpha = 0
        }
        
        //Create the UIImage
        UIGraphicsBeginImageContext(view.frame.size)
        view.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.helpMenuButton.isHidden = false
        
        if (vrMode) {
            self.leftEyeImageView.frame = CGRect(x: screenWidth/2, y: 0, width: screenWidth/2, height: screenHeight)
            self.rightEyeImageView.alpha = 1.0
            self.EyeSplitLine.alpha = 1.0
        }
        
        //Save it to the camera roll
        UIImageWriteToSavedPhotosAlbum(image!, nil, nil, nil)
    }
}
