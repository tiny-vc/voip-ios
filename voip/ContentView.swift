//
//  ContentView.swift
//  voip
//
//  Created by vc on 2025/9/8.
//

import SwiftUI
import linphonesw

struct ContentView: View {
    @StateObject var vm = LinPhoneViewModel()
    @State private var showError = false

    var body: some View {
        Group {
            if !vm.isRegistered {
                // 登录界面
                LoginView(vm: vm)
            } else {
                // 主界面
                MainTabView(vm: vm)
            }
        }
        .overlay(
            Group {
                if vm.calls.count > 0 {
                    CallStatusOverlay( vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }, alignment: .top
        )
        .overlay(
            Group {
                if let error = vm.errorMessage, showError {
                    ToastView(message: error)
                        .transition(.opacity)
                        .zIndex(200)
                }
            }
        )
        .onChange(of: vm.errorMessage) { newValue in
            if newValue != nil {
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        showError = false
                    }
                    // 延迟一点再清理，避免动画冲突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        vm.clearErrorMessage()
                    }
                }
            }
        }
    }
}

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.body)
            .foregroundColor(.black) // 文字改为黑色
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.95)) // 背景改为高亮白色
                    .shadow(color: .black.opacity(0.3), radius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}


struct LoginView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var domain = "180.97.215.207:5555"
    @State private var username = "jack"
    @State private var password = "1"
    @State private var transport = "udp"

    let transports = [
        ("UDP", "udp"),
        ("TCP", "tcp"),
        ("TLS", "tls")
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "phone.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            Text("SIP 登录")
                .font(.largeTitle)
                .fontWeight(.bold)
            VStack(spacing: 20) {
                TextField("服务器", text: $domain)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                TextField("用户名", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                SecureField("密码", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Text("传输方式")
                        .foregroundColor(.gray)
                    Spacer()
                    Picker("传输方式", selection: $transport) {
                        ForEach(transports, id: \.1) { item in
                            Text(item.0).tag(item.1)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)
                }
            }
            .padding(.horizontal, 32)
            Button(action: {
                let options = LinPhone.Options(
                    domain: domain,
                    username: username,
                    password: password,
                    transport: transport
                )
                vm.login(options: options)
            }) {
                if vm.registrationState == .Progress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text("登录")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .frame(maxWidth: 240)
            .background(vm.isInitialized ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(!vm.isInitialized || vm.registrationState == .Progress)
            Spacer()
        }
        .padding(.horizontal, 0)
        .background(Color(.systemBackground))
        // 不需要阴影和圆角
        .ignoresSafeArea()
    }
}


struct CallStatusOverlay: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var isSpeakerOn = false
    @State private var isMuted = false
    @State private var isExpanded = false
    @State private var showDtmfPad = false
    @State private var isRecording = false

    @State private var timer: Timer? = nil
    @State private var duration: Int = 0
    @State private var quality: Float = 0

    var call: Call? { vm.currentCall }
    var callState: Call.State? { vm.currentCallState }
    var isVideo: Bool { call?.currentParams?.videoEnabled ?? false }
    var isActive: Bool { callState == .Connected || callState == .StreamsRunning }
    var canAccept: Bool { call?.dir == .Incoming && callState == .IncomingReceived }
    var canHangup: Bool {
        guard let state = callState else { return false }
        return state != .End && state != .Released && state != .Error && state != .Idle
    }

    var body: some View {
        ZStack {
            // 视频通话时，对方画面全屏底层
            if isVideo, isActive {
                LinphoneVideoViewHolder { view in
                    vm.nativeVideoWindow = view
                }
                .edgesIgnoringSafeArea(.all)
                .background(Color.black)
            } else {
                Color(.systemBackground)
                    .edgesIgnoringSafeArea(.all)
            }
            // 本地预览画面，右上角悬浮
            if isVideo, isActive {
                VStack {
                    HStack {
                        Spacer()
                        LinphoneVideoViewHolder { view in
                            vm.nativePreviewWindow = view
                        }
                        .frame(width: 120, height: 160)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.5), lineWidth: 1))
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            VStack {
                Spacer()
                // 通话信息
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                        Text( call?.remoteAddress?.asString() ?? "未知")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .padding(.bottom, 6)
                    // 状态显示
                    if isActive {
                        HStack(spacing: 12) {
                            Label("通话中", systemImage: "phone.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.7))
                                .cornerRadius(10)
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .foregroundColor(.yellow)
                                Text("质量: \(quality)")
                            }
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.15))
                            .cornerRadius(10)
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .foregroundColor(.white)
                                Text("时长: \(duration)秒")
                            }
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.25))
                            .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    } else if canAccept {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.green)
                            Text("来电")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    } else if call?.dir == .Outgoing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                            Text("正在呼叫...")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer()
                // 主操作按钮（加大并下移）
                if canAccept {
                    HStack(spacing: 48) {
                        Button(action: {
                            vm.accept(call: call!)
                        }) {
                            VStack {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.green)
                                    .clipShape(Circle())
                                Text("接听")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        Button(action: {
                            vm.hangup(call: call!)
                        }) {
                            VStack {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                Text("拒绝")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                } else if canHangup {
                    Button(action: {
                        vm.hangup(call: call!)
                    }) {
                        VStack {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.red)
                                .clipShape(Circle())
                            Text("挂断")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 32)
                }
                if isActive {
                    // 功能按钮区（底部）
                    HStack(spacing: 28) {
                        // 免提
                        Button(action: {
                            isSpeakerOn.toggle()
                            vm.setSpeaker(on: isSpeakerOn)
                        }) {
                            Image(systemName: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.blue.opacity(0.7))
                                .clipShape(Circle())
                        }
                        // 静音
                        Button(action: {
                            isMuted.toggle()
                            vm.setMuted(muted: isMuted)
                        }) {
                            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.orange.opacity(0.7))
                                .clipShape(Circle())
                        }
                        // 视频
                        Button(action: {
                            if let call = call {
                                //vm.call(to: call.remoteAddress?.asString() ?? "", video: true)
                            }
                        }) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.purple.opacity(0.7))
                                .clipShape(Circle())
                        }
                        // 更多
                        Button(action: {
                            withAnimation { isExpanded.toggle() }
                        }) {
                            Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.gray.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, isExpanded ? 0 : 32)
                    // 展开后更多功能
                    if isExpanded {
                        HStack(spacing: 28) {
                            // 录音
                            Button(action: {
                                /*isRecording.toggle()
                                if isRecording {
                                    vm.startRecording()
                                } else {
                                    vm.stopRecording()
                                }*/
                            }) {
                                Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.red.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            // 切换摄像头
                            Button(action: {
                                vm.toggleCamera()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.blue.opacity(0.7))
                                    .clipShape(Circle())
                            }
                            // DTMF 键盘
                            Button(action: {
                                showDtmfPad = true
                            }) {
                                Image(systemName: "circle.grid.3x3.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.green.opacity(0.7))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        // DTMF 键盘弹窗
        .sheet(isPresented: $showDtmfPad) {
            DtmfPadView { dtmf in
                vm.sendDtmf(dtmf: dtmf)
            }
        }
        .onAppear {
            if isActive {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: isActive) { active in
            if active {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            duration = call?.duration ?? 0
            quality = call?.currentQuality ?? 0
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// DTMF 拨号盘
struct DtmfPadView: View {
    let onSend: (CChar) -> Void
    @Environment(\.presentationMode) var presentationMode
    let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]
    var body: some View {
        VStack(spacing: 18) {
            Text("发送 DTMF")
                .font(.headline)
                .padding(.top, 16)
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            if let char = key.utf8.first {
                                onSend(CChar(char))
                            }
                        }) {
                            Text(key)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .frame(width: 72, height: 72)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.primary)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            Button("关闭") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top, 24)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}


struct MainTabView: View {
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        TabView {
            CallsView(vm: vm)
                .tabItem {
                    Label("通话", systemImage: "phone")
                }
            DialPadTabView(vm: vm)
                .tabItem {
                    Label("拨号", systemImage: "circle.grid.3x3.fill")
                }
            ContactsView(vm: vm)
                .tabItem {
                    Label("联系人", systemImage: "person.2")
                }
            ChatView(vm: vm)
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right")
                }
            SettingsView(vm: vm)
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

struct DialPadTabView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var dialNumber: String = ""
    @State private var showTextInput = false
    @State private var textInput = ""

    let dialPadRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                // 显示输入的号码
                Text(dialNumber)
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 32)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Spacer()
                // 拨号键盘
                VStack(spacing: 18) {
                    ForEach(dialPadRows, id: \.self) { row in
                        HStack(spacing: 28) {
                            ForEach(row, id: \.self) { digit in
                                Button(action: {
                                    dialNumber.append(digit)
                                }) {
                                    Text(digit)
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .frame(width: 72, height: 72)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.primary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    // 操作按钮行
                    HStack(spacing: 40) {
                        // 删除
                        Button(action: {
                            if !dialNumber.isEmpty {
                                dialNumber.removeLast()
                            }
                        }) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 28, weight: .regular))
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.gray)
                                .clipShape(Circle())
                        }
                        // 文本输入
                        Button(action: {
                            showTextInput = true
                        }) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 24, weight: .regular))
                                .frame(width: 60, height: 60)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Circle())
                        }
                        // 拨号
                        Button(action: {
                            vm.call(to: "sip:\(dialNumber)@\(vm.options!.domain)")
                            dialNumber = ""
                        }) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 32, weight: .bold))
                                .frame(width: 60, height: 60)
                                .background(dialNumber.isEmpty ? Color.gray.opacity(0.15) : Color.green)
                                .foregroundColor(dialNumber.isEmpty ? .gray : .white)
                                .clipShape(Circle())
                        }
                        .disabled(dialNumber.isEmpty)
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
                Spacer()
            }
            .padding(.top, 24)
            .background(Color(.systemBackground))
            .navigationTitle("拨号键盘")
            // 弹出文本输入框
            .alert("输入SIP地址或用户名", isPresented: $showTextInput) {
                TextField("如 jack 或 sip:jack@domain", text: $textInput)
                Button("呼叫") {
                    var target = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !target.isEmpty {
                        // 如果没有 @，自动补全 domain
                        if !target.contains("@"), let domain = vm.options?.domain {
                            target = "sip:\(target)@\(domain)"
                        }
                        vm.call(to: target)
                    }
                    textInput = ""
                }
                Button("取消", role: .cancel) {
                    textInput = ""
                }
            }
        }
    }
}

enum ContactStatus {
    case online
    case offline
    case unknown
}

struct Contact: Identifiable, Hashable {
    let id: UUID = UUID()           // 唯一标识
    let username: String            // 用户名（如 jack）
    let displayName: String         // 显示名（如 张三）
    let sipAddress: String
    let phoneNumber: String
    var status: ContactStatus = .unknown
   
}


struct ContactsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var contacts: [Contact] = [
        Contact(
            username: "vc",
            displayName: "VC",
            sipAddress: "sip:vc@180.97.215.207",
            phoneNumber: "13800000001",
            status: .online
        ),
        Contact(
            username: "rose",
            displayName: "Rose",
            sipAddress: "sip:rose@180.97.215.208",
            phoneNumber: "13800000002",
            status: .unknown
        ),
        Contact(
            username: "john",
            displayName: "John",
            sipAddress: "sip:john@180.97.215.209",
            phoneNumber: "13800000003",
            status: .offline
        )
    ]
    @State private var showAddContact = false

    var body: some View {
        NavigationView {
            VStack {
                List(contacts, id: \.id) { contact in
                    NavigationLink(destination: ContactDetailView(contact: contact, vm: vm)) {
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(contact.displayName.prefix(1)))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    )
                                // 在线状态指示
                                Circle()
                                    .fill(contact.status == .online ? Color.green :
                                        (contact.status == .offline ? Color.gray : Color.gray.opacity(0.4)))
                                    .frame(width: 10, height: 10)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                                    .offset(x: 10, y: 10)
                            }
                            VStack(alignment: .leading) {
                                Text(contact.displayName)
                                    .font(.headline)
                                Text(contact.username)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            // 语音电话按钮
                            Button(action: {
                                vm.call(to: contact.sipAddress)
                            }) {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.green)
                                    .padding(8)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            // 视频电话按钮
                            Button(action: {
                                vm.call(to: contact.sipAddress,video: true)
                            }) {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.blue)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
                .listRowSeparator(.hidden)
                Spacer()
            }
            .navigationTitle("联系人")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddContact = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("添加联系人")
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView { newContact in
                    contacts.append(newContact)
                    showAddContact = false
                } onCancel: {
                    showAddContact = false
                }
            }
        }
    }
}

struct ContactDetailView: View {
    let contact: Contact
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            // 头像和昵称
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .overlay(
                        Text(String(contact.displayName.prefix(1)))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.blue)
                    )
                Circle()
                    .fill(contact.status == .online ? Color.green :
                          (contact.status == .offline ? Color.gray : Color.gray.opacity(0.4)))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: 8, y: 8)
            }
            Text(contact.displayName)
                .font(.title)
                .fontWeight(.bold)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.blue)
                    Text("用户名：\(contact.username)")
                }
                HStack {
                    Image(systemName: "envelope")
                        .foregroundColor(.purple)
                    Text("SIP地址：\(contact.sipAddress)")
                }
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.orange)
                    Text("手机号：\(contact.phoneNumber)")
                }
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(contact.status == .online ? .green : .gray)
                        .font(.system(size: 12))
                    Text(contact.status == .online ? "在线" : (contact.status == .offline ? "离线" : "未知"))
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }
            .font(.body)
            .padding(.horizontal, 24)

            Spacer()
            // 操作按钮
            HStack(spacing: 32) {
                Button(action: { vm.call(to: contact.sipAddress) }) {
                    VStack {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .clipShape(Circle())
                        Text("语音通话")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Button(action: { vm.call(to: contact.sipAddress, video: true) }) {
                    VStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                        Text("视频通话")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                Button(action: { vm.sendMessage(to: contact.sipAddress, message: "Hello") }) {
                    VStack {
                        Image(systemName: "message.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.orange)
                            .clipShape(Circle())
                        Text("发信息")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("联系人详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct AddContactView: View {
    @State private var username = ""
    @State private var displayName = ""
    @State private var sipAddress = ""
    @State private var phoneNumber = ""
    var onAdd: (Contact) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Image(systemName: "person.text.rectangle")
                            .foregroundColor(.green)
                        TextField("昵称", text: $displayName)
                    }
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.purple)
                        TextField("SIP地址", text: $sipAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                    }
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.orange)
                        TextField("手机号", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                }
            }
            .navigationTitle("添加联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let contact = Contact(
                            username: username,
                            displayName: displayName.isEmpty ? username : displayName,
                            sipAddress: sipAddress,
                            phoneNumber: phoneNumber
                        )
                        onAdd(contact)
                    }
                    .disabled(username.isEmpty || sipAddress.isEmpty)
                }
            }
        }
    }
}

func formatTimestamp(_ timestamp: time_t) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

func statusText(for status: Call.Status) -> String {
    switch status {
    case .Success:
        return "已接通"
    case .Aborted:
        return "已取消"
    case .AcceptedElsewhere:
        return "其他设备已接听"
    case .Declined:
        return "已拒绝"
    case .DeclinedElsewhere:
        return "其他设备已拒绝"
    case .EarlyAborted:
        return "未建立即取消"
    case .Missed:
        return "未接听"
    default:
        return "未知"
    }
}


struct CallsView: View {
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.callLogs, id: \.callId) { log in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(log.dir == .Incoming ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: log.dir == .Incoming ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                                    .foregroundColor(log.dir == .Incoming ? .green : .blue)
                                    .font(.system(size: 22, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(log.dir == .Incoming ? "呼入" : "呼出")
                                        .font(.headline)
                                    if log.videoEnabled {
                                        Image(systemName: "video.fill")
                                            .foregroundColor(.purple)
                                    }
                                    Spacer()
                                    Text(statusText(for: log.status))
                                        .font(.caption)
                                        .foregroundColor(log.status == .Success ? .green : .red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill((log.status == .Success ? Color.green : Color.red).opacity(0.12))
                                        )
                                }
                                Text("本地: \(log.localAddress?.asString() ?? "-")")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Text("对方: \(log.remoteAddress?.asString() ?? "-")")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                HStack(spacing: 16) {
                                    Text("开始: \(formatTimestamp(log.startDate))")
                                    Text("时长: \(log.duration)秒")
                                    Text("质量: \(log.quality)")
                                }
                                .font(.caption2)
                                .foregroundColor(.gray)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.top, 12)
            }
            .background(Color(.systemBackground))
            .navigationTitle("通话记录")
        }
    }
}

struct ChatView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
            }
            .navigationTitle("聊天")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("当前账号")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text("未登录")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    Divider()
                    Button(action: {
                        vm.logout()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("注销")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .shadow(radius: 4)
                )
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("设置")
        }
    }
}



