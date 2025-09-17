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

class LinePhoneDelegate {
    static func createDelegate(linPhone: LinPhone)->CoreDelegate{
        return CoreDelegateStub(
            onCallStateChanged: { (core, call, state, message) in
                print("Call changed: \(call), state: \(state)")
                // 可以根据 call.callId 或 call.remoteAddress 识别是哪一个 call
            },
            onMessageReceived: { (core, room, message) in
                print("Message received from \(message)")
                // 处理接收到的消息
            },
            onChatRoomStateChanged: { (core, room, state) in
                print("Chat room state changed: \(room), state: \(state)")
                // 处理聊天室状态变化
            },
            onAccountRegistrationStateChanged: { (core ,account ,state ,message) in
                print("Account \(account) registration state changed: \(state)")
                // 处理注册状态变化
            }
            
        )
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
    //need
    var chatRooms: [String: ChatRoom] = [:]
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

    init?(logLevel: LogLevel){
        do{
            LoggingService.Instance.logLevel = logLevel
            self.core = try Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil)
            self.core.videoCaptureEnabled = true
            self.core.videoDisplayEnabled = true
            self.core.videoActivationPolicy!.automaticallyAccept = true
            self.version = Core.getVersion
            try self.core.start()
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
        }
    }

   //need 
    func delete()  {
        if let account = self.defaultAccount {
            if let authinfo=account.findAuthInfo(){
                self.core.removeAuthInfo(info: authinfo)
            }
            //self.core.removeAccount(account: account)
            
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

    

    func createChatRoom(to: String) throws{
        let params = try self.core.createConferenceParams(conference: nil)
        params.chatEnabled = true
        params.chatParams?.backend = .Basic
        params.groupEnabled = false
        if params.isValid {
            let remote = try Factory.Instance.createAddress(addr: to)
            let chatRoom = try self.core.createChatRoom(params: params, participants: [remote])
            self.chatRooms[to] = chatRoom
        }
    }

    func deleteChatRoom(to: String) {
        
    }

    func sendMessage(to: String, message: String) throws {
        if let chatRoom = self.chatRooms[to] {
            let msg = try chatRoom.createMessageFromUtf8(message: message)
            msg.send()
        } else {
            try self.createChatRoom(to: to)
            if let chatRoom = self.chatRooms[to] {
                let msg = try chatRoom.createMessageFromUtf8(message: message)
                msg.send()
            }
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


    func stop(){
        core.stop()
    }

    deinit {
        self.stop()
    }

    
}





class LinPhoneViewModel: ObservableObject {
    private var linPhone: LinPhone?
    @Published var isInitialized: Bool = false
    @Published var isRegistered: Bool = false
    
    @Published var errorMessage: String?
    @Published var calls: [Call] = []
    @Published var currentCall: Call? = nil
    @Published var currentCallState: Call.State? = nil

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
                    case .End, .Released, .Error:
                        self?.calls = self?.linPhone?.calls ?? []
                        self?.currentCall = self?.linPhone?.currentCall
                    default:
                        break
                    }
                }
            },
            onAccountRegistrationStateChanged: { [weak self] (core, account, state, message) in
                DispatchQueue.main.async {
                    print("---------------------------------------------------")
                    print("Account \(account) registration state changed: \(state)")
                    self?.isRegistered = (state == .Ok)
                }
            }
        )
        linPhone.core.addDelegate(delegate: linPhone.coreDelegate)
        isInitialized = true

    }

    func login(options:LinPhone.Options) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.login(options: options)
        } catch {
            self.errorMessage = "登录失败: \(error)"
        }
    }

    func logout() {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.logout()
            try linPhone.delete()
            self.isRegistered = false
        } catch {
            self.errorMessage = "注销失败: \(error)"
        }
    }

    func call(to: String, video: Bool = false) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.call(to: to, videoEnabled: video)
        } catch {
            self.errorMessage = "呼叫失败: \(error)"
        }
    }

    func accept(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.accept(call: call)
        } catch {
            self.errorMessage = "接听失败: \(error)"
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

    func clearErrorMessage() {
        errorMessage = nil
    }

}
