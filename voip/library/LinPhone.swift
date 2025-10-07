//
//  LinPhone.swift
//  voip
//
//  Created by vc on 2025/9/12.
//

import Foundation
import Combine
import linphonesw
import UIKit
import AVFoundation
import SQLite
import AVFoundation

/*import CallKit

class CallKitManager: NSObject, CXProviderDelegate {
    
    
    static let shared = CallKitManager()
    private let provider: CXProvider
    private let callController = CXCallController()

    var onAcceptCall: ((UUID) -> Void)?
    var onEndCall: ((UUID) -> Void)?

    override init() {
        let config = CXProviderConfiguration(localizedName: "VoIP App")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.iconTemplateImageData = nil
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool = false, completion: ((Error?) -> Void)? = nil) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        provider.reportNewIncomingCall(with: uuid, update: update, completion: { error in
            completion?(error)
        })
    }

    func endCall(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        callController.request(transaction) { error in
            if let error = error {
                print("End call error: \(error)")
            }
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        
    }

    // 必须实现的代理方法
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // 通知 Linphone 接听
        onAcceptCall?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // 通知 Linphone 挂断
        onEndCall?(action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // 通知 Linphone 发起呼叫
        action.fulfill()
    }
}*/

func requestAVPermissions(completion: @escaping (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
        AVCaptureDevice.requestAccess(for: .video) { videoGranted in
            DispatchQueue.main.async {
                completion(audioGranted && videoGranted)
            }
        }
    }
}


class LinPhone{

    static let instanceIdKey = "linphone_instance_id"
    static func getOrCreateInstanceId() -> String {
        if let id = UserDefaults.standard.string(forKey: instanceIdKey) {
            return id
        } else {
            let newId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newId, forKey: instanceIdKey)
            return newId
        }
    }

    struct Options{
        var domain: String
        var username: String
        var password: String
        var transport: String
        
    }
    var core: Core!
    var coreDelegate: CoreDelegate!
    var version: String!
    var defaultAccount: Account? {
        return self.core.defaultAccount
    }
    var currentCall: Call? {
        return self.core.currentCall
    }
    var calls: [Call] {
        return self.core.calls
    }
    var callLogs: [CallLog] {
        return self.core.callLogs
    }
    var chatRooms: [ChatRoom] {
        return self.core.chatRooms
    }
    var isMicMuted: Bool {
        get {
            return self.core.micEnabled
        }
        set {
            self.core.micEnabled = newValue
        }
    }
  
    var nativeVideoWindow: UIView? {
        get{
            return self.core.nativeVideoWindow
        }
        set{
            self.core.nativeVideoWindow = newValue
        }
    }
    
    var nativePreviewWindow: UIView? {
        get{
            return self.core.nativePreviewWindow
        }
        set{
            self.core.nativePreviewWindow = newValue
        }
    }

    var supportedVideoDefinitions: [VideoDefinition] {
        return Factory.Instance.supportedVideoDefinitions
    }

    init?(logLevel: LogLevel){
        do{
            LoggingService.Instance.logLevel = logLevel
            self.core = try Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil)
            self.core.videoCaptureEnabled = true
            self.core.videoDisplayEnabled = true
            //self.core.callkitEnabled = true
            self.core.videoActivationPolicy!.automaticallyAccept = true
            self.version = Core.getVersion
            try self.core.start()
            let list=self.supportedVideoDefinitions
            for item in list{
                print(item.name)
                //720
                if(item.name?.contains("ios-medium") == true){
                    self.core.preferredVideoDefinition = item
                }
            }
        }
        catch{
            print(error)
            return nil
        }

    }


    private func getTransport(type:String)->TransportType{
        switch type.lowercased() {
        case "tcp":
            return .Tcp
        case "tls":
            return .Tls
        default:
            return .Udp
        }
    }

    func login(options: Options) throws{
        let transport = self.getTransport(type: options.transport)
        let authInfo = try Factory.Instance.createAuthInfo(username: options.username, userid: nil, passwd: options.password, ha1: nil, realm: nil, domain: options.domain)
        let accountParams = try self.core.createAccountParams()
        let identity = try Factory.Instance.createAddress(addr: "sip:\(options.username)@\(options.domain)")
        try accountParams.setIdentityaddress(newValue: identity)
        let address = try Factory.Instance.createAddress(addr: "sip:\(options.domain)")
        try address.setTransport(newValue: transport)
        try accountParams.setServeraddress(newValue: address)
        accountParams.registerEnabled = true
        accountParams.expires = 300
        let instanceId = "<urn:uuid:\(LinPhone.getOrCreateInstanceId())>"
        accountParams.contactParameters = ";+sip.instance=\"\(instanceId)\""
        let account = try self.core.createAccount(params: accountParams)
        self.core.addAuthInfo(info: authInfo)
        try self.core.addAccount(account: account)
        self.core.defaultAccount = account
    
    }


    func logout() throws {
        if let account = self.defaultAccount {
            let params = account.params
            let clonedParams = params?.clone()
            clonedParams?.registerEnabled = false
            account.params = clonedParams
            if let authinfo=account.findAuthInfo(){
                self.core.removeAuthInfo(info: authinfo)
            }
        }
    }

    func delete()  {
        if let account = self.defaultAccount {
            if let authinfo=account.findAuthInfo(){
                self.core.removeAuthInfo(info: authinfo)
            }
            self.core.removeAccount(account: account)
            
        }
    }

    func terminate(call: Call) throws {
        try call.terminate()
    }

    func accept(call: Call) throws {
        try call.accept()
    }

    func call(to: String, videoEnabled: Bool) throws {
        let address = try Factory.Instance.createAddress(addr: to)
        let params = try self.core.createCallParams(call: nil)
        params.mediaEncryption = .None
        params.videoEnabled = videoEnabled
        let _ = try self.core.inviteAddressWithParams(addr: address, params: params)
    }

    func toggleCallVideo(call: Call) throws {
        let params = try self.core.createCallParams(call: call)
        params.videoEnabled = !call.params!.videoEnabled
        try call.update(params: params)
    }


    func pause(call: Call) throws {
        try call.pause()

    }

    func resume(call: Call) throws {
        try call.resume()
    }

    func setSpeaker(call: Call, on: Bool) {
        for audioDevice in self.core.audioDevices {
            if on && audioDevice.type == AudioDevice.Kind.Speaker {
                self.currentCall?.outputAudioDevice = audioDevice
                return
            }
            else if !on && audioDevice.type == AudioDevice.Kind.Microphone {
                 self.currentCall?.outputAudioDevice = audioDevice
                 return
            }
            /*else if (audioDevice.type == AudioDevice.Kind.Bluetooth) {
                 self.core.currentCall?.outputAudioDevice = audioDevice
            }*/
        }
    }

    

    //need
    func toggleCamera() throws{
        let currentDevice = self.core.videoDevice
			
        for camera in self.core.videoDevicesList {
            if camera != currentDevice && camera != "StaticImage: Static picture" {
                try self.core.setVideodevice(newValue: camera)
                break
            }
        }

    }

    

    func createChatRoom(to: String) throws -> ChatRoom{
        let params = try self.core.createConferenceParams(conference: nil)
        params.chatEnabled = true
        params.chatParams?.backend = .Basic
        params.groupEnabled = false
        if params.isValid {
            let remote = try Factory.Instance.createAddress(addr: to)
            let chatRoom = try self.core.createChatRoom(params: params, participants: [remote])
            return chatRoom
        }
        //need
        throw NSError(domain: "LinPhone", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建聊天房间"])
    }

    func findChatRoom(to: String) throws -> ChatRoom? {
        let remoteAddress = try Factory.Instance.createAddress(addr: to)
        for room in self.chatRooms {
            if let addr = room.peerAddress, addr.asString() == remoteAddress.asString() {
                return room
            }
        }
        return nil
    }

    func deleteChatRoom(room: ChatRoom) {
        self.core.deleteChatRoom(chatRoom: room)
        
    }


    func sendMessage(to: String, message: String) throws {
        if let room = try findChatRoom(to: to) {
            let chatMessage = try room.createMessageFromUtf8(message: message)
            chatMessage.send()
        } else {
            let room = try createChatRoom(to: to)
            let chatMessage = try room.createMessageFromUtf8(message: message)
            chatMessage.send()
        }
    }

    func sendDtmf(call: Call, dtmf: CChar) throws {
        try call.sendDtmf(dtmf: dtmf)
    }

    func sendDtmfs(call: Call, dtmfs: String) throws {
        try call.sendDtmfs(dtmfs: dtmfs)
    }

    func startRecording(call: Call)  {
        call.startRecording()
    }

    func stopRecording(call: Call)  {
        call.stopRecording()
    }

    func clearCallLogs() {
        self.core.clearCallLogs()
    }


    func stop(){
        core.stop()
    }

    deinit {
        self.stop()
    }

    
}



class RingPlayer {
    static let shared = RingPlayer()
    private var player: AVAudioPlayer?

    private init() {}

    func play() {
        /*if let player = player, player.isPlaying {
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.overrideOutputAudioPort(.speaker) // 强制扬声器
            try session.setActive(true)
        } catch {
            print("设置音频会话失败: \(error)")
        }
        guard let url = Bundle.main.url(forResource: "ring", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1 // 无限循环
            player?.play()
        } catch {
            print("无法播放铃声: \(error)")
        }
        */
    }

    func stop() {
        /*player?.stop()
        player = nil*/
    }
}


class LinPhoneViewModel: ObservableObject {
    private var linPhone: LinPhone?
    public var options: LinPhone.Options?
    @Published var isInitialized: Bool = false
    @Published var isRegistered: Bool = false
    
    @Published var errorMessage: String?
    @Published var calls: [Call] = []
    @Published var callLogs: [CallLog] = []
    @Published var currentCall: Call? = nil
    @Published var currentCallState: Call.State? = nil
    @Published var registrationState: RegistrationState? = nil

    private let db = DatabaseManager.shared
    @Published var contacts: [Contact] = []
    @Published var chatRooms: [ChatRoomLocal] = []
    @Published var currentRoomId: Int64? = nil
    @Published var chatMessages: [ChatMessageLocal] = []
    var currentUUID: UUID? = nil

    var nativeVideoWindow: UIView? {
        get{
            return linPhone?.nativeVideoWindow
        }
        set{
            linPhone?.nativeVideoWindow = newValue
        }
    }
    var nativePreviewWindow: UIView? {
        get{
            return linPhone?.nativePreviewWindow
        }
        set{
            linPhone?.nativePreviewWindow = newValue
        }
    }

    init() {
        linPhone = LinPhone(logLevel: .Error)
        guard let linPhone = linPhone else {
            self.errorMessage = "初始化失败"
            return
        }
        self.callLogs = linPhone.callLogs
        
        
        print("Linphone version: \(linPhone.version ?? "unknown")")
        print("Linphone core created")
        // 监听注册和通话状态
        linPhone.coreDelegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] (core, call, state, message) in
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Call changed: \(call), state: \(state)")
                    self?.currentCallState = self?.currentCall?.state
                    switch state {
                    case .IncomingReceived, .OutgoingInit:
                        self?.calls = self?.linPhone?.calls ?? []
                        self?.currentCall = self?.linPhone?.currentCall
                        self?.currentCallState = self?.currentCall?.state
                        if state == .IncomingReceived {
                            RingPlayer.shared.play()
                            /*let uuid = UUID()
                            self?.currentUUID = uuid
                            CallKitManager.shared.reportIncomingCall(uuid: uuid, handle: call.remoteAddress?.asString() ?? "未知")*/
                        }
                    case .Connected:
                        RingPlayer.shared.stop()

                    case .End, .Released, .Error:
                        self?.calls = self?.linPhone?.calls ?? []
                        self?.currentCall = self?.linPhone?.currentCall
                        self?.callLogs = self?.linPhone?.callLogs ?? []
                        RingPlayer.shared.stop()
                        /*if let uuid = self?.currentUUID {
                            CallKitManager.shared.endCall(uuid: uuid)
                            self?.currentUUID = nil
                        }*/
                    default:
                        break
                    }
                }
            },
            onMessageReceived: { [weak self] (core, room, message) in
                
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Message received in room: \(room)")
                    print("Message content: \(message.contents)")
                    //room.markAsRead()
                    self?.handleMessage(room: room, message: message)
                }
            },
            onMessageSent: { [weak self] (core, room, message) in
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Message sent in room: \(room)")
                    print("Message content: \(message.contents)")
                    self?.handleMessage(room: room, message: message)
                }
            },
            onChatRoomStateChanged: { [weak self] (core, room, state) in
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Chat room state changed: \(room), state: \(state)")
                    let peer = room.peerAddress?.asString() ?? ""
                    // 只创建房间，不保存消息
                    _ = self?.db.findOrCreateChatRoom(peerAddress: peer)
                    self?.loadChatRooms()
                }
            },
            onAccountRegistrationStateChanged: { [weak self] (core, account, state, message) in
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Account \(account) registration state changed: \(state)")
                    self?.registrationState = state
                    self?.isRegistered = (state == .Ok)
                    if state == .Failed {
                        self?.errorMessage = "登录失败: \(message ?? "未知错误")"
                    }
                }
            }
        )
        linPhone.core.addDelegate(delegate: linPhone.coreDelegate)
        isInitialized = true
        // 初始化时加载联系人
        loadContacts()
        loadChatRooms()

    }

    func loadChatRooms() {
        chatRooms = db.fetchChatRooms()
    }

    func findChatRoom(peerAddress: String) -> ChatRoomLocal? {
        return db.findOrCreateChatRoom(peerAddress: peerAddress)
    }

    // 加载指定聊天室的消息
    func loadChatMessages(roomId: Int64) {
        guard let current = currentRoomId, current == roomId else { return }
        chatMessages = db.fetchChatMessages(roomId: roomId)
    }

    // 新增或更新消息和聊天室
    func saveMessage(peerAddress: String, text: String, time: Int64, isOutgoing: Bool) {
        // 查找或创建聊天室
        guard let room = db.findOrCreateChatRoom(peerAddress: peerAddress) else { return }
        db.addChatMessage(roomId: room.id, text: text, time: time, isOutgoing: isOutgoing)
        db.updateChatRoomLastMessage(roomId: room.id, message: text, time: time)
        loadChatRooms()
        loadChatMessages(roomId: room.id)
    }

    // 在回调里调用
    private func handleMessage(room: ChatRoom, message: ChatMessage) {
        let peer = room.peerAddress?.asString() ?? ""
        let text = message.contents.first?.utf8Text ?? ""
        let time = Int64(message.time)
        let isOutgoing = message.isOutgoing
        saveMessage(peerAddress: peer, text: text, time: time, isOutgoing: isOutgoing)
    }

    func enterChatRoom(roomId: Int64) {
        currentRoomId = roomId
        chatMessages = db.fetchChatMessages(roomId: roomId)
    }

    func exitChatRoom() {
        currentRoomId = nil
        chatMessages = []
    }

    func loadContacts() {
        contacts = db.fetchContacts()
    }

    func findContact(byId id: Int64) -> Contact? {
        return db.findContact(byId: id)
    }

    func addContact(_ contact: Contact) {
        db.addContact(contact)
        loadContacts()
    }

    func updateContact(_ contact: Contact) {
        db.updateContact(contact)
        loadContacts()
    }

    func deleteContact(id: Int64) {
        db.deleteContact(id: id)
        loadContacts()
    }

    func saveAccount(username: String, domain: String, password: String, transport: String) {
        db.saveAccount(username: username, domain: domain, password: password, transport: transport)
    }

    func loadAccount() -> LocalAccount? {
        db.loadAccount()
    }

    func clearAccount() {
        db.clearAccount()
    }

    func login(options:LinPhone.Options) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.login(options: options)
            self.options = options
        } catch {
            self.errorMessage = "登录失败: \(error)"
        }
    }

    func logout() {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.logout()
            self.isRegistered = false
        } catch {
            self.errorMessage = "注销失败: \(error)"
        }
    }

    func call(to: String, video: Bool = false) {
        requestAVPermissions { granted in
            if granted {
                guard let linPhone = self.linPhone else { return }
                do {
                    try linPhone.call(to: to, videoEnabled: video)
                } catch {
                    self.errorMessage = "呼叫失败: \(error)"
                }
            } else {
                self.errorMessage = "需要麦克风和摄像头权限"
            }
        }
        
    }

    func toggleCallVideo(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.toggleCallVideo(call: call)
        } catch {
            self.errorMessage = "切换视频失败: \(error)"
        }
    }

    func accept(call: Call) {
        requestAVPermissions { granted in
            if granted {
                guard let linPhone = self.linPhone else { return }
                do {
                    try linPhone.accept(call: call)
                } catch {
                    self.errorMessage = "接听失败: \(error)"
                }
            } else {
                self.errorMessage = "需要麦克风和摄像头权限"
            }
        }
    }

    func hangup(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.terminate(call: call)
        } catch {
            self.errorMessage = "挂断失败: \(error)"
        }
    }

    func pause(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.pause(call: call)
        } catch {
            self.errorMessage = "保持失败: \(error)"
        }
    }

    func resume(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.resume(call: call)
        } catch {
            self.errorMessage = "恢复失败: \(error)"
        }
    }


    func setSpeaker(on: Bool) {
        if let call = self.currentCall {
            linPhone?.setSpeaker(call: call, on: on)
        }
    }

    func setMuted(muted: Bool) {
        guard let linPhone = linPhone else { return }
        linPhone.isMicMuted = muted
    }

    func toggleCamera() {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.toggleCamera()
        } catch {
            self.errorMessage = "切换摄像头失败: \(error)"
        }
    }

    func startRecording() {
        guard let linPhone = linPhone, let call = self.currentCall else { return }
        linPhone.startRecording(call: call)
    }

    func stopRecording() {
        guard let linPhone = linPhone, let call = self.currentCall else { return }
        linPhone.stopRecording(call: call)
    }

    func sendMessage(to: String, message: String) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.sendMessage(to: to, message: message)
        } catch {
            self.errorMessage = "发送消息失败: \(error)"
        }
    }

    func sendDtmf(dtmf: CChar) {
        guard let linPhone = linPhone, let call = self.currentCall else { return }
        do {
            try linPhone.sendDtmf(call: call, dtmf: dtmf)
        } catch {
            self.errorMessage = "发送DTMF失败: \(error)"
        }
    }

    func clearCallLogs() {
        guard let linPhone = linPhone else { return }
        linPhone.clearCallLogs()
        self.callLogs = linPhone.callLogs
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

}
