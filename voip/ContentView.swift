//
//  ContentView.swift
//  voip
//
//  Created by vc on 2025/9/8.
//

import SwiftUI
import linphonesw
import UIKit

let apiUrl = "http://180.97.215.207:3001"

func updateIdleTimer(for isActive: Bool) {
    UIApplication.shared.isIdleTimerDisabled = isActive
}

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
    @State private var domain = ""
    @State private var username = ""
    @State private var password = ""
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
                // 登录后保存账号
                vm.saveAccount(username: username, domain: domain, password: password, transport: transport)
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
        .ignoresSafeArea()
        .onAppear {
            // 自动填充上次账号
            if let account = vm.loadAccount() {
                domain = account.domain
                username = account.username
                password = account.password
                transport = account.transport
            }
        }
    }
}


struct CallStatusOverlay: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var isSpeakerOn = false
    @State private var isMuted = false
    @State private var showDtmfPad = false
    @State private var showStats = false
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

    var stats: CallStats? {
        return call?.audioStats
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

            // 顶部状态栏
            VStack(alignment: .center, spacing: 8) {
                HStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                    Text(call?.remoteAddress?.asString() ?? "未知")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                // 状态显示
                if isActive {
                    HStack(spacing: 16) {
                        Spacer()
                        Label("通话中", systemImage: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .foregroundColor(.yellow)
                            Text("质量: \(quality)")
                        }
                        .font(.caption)
                        .foregroundColor(.yellow)
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.gray)
                            Text("时长: \(duration)秒")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                        Spacer()
                    }
                } else if canAccept {
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "phone.fill")
                            .foregroundColor(.green)
                        Text("来电")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }
                } else if call?.dir == .Outgoing {
                    HStack(spacing: 8) {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                            .scaleEffect(0.7)
                        Text("正在呼叫...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .top)
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
                        .padding(.top, 44)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // 底部按钮区
            VStack {
                Spacer()
                // 主操作按钮区
                if canAccept {
                    HStack(spacing: 40) {
                        Button(action: {
                            vm.accept(call: call!)
                        }) {
                            VStack {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.green)
                                    .clipShape(Circle())
                                Text("接听")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        Button(action: {
                            vm.hangup(call: call!)
                        }) {
                            VStack {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                Text("拒绝")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                } else if canHangup {
                    Button(action: {
                        vm.hangup(call: call!)
                    }) {
                        VStack {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.red)
                                .clipShape(Circle())
                            Text("挂断")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.bottom, 24)
                }
                // 底部功能按钮区
                if isActive {
                    HStack(spacing: isVideo ? 32 : 40) {
                        Button(action: {
                            isSpeakerOn.toggle()
                            vm.setSpeaker(on: isSpeakerOn)
                        }) {
                            VStack {
                                Image(systemName: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.wave.2")
                                    .font(.system(size: 22))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                Text("免提")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                        Button(action: {
                            isMuted.toggle()
                            vm.setMuted(muted: isMuted)
                        }) {
                            VStack {
                                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                Text("静音")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                        if isVideo {
                            Button(action: {
                                vm.toggleCamera()
                            }) {
                                VStack {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                                        .font(.system(size: 22))
                                        .foregroundColor(.primary)
                                        .frame(width: 40, height: 40)
                                    Text("切换")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            }
                        } else {
                            Button(action: {
                                if let call = call {
                                    vm.toggleCallVideo(call: call)
                                }
                            }) {
                                VStack {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.primary)
                                        .frame(width: 40, height: 40)
                                    Text("视频")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        Button(action: {
                            showDtmfPad = true
                        }) {
                            VStack {
                                Image(systemName: "circle.grid.3x3.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                Text("键盘")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.bottom, 8)

            // 统计按钮右上角悬浮
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showStats.toggle()
                    }) {
                        Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                            .font(.system(size: 26))
                            .foregroundColor(.blue)
                            .padding(12)
                    }
                    .padding(.trailing, 18)
                    .padding(.top, 18)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(200)

            // 统计浮窗左上角，无背景色，浮于所有内容之上
            if showStats, let stats = stats {
                VStack(alignment: .leading, spacing: 6) {
                    Text("通话统计")
                        .font(.headline)
                    Text("下载带宽: \(String(format: "%.2f", stats.downloadBandwidth)) kbit/s")
                        .font(.caption)
                    Text("上传带宽: \(String(format: "%.2f", stats.uploadBandwidth)) kbit/s")
                        .font(.caption)
                    Text("丢包率: \(String(format: "%.2f", stats.localLossRate))%")
                        .font(.caption)
                    Text("远端丢包率: \(String(format: "%.2f", stats.receiverLossRate))%")
                        .font(.caption)
                    Text("往返延迟: \(String(format: "%.2f", stats.roundTripDelay)) s")
                        .font(.caption)
                    Text("抖动: \(String(format: "%.2f", stats.receiverInterarrivalJitter)) s")
                        .font(.caption)
                    Text("RTP丢包累计: \(stats.rtpCumPacketLoss)")
                        .font(.caption)
                    Text("RTP接收包数: \(stats.rtpPacketRecv)")
                        .font(.caption)
                    Text("RTP发送包数: \(stats.rtpPacketSent)")
                        .font(.caption)
                }
                .padding(.top, 18)
                .padding(.leading, 18)
                .frame(maxWidth: 320, alignment: .leading)
                .zIndex(300)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // 无背景色
            }
        }
        .sheet(isPresented: $showDtmfPad) {
            DtmfPadView { dtmf in
                if let char = dtmf.first {
                    vm.sendDtmf(dtmf: CChar(char.asciiValue ?? 0))
                }
            }
        }
        .onAppear {
            if isActive { startTimer() }
            updateIdleTimer(for: isActive)
        }
        .onDisappear {
            stopTimer()
            updateIdleTimer(for: false)
        }
        .onChange(of: isActive) { active in
            if active { startTimer() } else { stopTimer() }
            updateIdleTimer(for: active)
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
struct DialPadTabView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var dialNumber: String = ""
    @State private var showTextInput = false
    @State private var textInput = ""
    @State private var gateways: [GatewayItem] = []
    @State private var selectedGatewayId: Int? = nil
    @State private var isLoadingGateway = false

    let dialPadRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var selectedGateway: GatewayItem? {
        gateways.first(where: { $0.gateway_id == selectedGatewayId })
    }

    var body: some View {
        NavigationView {
            VStack {
                // 顶部网关选择
                HStack {
                    Text("网关:")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Picker("网关", selection: $selectedGatewayId) {
                        Text("自动").tag(Int?.none)
                        ForEach(gateways, id: \.gateway_id) { gw in
                            Text(gw.gateway_name).tag(Int?.some(gw.gateway_id))
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 140)
                    .disabled(isLoadingGateway)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

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
                            let target: String
                            if let gw = selectedGateway {
                                target = "sip:\(dialNumber)@\(gw.gateway_host)"
                            } else if let domain = vm.options?.domain {
                                target = "sip:\(dialNumber)@\(domain)"
                            } else {
                                target = dialNumber
                            }
                            vm.call(to: target)
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
                TextField("如 name 或 sip:name@domain", text: $textInput)
                Button("呼叫") {
                    var target = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !target.isEmpty {
                        if !target.contains("@") {
                            if let gw = selectedGateway {
                                target = "sip:\(target)@\(gw.gateway_host)"
                            } else if let domain = vm.options?.domain {
                                target = "sip:\(target)@\(domain)"
                            }
                        }
                        vm.call(to: target)
                    }
                    textInput = ""
                }
                Button("取消", role: .cancel) {
                    textInput = ""
                }
            }
            .onAppear {
                fetchGateways()
            }
        }
    }

    func fetchGateways() {
        isLoadingGateway = true
        //need 只获取落地
        HttpClient.shared.post(url: "\(apiUrl)/gateway/list", body: ["page": 1, "limit": 100]) { result in
            DispatchQueue.main.async {
                isLoadingGateway = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(GatewayListResponse.self, from: data), resp.code == 1 {
                        gateways = resp.data
                    } else {
                        gateways = []
                    }
                case .failure(_):
                    gateways = []
                }
            }
        }
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
struct DtmfPadView: View {
    var onSend: (String) -> Void
    @Environment(\.presentationMode) var presentationMode

    let dtmfRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("DTMF 拨号盘")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 24)
            Spacer()
            VStack(spacing: 18) {
                ForEach(dtmfRows, id: \.self) { row in
                    HStack(spacing: 28) {
                        ForEach(row, id: \.self) { digit in
                            Button(action: {
                                onSend(digit)
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
            }
            Spacer()
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("关闭")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
}


struct ContactEditAction: Identifiable {
    let id = UUID() // 唯一标识，满足 Identifiable 协议
    let contactId: Int64
}

struct ContactsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var showAddContact = false
    @State var editContact: Contact? = nil
    @State private var showDeleteAlert = false
    @State private var deletingContactId: Int64? = nil
    @State private var selectedSegment = 0
    @State private var cloudContacts: [Contact] = []
    @State private var isLoadingCloud = false

    let segments = ["本地联系人", "云端联系人"]

    var body: some View {
        NavigationView {
            VStack {
                Picker("联系人类型", selection: $selectedSegment) {
                    ForEach(0..<segments.count, id: \.self) { idx in
                        Text(segments[idx])
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if selectedSegment == 0 {
                    // 本地联系人
                    List {
                        ForEach(vm.contacts, id: \.id) { contact in
                            NavigationLink(destination: ContactDetailView(contact: contact, vm: vm)) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.18))
                                            .frame(width: 44, height: 44)
                                        Text(String(contact.username.prefix(1)))
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.username)
                                            .font(.headline)
                                        Text(contact.sipAddress ?? contact.phoneNumber ?? "")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deletingContactId = contact.id
                                    showDeleteAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editContact = contact
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .alert("确定要删除该联系人吗？", isPresented: $showDeleteAlert) {
                        Button("删除", role: .destructive) {
                            if let id = deletingContactId {
                                vm.deleteContact(id: id)
                            }
                            deletingContactId = nil
                        }
                        Button("取消", role: .cancel) {}
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showAddContact = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .sheet(isPresented: $showAddContact) {
                        AddEditContactView(
                            vm: vm,
                            contact: nil,
                            onSave: { newContact in
                                vm.addContact(newContact)
                                showAddContact = false
                            },
                            onCancel: { showAddContact = false }
                        )
                    }
                    .sheet(item: $editContact) { contact in
                        AddEditContactView(
                            vm: vm,
                            contact: contact,
                            onSave: { updatedContact in
                                vm.updateContact(updatedContact)
                                editContact = nil
                            },
                            onCancel: { editContact = nil }
                        )
                    }
                } else {
                    // 云端联系人
                    if isLoadingCloud {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(cloudContacts, id: \.id) { contact in
                                NavigationLink(destination: ContactDetailView(contact: contact, vm: vm)) {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.purple.opacity(0.18))
                                                .frame(width: 44, height: 44)
                                            Text(String(contact.username.prefix(1)))
                                                .font(.title2)
                                                .foregroundColor(.purple)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(contact.username)
                                                .font(.headline)
                                            Text(contact.sipAddress ?? contact.phoneNumber ?? "")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("联系人")
            .onChange(of: selectedSegment) { idx in
                if idx == 1 && cloudContacts.isEmpty {
                    fetchCloudContacts()
                }
            }
            .onAppear {
                if selectedSegment == 1 && cloudContacts.isEmpty {
                    fetchCloudContacts()
                }
            }
        }
    }

    func fetchCloudContacts() {
        isLoadingCloud = true
        let params: [String: Any] = ["page": 1, "limit": 100]
        HttpClient.shared.post(url: "\(apiUrl)/user/list", body: params) { result in
            DispatchQueue.main.async {
                isLoadingCloud = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(UserListResponse.self, from: data), resp.code == 1 {
                        cloudContacts = resp.data.map {
                            Contact(
                                id: Int64($0.user_id),
                                username: $0.user_displayname ?? $0.user_name,
                                sipAddress: "sip:\($0.user_name)@\(vm.options?.domain ?? "")",
                                phoneNumber: $0.user_phone,
                                remark: nil
                            )
                        }
                    }
                case .failure(let error):
                    vm.errorMessage = "云端联系人加载失败: \(error.localizedDescription)"
                }
            }
        }
    }
}


// 添加/编辑联系人页面
struct AddEditContactView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var contact: Contact?
    var onSave: (Contact) -> Void
    var onCancel: () -> Void

    @State private var username: String = ""
    @State private var sipAddress: String = ""
    @State private var phoneNumber: String = ""
    @State private var remark: String = ""

    var isEdit: Bool { contact != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                    TextField("SIP地址", text: $sipAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("手机号", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("备注", text: $remark)
                }
            }
            .navigationTitle(isEdit ? "编辑联系人" : "添加联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "保存" : "添加") {
                        let newContact = Contact(
                            id: contact?.id ?? 0,
                            username: username,
                            sipAddress: sipAddress.isEmpty ? nil : sipAddress,
                            phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber,
                            remark: remark.isEmpty ? nil : remark
                        )
                        onSave(newContact)
                    }
                    .disabled(username.isEmpty || (sipAddress.isEmpty && phoneNumber.isEmpty))
                }
            }
            .onAppear {
                if let c = contact {
                    username = c.username
                    sipAddress = c.sipAddress ?? ""
                    phoneNumber = c.phoneNumber ?? ""
                    remark = c.remark ?? ""
                }
            }
        }
    }
}

struct ContactDetailView: View {
    let contact: Contact
    @ObservedObject var vm: LinPhoneViewModel
    @State private var showChat = false

    // 拨号逻辑：优先用 sipAddress，其次用 phoneNumber 拼 sip 地址
    func callTarget(isVideo: Bool = false) {
        if let sip = contact.sipAddress, !sip.isEmpty {
            vm.call(to: sip, video: isVideo)
        } else if let phone = contact.phoneNumber, !phone.isEmpty, let domain = vm.options?.domain {
            let target = "sip:\(phone)@\(domain)"
            vm.call(to: target, video: isVideo)
        } else {
            vm.errorMessage = "无有效的拨号地址"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // 头像和昵称
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 110, height: 110)
                        Text(String(contact.username.prefix(1)))
                            .font(.system(size: 54, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    Text(contact.username)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 32)

                // 信息卡片
                VStack(spacing: 18) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text("用户名")
                            .foregroundColor(.gray)
                        Spacer()
                        Text(contact.username)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    Divider()
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.purple)
                        Text("SIP地址")
                            .foregroundColor(.gray)
                        Spacer()
                        Text(contact.sipAddress ?? "")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Divider()
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.orange)
                        Text("手机号")
                            .foregroundColor(.gray)
                        Spacer()
                        Text(contact.phoneNumber ?? "")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                )
                .padding(.horizontal, 20)

                // 操作按钮区
                HStack(spacing: 24) {
                    Button(action: { callTarget(isVideo: false) }) {
                        VStack {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.green)
                                .clipShape(Circle())
                                .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                            Text("语音通话")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .disabled((contact.sipAddress?.isEmpty ?? true) && (contact.phoneNumber?.isEmpty ?? true))

                    Button(action: { callTarget(isVideo: true) }) {
                        VStack {
                            Image(systemName: "video.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                            Text("视频通话")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(contact.sipAddress?.isEmpty ?? true) // 只有有sip地址才能视频

                    Button(action: { showChat = true }) {
                        VStack {
                            Image(systemName: "message.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(color: Color.orange.opacity(0.3), radius: 4, x: 0, y: 2)
                            Text("发信息")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .disabled(contact.sipAddress?.isEmpty ?? true) // 只有有sip地址才能发消息
                    .sheet(isPresented: $showChat) {
                        if let room = vm.chatRooms.first(where: { $0.peerAddress == contact.sipAddress }) {
                            ChatDetailView(vm: vm, room: room)
                        } else {
                            if let room = vm.findChatRoom(peerAddress: contact.sipAddress ?? "") {
                                ChatDetailView(vm: vm, room: room)
                            } else {
                                Text("无法创建聊天房间")
                            }
                        }
                    }
                }
                .padding(.top, 16)
                Spacer()
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("联系人详情")
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var showClearAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.callLogs, id: \.callId) { log in
                    Button(action: {
                        let target = log.remoteAddress?.asString() ?? ""
                        if !target.isEmpty {
                            vm.call(to: target, video: log.videoEnabled)
                        }
                    }) {
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
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .listStyle(.plain)
            .navigationTitle("通话记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showClearAlert = true
                    } label: {
                        Label("清空", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .alert("确定要清空所有通话记录吗？", isPresented: $showClearAlert) {
                Button("清空", role: .destructive) {
                    vm.clearCallLogs()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}


struct ChatView: View {
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        NavigationView {
            List {
                ForEach(vm.chatRooms, id: \.id) { room in
                    NavigationLink(destination: ChatDetailView(vm: vm, room: room)) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.18))
                                    .frame(width: 44, height: 44)
                                Text(room.peerAddress.prefix(1))
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(room.peerAddress)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(room.lastMessage ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let lastUpdate = room.lastUpdate {
                                Text(formatTimestamp(time_t(lastUpdate)))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("聊天")
        }
    }
}

struct ChatDetailView: View {
    @ObservedObject var vm: LinPhoneViewModel
    let room: ChatRoomLocal
    @State private var inputText: String = ""

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(vm.chatMessages, id: \.id) { msg in
                        HStack(alignment: .bottom) {
                            if msg.isOutgoing {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(msg.text)
                                        .padding(10)
                                        .background(Color.blue.opacity(0.18))
                                        .cornerRadius(12)
                                        .foregroundColor(.primary)
                                    Text(formatTimestamp(time_t(msg.time)))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(msg.text)
                                        .padding(10)
                                        .background(Color.gray.opacity(0.12))
                                        .cornerRadius(12)
                                        .foregroundColor(.primary)
                                    Text(formatTimestamp(time_t(msg.time)))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            HStack {
                TextField("输入消息...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.vertical, 8)
                Button(action: {
                    let to = room.peerAddress
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !to.isEmpty {
                        vm.sendMessage(to: to, message: inputText)
                        inputText = ""
                        //vm.enterChatRoom(roomId: room.id)
                    }
                }) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .background(Color(.systemBackground))
        }
        .navigationTitle(room.peerAddress)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            vm.enterChatRoom(roomId: room.id)
        }
        .onDisappear {
            vm.exitChatRoom()
        }
    }
}



struct SettingsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // 账号信息卡片
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("当前账号")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Text(vm.options?.username ?? "未登录")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .shadow(radius: 4)
                )
                .padding(.horizontal, 24)

                // 管理模块入口（紧跟账号信息卡片）
                VStack(spacing: 18) {
                    NavigationLink(destination: UserManagementView(vm: vm)) {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(.blue)
                            Text("用户管理")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    NavigationLink(destination: GatewayManagementView(vm: vm)) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.purple)
                            Text("网关管理")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    NavigationLink(destination: CallQueryView()) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.green)
                            Text("通话查询")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // 注销按钮单独分组，放底部
                VStack {
                    Divider()
                    Button(action: {
                        showLogoutAlert = true
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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("设置")
            .alert("确定要注销并退出登录吗？", isPresented: $showLogoutAlert) {
                Button("注销", role: .destructive) {
                    vm.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}


struct UserItem: Identifiable, Decodable {
    let user_id: Int
    let user_name: String
    let user_password: String
    let user_displayname: String?
    let user_phone: String?
    let user_type: Int // 1内部, 2 对接
    let user_enabled: Int // 1启用 2禁用
    let user_role:Int //1 管理员 2 普通用户

    var id: Int { user_id }
}

struct UserResponse: Decodable {
    let code: Int
    let message: String
}

struct UserListResponse: Decodable {
    let code: Int
    let message: String
    let data: [UserItem]
    let total: Int
}


// 用户管理列表
struct UserManagementView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var users: [UserItem] = []
    @State private var page = 1
    @State private var limit = 20
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var showAddUser = false
    @State private var editUser: UserItem? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(users) { user in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(user.user_displayname ?? "")
                                .font(.headline)
                            Spacer()
                            Text(user.user_enabled == 1 ? "启用" : "禁用")
                                .font(.caption)
                                .foregroundColor(user.user_enabled == 1 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill((user.user_enabled == 1 ? Color.green : Color.red).opacity(0.12))
                                )
                        }
                        Text("账号: \(user.user_name)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        if let phone = user.user_phone, !phone.isEmpty {
                            Text("手机号: \(phone)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Text("类型: \(user.user_type == 1 ? "内部" : "对接") 角色: \(user.user_role == 1 ? "管理员" : "普通用户")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteUser(user)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editUser = user
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                // 底部加载更多
                if users.count < totalCount && !isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                loadMore()
                            }
                        Spacer()
                    }
                }
            }
            .navigationTitle("用户管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddUser = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .overlay(
                Group {
                    if isLoading && users.isEmpty {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground).opacity(0.7))
                    }
                }
            )
            .sheet(isPresented: $showAddUser) {
                AddEditUserView(
                    vm: vm,
                    user: nil,
                    onSave: { newUser in
                        addUser(newUser)
                    },
                    onCancel: { showAddUser = false }
                )
            }
            .sheet(item: $editUser) { user in
                AddEditUserView(
                    vm: vm,
                    user: user,
                    onSave: { updatedUser in
                        updateUser(updatedUser)
                    },
                    onCancel: { editUser = nil }
                )
            }
            .onAppear {
                if users.isEmpty {
                    Task { await refresh() }
                }
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        page = 1
        await fetchUsers(reset: true)
        isRefreshing = false
    }

    func loadMore() {
        guard !isLoading, users.count < totalCount else { return }
        page += 1
        fetchUsers(reset: false)
    }

    func fetchUsers(reset: Bool) {
        isLoading = true
        let params = ["page": page, "limit": limit]
        HttpClient.shared.post(url: "\(apiUrl)/user/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(UserListResponse.self, from: data) {
                        if resp.code == 1 {
                            totalCount = resp.total
                            if reset {
                                users = resp.data
                            } else {
                                users += resp.data
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchUsers(reset: Bool) async {
        await withCheckedContinuation { continuation in
            fetchUsers(reset: reset)
            continuation.resume()
        }
    }

    func addUser(_ user: UserItem) {
        isLoading = true
        let params: [String: Any] = [
            "user_name": user.user_name,
            "user_displayname": user.user_displayname,
            "user_password": user.user_password,
            "user_phone": user.user_phone ?? "",
            "user_type": user.user_type,
            "user_enabled": user.user_enabled,
            "user_role": user.user_role
        ]
        HttpClient.shared.post(url: "\(apiUrl)/user/add", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(UserResponse.self, from: data) {
                        if resp.code == 1 {
                            showAddUser = false
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "添加失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateUser(_ user: UserItem) {
        isLoading = true
        let params: [String: Any] = [
            "user_id": user.user_id,
            "user_name": user.user_name,
            "user_displayname": user.user_displayname,
            "user_password": user.user_password,
            "user_phone": user.user_phone ?? "",
            "user_type": user.user_type,
            "user_enabled": user.user_enabled,
            "user_role": user.user_role
        ]
        HttpClient.shared.post(url: "\(apiUrl)/user/update", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(UserResponse.self, from: data) {
                        if resp.code == 1 {
                            editUser = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "修改失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteUser(_ user: UserItem) {
        isLoading = true
        let params: [String: Any] = [
            "user_id": user.user_id
        ]
        HttpClient.shared.post(url: "\(apiUrl)/user/delete", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(UserResponse.self, from: data) {
                        if resp.code == 1 {
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "删除失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

// 添加/编辑用户弹窗
struct AddEditUserView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var user: UserItem?
    var onSave: (UserItem) -> Void
    var onCancel: () -> Void

    @State private var userName: String = ""
    @State private var displayName: String = ""
    @State private var password: String = ""
    @State private var phone: String = ""
    @State private var userType: Int = 2
    @State private var userEnabled: Int = 1
    @State private var userRole: Int = 2

    let typeOptions = [
        (name: "内部", value: 1),
        (name: "对接", value: 2)
    ]
    let enabledOptions = [
        (name: "启用", value: 1),
        (name: "禁用", value: 2)
    ]
    let roleOptions = [
        (name: "管理员", value: 1),
        (name: "普通用户", value: 2)
    ]

    var isEdit: Bool { user != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("用户信息")) {
                    if isEdit {
                        TextField("账号", text: $userName)
                            .disabled(true)
                            .foregroundColor(.gray)
                    } else {
                        TextField("账号", text: $userName)
                            .textInputAutocapitalization(.never)
                    }
                    TextField("显示名称", text: $displayName)
                    SecureField("密码", text: $password)
                    TextField("手机号（可选）", text: $phone)
                        .keyboardType(.phonePad)
                    Picker("类型", selection: $userType) {
                        ForEach(typeOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    Picker("状态", selection: $userEnabled) {
                        ForEach(enabledOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    Picker("角色", selection: $userRole) {
                        ForEach(roleOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? "修改用户" : "添加用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "保存" : "添加") {
                        let newUser = UserItem(
                            user_id: user?.user_id ?? 0,
                            user_name: userName,
                            user_password: password,
                            user_displayname: displayName,
                            user_phone: phone.isEmpty ? nil : phone,
                            user_type: userType,
                            user_enabled: userEnabled,
                            user_role: userRole
                        )
                        onSave(newUser)
                    }
                    .disabled(userName.isEmpty || displayName.isEmpty || password.isEmpty)
                }
            }
            .onAppear {
                if let u = user {
                    userName = u.user_name
                    displayName = u.user_displayname ?? ""
                    password = u.user_password
                    phone = u.user_phone ?? ""
                    userType = u.user_type
                    userEnabled = u.user_enabled
                    userRole = u.user_role
                }
            }
        }
        .overlay(
            Group {
                if let error = vm.errorMessage {
                    ToastView(message: error)
                        .transition(.opacity)
                        .zIndex(200)
                }
            }
        )
    }
}


struct GatewayItem: Identifiable, Decodable {
    let gateway_id: Int
    let gateway_name: String
    let gateway_type: Int //1 sip 2 h323 
    let gateway_host: String
    let gateway_port: Int
    let gateway_realm: String
    let gateway_username: String
    let gateway_password: String
    let gateway_authtype:Int //1 帐号认证 2 IP认证
    let gateway_enabled: Int // 1启用 2禁用
    let gateway_remark: String?

    var id: Int { gateway_id }
}

struct GatewayResponse: Decodable {
    let code: Int
    let message: String
}

struct GatewayListResponse: Decodable {
    let code: Int
    let message: String
    let data: [GatewayItem]
    let total: Int
}


struct GatewayManagementView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var gateways: [GatewayItem] = []
    @State private var page = 1
    @State private var limit = 20
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var showAddGateway = false
    @State private var editGateway: GatewayItem? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(gateways) { gateway in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(gateway.gateway_name)
                                .font(.headline)
                            Spacer()
                            Text(gateway.gateway_enabled == 1 ? "启用" : "禁用")
                                .font(.caption)
                                .foregroundColor(gateway.gateway_enabled == 1 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill((gateway.gateway_enabled == 1 ? Color.green : Color.red).opacity(0.12))
                                )
                        }
                        Text("类型: \(gateway.gateway_type == 1 ? "SIP" : "H323") 认证: \(gateway.gateway_authtype == 1 ? "帐号" : "IP")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("地址: \(gateway.gateway_host):\(gateway.gateway_port) Realm: \(gateway.gateway_realm)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("用户名: \(gateway.gateway_username)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        if let remark = gateway.gateway_remark, !remark.isEmpty {
                            Text("备注: \(remark)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteGateway(gateway)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editGateway = gateway
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                // 底部加载更多
                if gateways.count < totalCount && !isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                loadMore()
                            }
                        Spacer()
                    }
                }
            }
            .navigationTitle("网关管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddGateway = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .overlay(
                Group {
                    if isLoading && gateways.isEmpty {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground).opacity(0.7))
                    }
                }
            )
            .sheet(isPresented: $showAddGateway) {
                AddEditGatewayView(
                    vm: vm,
                    gateway: nil,
                    onSave: { newGateway in
                        addGateway(newGateway)
                    },
                    onCancel: { showAddGateway = false }
                )
            }
            .sheet(item: $editGateway) { gateway in
                AddEditGatewayView(
                    vm: vm,
                    gateway: gateway,
                    onSave: { updatedGateway in
                        updateGateway(updatedGateway)
                    },
                    onCancel: { editGateway = nil }
                )
            }
            .onAppear {
                if gateways.isEmpty {
                    Task { await refresh() }
                }
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        page = 1
        await fetchGateways(reset: true)
        isRefreshing = false
    }

    func loadMore() {
        guard !isLoading, gateways.count < totalCount else { return }
        page += 1
        fetchGateways(reset: false)
    }

    func fetchGateways(reset: Bool) {
        isLoading = true
        let params = ["page": page, "limit": limit]
        HttpClient.shared.post(url: "\(apiUrl)/gateway/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    print("Gateway list response: \(String(data: data, encoding: .utf8) ?? "")")
                    if let resp = try? JSONDecoder().decode(GatewayListResponse.self, from: data) {
                        if resp.code == 1 {
                            totalCount = resp.total
                            if reset {
                                gateways = resp.data
                            } else {
                                gateways += resp.data
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchGateways(reset: Bool) async {
        await withCheckedContinuation { continuation in
            fetchGateways(reset: reset)
            continuation.resume()
        }
    }

    func addGateway(_ gateway: GatewayItem) {
        isLoading = true
        let params: [String: Any] = [
            "gateway_name": gateway.gateway_name,
            "gateway_type": gateway.gateway_type,
            "gateway_host": gateway.gateway_host,
            "gateway_port": gateway.gateway_port,
            "gateway_realm": gateway.gateway_realm,
            "gateway_username": gateway.gateway_username,
            "gateway_password": gateway.gateway_password,
            "gateway_authtype": gateway.gateway_authtype,
            "gateway_enabled": gateway.gateway_enabled,
            "gateway_remark": gateway.gateway_remark
        ]
        HttpClient.shared.post(url: "\(apiUrl)/gateway/add", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(GatewayResponse.self, from: data) {
                        if resp.code == 1 {
                            showAddGateway = false
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "添加失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateGateway(_ gateway: GatewayItem) {
        isLoading = true
        let params: [String: Any] = [
            "gateway_id": gateway.gateway_id,
            "gateway_name": gateway.gateway_name,
            "gateway_type": gateway.gateway_type,
            "gateway_host": gateway.gateway_host,
            "gateway_port": gateway.gateway_port,
            "gateway_realm": gateway.gateway_realm,
            "gateway_username": gateway.gateway_username,
            "gateway_password": gateway.gateway_password,
            "gateway_authtype": gateway.gateway_authtype,
            "gateway_enabled": gateway.gateway_enabled,
            "gateway_remark": gateway.gateway_remark
        ]
        HttpClient.shared.post(url: "\(apiUrl)/gateway/update", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(GatewayResponse.self, from: data) {
                        if resp.code == 1 {
                            editGateway = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "修改失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteGateway(_ gateway: GatewayItem) {
        isLoading = true
        let params: [String: Any] = [
            "gateway_id": gateway.gateway_id
        ]
        HttpClient.shared.post(url: "\(apiUrl)/gateway/delete", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    if let resp = try? JSONDecoder().decode(GatewayResponse.self, from: data) {
                        if resp.code == 1 {
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } else {
                        vm.errorMessage = "删除失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AddEditGatewayView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var gateway: GatewayItem?
    var onSave: (GatewayItem) -> Void
    var onCancel: () -> Void

    @State private var gatewayName: String = ""
    @State private var gatewayType: Int = 1 // 1=sip, 2=h323
    @State private var gatewayHost: String = ""
    @State private var gatewayPort: String = ""
    @State private var gatewayRealm: String = ""
    @State private var gatewayUsername: String = ""
    @State private var gatewayPassword: String = ""
    @State private var gatewayAuthtype: Int = 1 // 1帐号认证 2 IP认证
    @State private var gatewayRemark: String = ""
    @State private var gatewayEnabled: Int = 1 // 默认启用

    let gatewayTypeOptions = [
        (name: "SIP网关", value: 1),
        (name: "H323网关", value: 2)
    ]
    let authtypeOptions = [
        (name: "帐号认证", value: 1),
        (name: "IP认证", value: 2)
    ]
    let enabledOptions = [
        (name: "启用", value: 1),
        (name: "禁用", value: 2)
    ]

    var isEdit: Bool { gateway != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("网关信息")) {
                    TextField("网关名称", text: $gatewayName)
                    Picker("类型", selection: $gatewayType) {
                        ForEach(gatewayTypeOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    TextField("主机地址", text: $gatewayHost)
                    TextField("端口", text: $gatewayPort)
                        .keyboardType(.numberPad)
                    TextField("Realm", text: $gatewayRealm)
                    TextField("用户名", text: $gatewayUsername)
                    SecureField("密码", text: $gatewayPassword)
                    Picker("认证方式", selection: $gatewayAuthtype) {
                        ForEach(authtypeOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    Picker("状态", selection: $gatewayEnabled) {
                        ForEach(enabledOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    TextField("备注（可选）", text: $gatewayRemark)
                }
            }
            .navigationTitle(isEdit ? "编辑网关" : "添加网关")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "保存" : "添加") {
                        let newGateway = GatewayItem(
                            gateway_id: gateway?.gateway_id ?? 0,
                            gateway_name: gatewayName,
                            gateway_type: gatewayType,
                            gateway_host: gatewayHost,
                            gateway_port: Int(gatewayPort) ?? 5060,
                            gateway_realm: gatewayRealm,
                            gateway_username: gatewayUsername,
                            gateway_password: gatewayPassword,
                            gateway_authtype: gatewayAuthtype,
                            gateway_enabled: gatewayEnabled,
                            gateway_remark: gatewayRemark.isEmpty ? nil : gatewayRemark
                        )
                        onSave(newGateway)
                    }
                    .disabled(gatewayName.isEmpty || gatewayHost.isEmpty || gatewayPort.isEmpty || gatewayUsername.isEmpty || gatewayPassword.isEmpty)
                }
            }
            .onAppear {
                if let g = gateway {
                    gatewayName = g.gateway_name
                    gatewayType = g.gateway_type
                    gatewayHost = g.gateway_host
                    gatewayPort = "\(g.gateway_port)"
                    gatewayRealm = g.gateway_realm
                    gatewayUsername = g.gateway_username
                    gatewayPassword = g.gateway_password
                    gatewayAuthtype = g.gateway_authtype
                    gatewayRemark = g.gateway_remark ?? ""
                    gatewayEnabled = g.gateway_enabled
                }
            }
        }
        .overlay(
            Group {
                if let error = vm.errorMessage {
                    ToastView(message: error)
                        .transition(.opacity)
                        .zIndex(200)
                }
            }
        )
    }
}

struct CallItem: Identifiable, Decodable {
    let call_id: Int
    let call_callid: String
    let call_direction: Int? //1 呼入 2 呼出 3 内部
    let call_fromuri: String
    let call_touri: String
    let call_fromtag: String
    let call_totag: String?
    let call_finalcode: Int?
    let call_starttime: String? //开始时间
    let call_answertime: String? //应答时间
    let call_endtime: String?
    let call_duration: Int? //通话时长，单位秒
    let call_gatewayid: Int?
    let call_gatewayname: String?
    let call_status:Int?   //1 未接通 2 已接通
    let call_hangupcause: Int? //1 正常 2 取消 3 拒绝 4 忙 5 未接听（超时） 6 错误 
    let call_errorcause: Int? // 1 邀请系统错误 2 桥接系统错误 3 邀请ua返回错误码 4 桥接ua返回错误码 

    var id : Int { call_id }
}

struct CallListResponse: Decodable {
    let code: Int
    let message: String
    let data: [CallItem]
    let total: Int
}

struct CallQueryView: View {
    @State private var calls: [CallItem] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var limit = 20
    @State private var totalCount = 0

    var body: some View {
        NavigationView {
            List {
                ForEach(calls) { call in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(call.call_direction == 1 ? "呼入" : (call.call_direction == 2 ? "呼出" : "内部"))
                                .font(.headline)
                                .foregroundColor(call.call_direction == 1 ? .green : (call.call_direction == 2 ? .blue : .gray))
                            Spacer()
                            Text(call.call_status == 2 ? "已接通" : "未接通")
                                .font(.caption)
                                .foregroundColor(call.call_status == 2 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill((call.call_status == 2 ? Color.green : Color.red).opacity(0.12))
                                )
                        }
                        Text("主叫: \(call.call_fromuri)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("被叫: \(call.call_touri)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("网关: \(call.call_gatewayname ?? "")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        HStack(spacing: 16) {
                            /*Text("开始: \(formatDate(call.call_starttime))")*/
                            Text("时长: \(call.call_duration ?? 0)秒")
                        }
                        .font(.caption2)
                        .foregroundColor(.gray)
                        HStack(spacing: 16) {
                            Text("挂断原因: \(hangupCauseText(call.call_hangupcause ?? 0))")
                            Text("最终响应: \(call.call_finalcode ?? 0)")
                        }
                        .font(.caption2)
                        .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
                // 底部加载更多
                if calls.count < totalCount && !isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear {
                                loadMore()
                            }
                        Spacer()
                    }
                }
            }
            .navigationTitle("通话查询")
            .onAppear {
                if calls.isEmpty {
                    fetchCalls(reset: true)
                }
            }
            .refreshable {
                fetchCalls(reset: true)
            }
        }
    }

    func fetchCalls(reset: Bool) {
        isLoading = true
        let params: [String: Any] = ["page": page, "limit": limit]
        HttpClient.shared.post(url: "\(apiUrl)/call/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    print("Call list response: \(String(data: data, encoding: .utf8) ?? "")")
                    if let resp = try? JSONDecoder().decode(CallListResponse.self, from: data) {
                        totalCount = resp.total
                        if reset {
                            calls = resp.data
                        } else {
                            calls += resp.data
                        }
                    }
                case .failure(_):
                    // Handle error case
                    calls = []
                }
            }
        }
    }

    func loadMore() {
        guard !isLoading, calls.count < totalCount else { return }
        page += 1
        fetchCalls(reset: false)
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    func hangupCauseText(_ cause: Int) -> String {
        switch cause {
        case 1: return "正常"
        case 2: return "取消"
        case 3: return "拒绝"
        case 4: return "忙"
        case 5: return "未接听"
        case 6: return "错误"
        default: return "-"
        }
    }

    func errorCauseText(_ cause: Int) -> String {
        switch cause {
        case 1: return "邀请系统错误"
        case 2: return "桥接系统错误"
        case 3: return "邀请UA错误码"
        case 4: return "桥接UA错误码"
        default: return "-"
        }
    }
}





