//
//  LinPhone.swift
//  voip
//
//  Created by vc on 2025/9/12.
//

import Foundation
import Combine
import linphonesw

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
    var chatRooms: [String: ChatRoom] = [:]
    var isMicMuted: Bool {
        get {
            return self.core.micEnabled
        }
        set {
            self.core.micEnabled = newValue
        }
    }
    var currentSpeakerMode: AudioDevice.Kind? {
        return core.currentCall?.outputAudioDevice?.type
    }

    init?(logLevel: LogLevel){
        do{
            LoggingService.Instance.logLevel = logLevel
            self.core = try Factory.Instance.createCore(configPath: "", factoryConfigPath: "", systemContext: nil)
            
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
    func delete() throws {
        if let account = self.defaultAccount {
            self.core.removeAccount(account: account)
            //self.core.clearAccounts()
            self.core.clearAllAuthInfo()
        }
    }

    func terminate(call: Call) throws {
        try call.terminate()
    }

    func accept(call: Call) throws {
        try call.accept()
    }

    func call(to: String) throws {
        let address = try Factory.Instance.createAddress(addr: to)
        let params = try self.core.createCallParams(call: nil)
        params.mediaEncryption = .None
        let _ = try self.core.inviteAddressWithParams(addr: address, params: params)
    }


    func pauseOrResume(call: Call) throws {
        if (call.state != Call.State.Paused && call.state != Call.State.Pausing) {
            // If our call isn't paused, let's pause it
            try call.pause()
        } else if (call.state != Call.State.Resuming) {
            // Otherwise let's resume it
            try call.resume()
        }

    }



    func toggleSpeaker(){
        guard let mode = self.currentSpeakerMode else {
            return
        }
        let speakerEnabled = mode != .Speaker
        for audioDevice in self.core.audioDevices {
            if speakerEnabled && audioDevice.type == AudioDevice.Kind.Microphone {
                self.currentCall?.outputAudioDevice = audioDevice
                return
            }
            else if !speakerEnabled && audioDevice.type == AudioDevice.Kind.Speaker {
                 self.currentCall?.outputAudioDevice = audioDevice
                 return
            }
            /*else if (audioDevice.type == AudioDevice.Kind.Bluetooth) {
                 self.core.currentCall?.outputAudioDevice = audioDevice
            }*/
        }
    }

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


    func stop() throws {
        core.stop()
    }

    
}





class LinPhoneViewModel: ObservableObject {
    @Published var isInitialized: Bool = false
    @Published var isRegistered: Bool = false
    @Published var speakerOn: Bool = false
    @Published var isMicMuted: Bool = false
    private var linPhone: LinPhone?
    @Published var errorMessage: String?

    @Published var currentCall: Call? = nil
    @Published var currentCallState: Call.State? = nil

    init() {
        linPhone = LinPhone(logLevel: .Error)
        guard let linPhone = linPhone else {
            self.errorMessage = "LinPhone 初始化失败"
            return
        }
        
        // 监听注册和通话状态
        linPhone.coreDelegate = CoreDelegateStub(
            onCallStateChanged: { [weak self] (core, call, state, message) in
                DispatchQueue.main.async {
                    print("Call changed: \(call), state: \(state)")
                    
                    self?.currentCall = call
                }
            },
            onAccountRegistrationStateChanged: { [weak self] (core, account, state, message) in
                DispatchQueue.main.async {
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
            self.isRegistered = false
        } catch {
            self.errorMessage = "注销失败: \(error)"
        }
    }

    func call(to: String) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.call(to: to)
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

    func pauseOrResume(call: Call) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.pauseOrResume(call: call)
        } catch {
            self.errorMessage = "暂停/恢复失败: \(error)"
        }
    }

    func toggleMic() {
        guard let linPhone = linPhone else { return }
        linPhone.isMicMuted = !linPhone.isMicMuted
        self.isMicMuted = linPhone.isMicMuted
    }

    func toggleSpeaker() {
        guard let linPhone = linPhone else { return }
        linPhone.toggleSpeaker()
        self.speakerOn.toggle()
    }

    func sendMessage(to: String, message: String) {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.sendMessage(to: to, message: message)
        } catch {
            self.errorMessage = "发送消息失败: \(error)"
        }
    }

    func stop() {
        guard let linPhone = linPhone else { return }
        do {
            try linPhone.stop()
        } catch {
            self.errorMessage = "停止失败: \(error)"
        }
    }
}
