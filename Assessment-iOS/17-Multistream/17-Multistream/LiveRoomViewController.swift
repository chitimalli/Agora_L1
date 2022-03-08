//
//  LiveRoomViewController.swift
//  LargeGroupVideoChat
//
//  Created by ZhangJi on 30/09/2017.
//  Copyright © 2017 Agora. All rights reserved.
//

import UIKit
import AgoraRtcKit
import AGEVideoLayout

protocol LiveRoomVCDelegate: NSObjectProtocol {
    func liveVCNeedClose(_ liveVC: LiveRoomViewController)
}

class LiveRoomViewController: UIViewController {
    
    @IBOutlet weak var videoContainer: AGEVideoContainer!
    @IBOutlet weak var audioMuteButton: UIButton!
    
    private lazy var fullLayout: AGEVideoLayout = AGEVideoLayout(level: 0)
                                                    .startPoint(x: 0, y: 0)
                                                    .size(.scale(CGSize(width: 1, height: 1)))
    
    private lazy var scrollLayout: AGEVideoLayout = {
        var topSafeArea: CGFloat = 46
        
        let screenWidth = UIScreen.main.bounds.width - 20
        
        return AGEVideoLayout(level: 1)
                .startPoint(x: 10, y: topSafeArea)
                .size(.constant(CGSize(width: screenWidth, height: 100)))
                .itemSize(.constant(CGSize(width: 100, height: 100)))
                .scrollType(.scroll(.horizontal))
                .interitemSpacing(10)
    }()
    
    // MARK: - AgoraRtcEngineKit
    private var rtcEngine: AgoraRtcEngineKit!
    
    private var isMuted = false {
        didSet {
            rtcEngine?.muteLocalAudioStream(isMuted)
            audioMuteButton?.setImage(isMuted ? #imageLiteral(resourceName: "btn_mute_cancel.pdf") : #imageLiteral(resourceName: "btn_mute.pdf"), for: .normal)
        }
    }
    
    private var videoSessions = [VideoSessionView]() {
        didSet {
            
            guard videoContainer != nil,
                videoSessions.count > 0 else {
                return
            }
            
            setupVideoLayout(newCount: videoSessions.count,
                             oldCount: oldValue.count)
        }
    }
    
    private let currentUid: UInt = 0
    
    weak var delegate: LiveRoomVCDelegate?
    
    var roomName: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.automaticallyAdjustsScrollViewInsets = false
        
        
        //Amar: Enable Agora Logs
        
        
        videoContainer.delegate = self
        videoContainer.dataSource = self
        joinChannel()
    }
    
    // MARK: - user action
    @IBAction func doSwitchCameraPressed(_ sender: UIButton) {
        rtcEngine?.switchCamera()
    }
    
    @IBAction func doMutePressed(_ sender: UIButton) {
        isMuted = !isMuted
    }
    
    @IBAction func doLeavePressed(_ sender: UIButton) {
        leaveChannel()
    }
}

private extension LiveRoomViewController {
    
    func getLogConfigs() -> AgoraRtcEngineConfig{

        let logConfig = AgoraLogConfig()
        // Set the log filter to ERROR
        logConfig.level = AgoraLogLevel.error
        // Set the log file path
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyyHHmm"
        let folder = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        //let folder = NSSearchPathForDirectoriesInDomains(.documentDirectoryuserDomainMask, true)
        logConfig.filePath = "\(folder[0])/logs/\(formatter.string(from: Date())).log"
        // Set the log file size to 2 MB
        logConfig.fileSize = 2 * 1024

        let config = AgoraRtcEngineConfig()
        config.appId = KeyCenter.AppId
        config.areaCode = AgoraAreaCode.AS.rawValue
        config.logConfig = logConfig
        return config
    }
    
    func joinChannel() {
        // init Agora Video Engine with AgoraChannelProfileLiveBroadcasting, and set self as broadcaster
        //AMAR: Added and enabled LogConfigs
        
        rtcEngine = AgoraRtcEngineKit.sharedEngine(with: getLogConfigs(), delegate: self)
        //rtcEngine = AgoraRtcEngineKit.sharedEngine(withAppId: KeyCenter.AppId, delegate: self)
        rtcEngine.setChannelProfile(.liveBroadcasting)
        rtcEngine.setClientRole(.broadcaster)
        rtcEngine.enableVideo()
        
        // setup video configuration with AgoraVideoBitrateCompatible
        let videoConfiguration =
            AgoraVideoEncoderConfiguration(size: AgoraVideoDimension640x360,
                                           frameRate: .fps15,
                                           bitrate: AgoraVideoBitrateCompatible,
                                           orientationMode: .adaptative)
        rtcEngine.setVideoEncoderConfiguration(videoConfiguration)
        
        rtcEngine.startPreview()
        addLocalSessionView()
        
        // start lastmile test together with join to indicate user network status
        let config = AgoraLastmileProbeConfig()
        config.probeDownlink = true
        config.expectedDownlinkBitrate = 5000
        rtcEngine.startLastmileProbeTest(config)
        
        //AMAR: Get the Token from the Token server, that matches with the room name(channleID), before joing the Channle
        //For this test we are getting then token from the Test Console App. This needs to come from the Application Server managed by the Application backend
        rtcEngine.joinChannel(byToken: KeyCenter.Token, channelId: roomName, info: nil, uid: currentUid, joinSuccess: nil)
        
        //AMAR:As per the requirement we do not want to compramise on Audio quality,
        // hence enabling DualStream, and setting RemoteDefault Vodeo to Low and
        // Remote Subscribed fallback to Audion, incase the N/W condition becomes really bad
        rtcEngine.enableDualStreamMode(true)
        rtcEngine.setRemoteDefaultVideoStreamType(AgoraVideoStreamType.low)
        
        rtcEngine.setLocalPublishFallbackOption(AgoraStreamFallbackOptions.audioOnly)
        rtcEngine.setRemoteSubscribeFallbackOption(AgoraStreamFallbackOptions.audioOnly)
        
    }
    
    func leaveChannel() {
        setIdleTimerActive(true)
        
        rtcEngine.setupLocalVideo(nil)
        rtcEngine.leaveChannel(nil)
        rtcEngine.stopPreview()
        
        for session in videoSessions {
            session.removeFromSuperview()
        }
        videoSessions.removeAll()
        
        delegate?.liveVCNeedClose(self)
    }
}

private extension LiveRoomViewController {
    func setupVideoLayout(newCount: Int, oldCount: Int) {
        if newCount == 1, oldCount == 0 {
            videoContainer.setLayouts([fullLayout])
        } else if newCount == 1, oldCount > 1 {
            videoContainer.removeLayout(level: scrollLayout.level)
            
        // if video session count great than 2, add scroll layout to present new video stream
        } else if newCount > 1, oldCount == 1 {
            videoContainer.setLayouts([fullLayout, scrollLayout], animated: true)
        }
        
        videoContainer.reload(level: 0, animated: true)
        videoContainer.reload(level: 1, animated: true)
    }
    
    func addLocalSessionView() {
        let localSession = videoSessionView(ofUid: 0)
        localSession.isNoNeedSubViews = true
        rtcEngine.setupLocalVideo(localSession.canvas)
    }
    
    func fetchSessionView(ofUid uid: UInt) -> VideoSessionView? {
        for session in videoSessions {
            if session.uid == uid {
                return session
            }
        }
        return nil
    }
    
    func videoSessionView(ofUid uid: UInt) -> VideoSessionView {
        if let fetchedSession = fetchSessionView(ofUid: uid) {
            return fetchedSession
        } else {
            let newSession = VideoSessionView.newInstance(uid: uid)
            newSession.delegate = self
            videoSessions.append(newSession)
            return newSession
        }
    }
    
    func onUpdateUserCounts() {
        if(videoSessions.count > 1) {
            // use live profile for more users
            rtcEngine.setChannelProfile(.liveBroadcasting)
            rtcEngine.setClientRole(.broadcaster)
        } else {
            // use communication profile for 1 to 1
            rtcEngine.setChannelProfile(.communication)
        }
    }
}

//MARK: - AgoraRtcEngineDelegate
extension LiveRoomViewController: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid: UInt, size: CGSize, elapsed: Int) {
        let remoteSession = videoSessionView(ofUid: uid)
        rtcEngine.setupRemoteVideo(remoteSession.canvas)
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        var indexToDelete: Int?
        for (index, session) in videoSessions.enumerated() {
            if session.uid == uid {
                indexToDelete = index
            }
        }
        
        if let indexToDelete = indexToDelete {
            let deletedSession = videoSessions.remove(at: indexToDelete)
            deletedSession.removeFromSuperview()
            deletedSession.canvas.view = nil
        }
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        print("didOccurWarning: \(warningCode.rawValue)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print("didOccurError: \(errorCode.rawValue)")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, lastmileProbeTest result: AgoraLastmileProbeResult) {
        
    }
}

extension LiveRoomViewController: VideoSessionViewDelegate {
    func videoSessionView(_ view: VideoSessionView, shouldMute: Bool) {
        let uid: UInt = view.uid
        rtcEngine.muteRemoteAudioStream(uid, mute: shouldMute)
        rtcEngine.muteRemoteVideoStream(uid, mute: shouldMute)
    }
}

extension LiveRoomViewController: AGEVideoContainerDataSource {
    func container(_ container: AGEVideoContainer, numberOfItemsIn level: Int) -> Int {
        if level == fullLayout.level {
            return 1
        } else {
            return videoSessions.count - 1
        }
    }
    
    func container(_ container: AGEVideoContainer, viewForItemAt index: AGEIndex) -> AGEView {
        if index.level == fullLayout.level {
            return videoSessions[0]
        } else {
            return videoSessions[index.item + 1]
        }
    }
}

extension LiveRoomViewController: AGEVideoContainerDelegate {
    func container(_ container: AGEVideoContainer, didSelected itemView: AGEView, index: AGEIndex) {
        guard index.level == scrollLayout.level else {
            return
        }
        
        let first = 0
        let swap = index.item + 1
        
        let firstSession = videoSessions[first]
        let swapSession = videoSessions[swap]
        
        videoSessions.swapAt(first, swap)
        
        container.reload(level: fullLayout.level, animated: true)
        container.reload(level: scrollLayout.level, animated: true)
        
        if currentUid != swapSession.uid {
            rtcEngine.setRemoteVideoStream(swapSession.uid, type: .high)
        }
        
        if currentUid != firstSession.uid {
            rtcEngine.setRemoteVideoStream(firstSession.uid, type: .low)
        }
    }
    
    func container(_ container: AGEVideoContainer, itemDidHidden index: AGEIndex) {
        guard index.level == scrollLayout.level else {
            return
        }
        
        let session = videoSessions[index.item + 1]
        session.isMute = true
    }
    
    func container(_ container: AGEVideoContainer, itemWillDisplay index: AGEIndex) {
        guard index.level == scrollLayout.level else {
            return
        }
        
        let session = videoSessions[index.item + 1]
        session.isMute = false
    }
}

extension LiveRoomViewController {
    func setIdleTimerActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = !active
    }
}
