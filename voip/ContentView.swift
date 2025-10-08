//
//  ContentView.swift
//  voip
//
//  Created by vc on 2025/9/8.
//

import SwiftUI
import linphonesw
import UIKit

struct CommonResponse: Decodable {
    let code: Int
    let message: String
}

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



// 轻量毛玻璃视图，用于 Toast 背景
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// 美化后的 ToastView：磨砂背景 + 半透明叠加 + 圆角 + 阴影
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.body)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 340)
            .background(
                ZStack {
                    BlurView(style: .systemThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
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
            else{
                domain = "180.97.215.207:5555"
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
        let params: [String: Any?] = ["page": 1, "limit": 1000]
        vm.post(path: "/gateway/list", body: params) { result in
            DispatchQueue.main.async {
                isLoadingGateway = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data) 
                        if resp.code == 1 {
                            let gatewayResp = try JSONDecoder().decode(GatewayListResponse.self, from: data)
                            gateways = gatewayResp.data
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "请求失败: \(error.localizedDescription)"
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
        let params: [String: Any?] = ["page": 1, "limit": 1000]
        vm.post(path: "/user/list", body: params) { result in
            DispatchQueue.main.async {
                isLoadingCloud = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let userListResp = try JSONDecoder().decode(UserListResponse.self, from: data)
                            cloudContacts = userListResp.data.map {
                                Contact(
                                    id: Int64($0.user_id),
                                    username: $0.user_displayname ?? $0.user_name,
                                    sipAddress: "sip:\($0.user_name)@\(vm.options?.domain ?? "")",
                                    phoneNumber: $0.user_phone,
                                    remark: nil
                                )
                            }
                        } else {
                            vm.errorMessage =  resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
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

//utc字符串转本地时间字符串
// ...existing code...
func formatUtcString(_ utcString: String?) -> String {
    guard let s = utcString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return "-" }

    // 1) 优先使用 ISO8601DateFormatter（支持 fractional seconds）
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) {
        let out = DateFormatter()
        out.locale = Locale.current
        out.timeZone = TimeZone.current
        out.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return out.string(from: d)
    }

    // 2) 再尝试不带 fractional seconds 的 ISO8601
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: s) {
        let out = DateFormatter()
        out.locale = Locale.current
        out.timeZone = TimeZone.current
        out.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return out.string(from: d)
    }


    // 无法解析则返回原值或 "-"
    return utcString ?? "-"
}
// ...existing code...

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
                    NavigationLink(destination: CallQueryView(vm: vm)) {
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
    let user_gatewaytype: Int? // 1 全部 2 部分
    let user_gateways: [Int]?
    var id: Int { user_id }
}



struct UserInfoResponse: Decodable {
    let code: Int
    let message: String
    let data: UserItem
    
}

struct UserListResponse: Decodable {
    let code: Int
    let message: String
    let data: [UserItem]
    let total: Int
}


// 用户管理列表
// ...existing code...

// ...existing code...

// 完整的用户管理视图（含把保存落地网关请求放在父视图处理）
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
    @State private var setGatewaysUser: UserItem? = nil // 打开设置落地网关弹窗

    var body: some View {
        //NavigationView {
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
                        Button {
                            setGatewaysUser = user
                        } label: {
                            Label("落地网关", systemImage: "network")
                        }
                        .tint(.purple)
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
            // SetUserGatewaysView 只负责 UI，保存由父视图 setUserGateways 执行
            .sheet(item: $setGatewaysUser) { user in
                SetUserGatewaysView(
                    vm: vm,
                    user: user,
                    onSave: { userId, gatewayType, gatewayIds in
                        // 由父视图统一提交保存请求
                        setUserGateways(userId: userId, gatewayType: gatewayType, gatewayIds: gatewayIds)
                    },
                    onCancel: {
                        setGatewaysUser = nil
                    }
                    
                )
            }
            .onAppear {
                if users.isEmpty {
                    Task { await refresh() }
                }
            }
        //}
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
        let params: [String: Any?] = ["page": page, "limit": limit]
        vm.post(path: "/user/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let userListResp = try JSONDecoder().decode(UserListResponse.self, from: data)
                            totalCount = userListResp.total
                            if reset {
                                users = userListResp.data
                            } else {
                                users += userListResp.data
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
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
        let params: [String: Any?] = [
            "user_name": user.user_name,
            "user_displayname": user.user_displayname,
            "user_password": user.user_password,
            "user_phone": user.user_phone,
            "user_type": user.user_type,
            "user_enabled": user.user_enabled,
            "user_role": user.user_role
        ]
        vm.post(path: "/user/add", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            showAddUser = false
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
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
        let params: [String: Any?] = [
            "user_id": user.user_id,
            "user_name": user.user_name,
            "user_displayname": user.user_displayname,
            "user_password": user.user_password,
            "user_phone": user.user_phone,
            "user_type": user.user_type,
            "user_enabled": user.user_enabled,
            "user_role": user.user_role
        ]
        vm.post(path: "/user/update", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do{
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            editUser = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
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
        let params: [String: Any?] = [
            "user_id": user.user_id
        ]
        vm.post(path: "/user/delete", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "删除失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    // 将 /user/set_gateways 请求放到父视图统一处理
    func setUserGateways(userId: Int, gatewayType: Int, gatewayIds: [Int]) {
        isLoading = true
        var params: [String: Any?] = [
            "user_id": userId,
            "user_gatewaytype": gatewayType
        ]

        if gatewayType == 2 {
            do {
                let data = try JSONSerialization.data(withJSONObject: gatewayIds, options: [])
                if let jsonString = String(data: data, encoding: .utf8) {
                    params["user_gateways"] = jsonString // -> "[1,2,3]"
                }
            } catch {
                vm.errorMessage = "序列化 gatewayIds 失败: \(error.localizedDescription)"
                return
            }
        }
        vm.post(path: "/user/set_gateways", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            setGatewaysUser = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "保存失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

// SetUserGatewaysView：仅负责 UI，onSave 回调交给父视图执行保存
struct SetUserGatewaysView: View {
    @ObservedObject var vm: LinPhoneViewModel
    let user: UserItem
    var onSave: (_ userId: Int, _ gatewayType: Int, _ gatewayIds: [Int]) -> Void
    var onCancel: () -> Void
    

    @State private var gateways: [GatewayItem] = []
    @State private var isLoading = false
    @State private var gatewayType: Int = 1 // 1 全部, 2 部分
    @State private var selectedGatewayIds: Set<Int> = []
    @State private var initialLoaded = false
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("落地网关范围")) {
                        Picker("类型", selection: $gatewayType) {
                            Text("全部").tag(1)
                            Text("部分").tag(2)
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    if gatewayType == 2 {
                        Section(header: Text("选择网关")) {
                            if isLoading {
                                HStack { Spacer(); ProgressView(); Spacer() }
                            } else if gateways.isEmpty {
                                Text("没有可用网关").foregroundColor(.gray)
                            } else {
                                ForEach(gateways) { gw in
                                    Toggle(isOn: Binding(
                                        get: { selectedGatewayIds.contains(gw.gateway_id) },
                                        set: { on in
                                            if on { selectedGatewayIds.insert(gw.gateway_id) }
                                            else { selectedGatewayIds.remove(gw.gateway_id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(gw.gateway_name)
                                                .font(.subheadline)
                                            Text("\(gw.gateway_host):\(gw.gateway_port)")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            .navigationTitle("设置落地网关")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: { onCancel() })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        isSaving = true
                        // 由父视图执行网络保存，传回去后关闭 sheet（父视图处理刷新）
                        onSave(user.user_id, gatewayType, Array(selectedGatewayIds))
                        // 由父视图刷新用户列表后关闭 sheet；这里本地提前结束保存状态
                        isSaving = false
                        onCancel()
                    }) {
                        Text(isSaving ? "保存中..." : "保存")
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if !initialLoaded {
                    initialLoaded = true
                    loadGateways()
                    loadUserInfoAndInit()
                }
            }
            .overlay(
                Group {
                    if let err = vm.errorMessage {
                        ToastView(message: err).zIndex(200)
                    }
                }
            )
        }
    }

    func loadGateways() {
        isLoading = true
        let params: [String: Any?] = ["page": 1, "limit": 1000]
        vm.post(path: "/gateway/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let gatewayListResp = try JSONDecoder().decode(GatewayListResponse.self, from: data)
                            gateways = gatewayListResp.data
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func loadUserInfoAndInit() {
        isLoading = true
        let params: [String: Any?] = ["user_id": user.user_id]
        vm.post(path: "/user/info", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let userInfoResp = try JSONDecoder().decode(UserInfoResponse.self, from: data)
                            let u = userInfoResp.data
                            gatewayType = u.user_gatewaytype ?? 2
                            selectedGatewayIds = Set(u.user_gateways ?? [])
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
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
    var user: UserItem? // 传入时只带 user_id 用于编辑场景
    var onSave: (UserItem) -> Void
    var onCancel: () -> Void

    @State private var userId: Int = 0
    @State private var userName: String = ""
    @State private var displayName: String = ""
    @State private var password: String = ""
    @State private var phone: String = ""
    @State private var userType: Int = 2
    @State private var userEnabled: Int = 1
    @State private var userRole: Int = 2

    @State private var isLoading = false
    @State private var initialLoaded = false

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
            ZStack {
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

                if isLoading {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("加载中...").padding().background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
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
                            user_id: userId,
                            user_name: userName,
                            user_password: password,
                            user_displayname: displayName.isEmpty ? nil : displayName,
                            user_phone: phone.isEmpty ? nil : phone,
                            user_type: userType,
                            user_enabled: userEnabled,
                            user_role: userRole,
                            user_gatewaytype: nil,
                            user_gateways: nil
                        )
                        onSave(newUser)
                    }
                    .disabled(userName.isEmpty || (!isEdit && password.isEmpty))
                }
            }
            .onAppear {
                if isEdit && !initialLoaded {
                    initialLoaded = true
                    userId = user?.user_id ?? 0
                    loadUserInfoAndInit()
                } else if !isEdit && !initialLoaded {
                    initialLoaded = true
                    // 新增时保持默认空字段
                }
            }
            .overlay(
                Group {
                    if let err = vm.errorMessage {
                        ToastView(message: err).zIndex(200)
                    }
                }
            )
        }
    }

    func loadUserInfoAndInit() {
        guard let uid = user?.user_id else { return }
        isLoading = true
        let params: [String: Any?] = ["user_id": uid]
        vm.post(path: "/user/info", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let userInfoResp = try JSONDecoder().decode(UserInfoResponse.self, from: data)
                            let u = userInfoResp.data
                            userId = u.user_id
                            userName = u.user_name
                            displayName = u.user_displayname ?? ""
                            // 后端可能不返回密码，保持空则表示不修改
                            password = u.user_password
                            phone = u.user_phone ?? ""
                            userType = u.user_type
                            userEnabled = u.user_enabled
                            userRole = u.user_role
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
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


struct GatewayInfoResponse: Decodable {
    let code: Int
    let message: String
    let data: GatewayItem
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
    @State private var showRouteForGateway: GatewayItem? = nil

    var body: some View {
        //NavigationView {
            List {
                ForEach(gateways) { gateway in
                    NavigationLink(destination: GatewayDetailView(vm: vm, gatewayId: gateway.gateway_id)) {
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
                        Button {
                            showRouteForGateway = gateway
                        } label: {
                            Label("路由", systemImage: "arrow.triangle.branch")
                        }
                        .tint(.blue)
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
            .sheet(item: $showRouteForGateway) { gw in
                
                RouteManagementView(vm: vm, gateway: gw)
            }
            .onAppear {
                if gateways.isEmpty {
                    Task { await refresh() }
                }
            }
        //}
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
        let params: [String: Any?] = ["page": page, "limit": limit]
        vm.post(path: "/gateway/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let gatewayListResp = try JSONDecoder().decode(GatewayListResponse.self, from: data)
                            totalCount = gatewayListResp.total
                            if reset {
                                gateways = gatewayListResp.data
                            } else {
                                gateways += gatewayListResp.data
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } 
                    catch {
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
        let params: [String: Any?] = [
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
        vm.post(path: "/gateway/add", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            showAddGateway = false
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } 
                    catch {
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
        let params: [String: Any?] = [
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
        vm.post(path: "/gateway/update", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            editGateway = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } 
                    catch {
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
        let params: [String: Any?] = [
            "gateway_id": gateway.gateway_id
        ]
        vm.post(path: "/gateway/delete", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "删除失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

// ...existing code...

// MARK: - /gateway/stat 响应数据结构
struct GatewayStatResponse: Decodable {
    let code: Int
    let message: String
    let data: GatewayStatData
}

struct GatewayStatData: Decodable {
    let summary: GatewaySummary?
    let finalcodes: [FinalCodeItem]?
    let hangupBreakdown: [HangupBreakdownItem]?
    let errorBreakdown: [ErrorBreakdownItem]?
    let daily: [DailyStatItem]?
    let from: String?
    let to: String?
}

struct GatewaySummary: Decodable {
    let total_calls: String
    let answered_calls: String
    let asr_percent: String
    let total_answered_seconds: Int
    let avg_answered_seconds: String
}

struct FinalCodeItem: Decodable, Identifiable {
    let call_finalcode: Int?
    let cnt: String
    var id: Int { call_finalcode ?? 0 }
}

struct HangupBreakdownItem: Decodable, Identifiable {
    let hangup_cause: Int
    let cnt: String
    var id: Int { hangup_cause }
}

struct ErrorBreakdownItem: Decodable, Identifiable {
    let error_cause: Int
    let cnt: String
    var id: Int { error_cause }
}

struct DailyStatItem: Decodable, Identifiable {
    let day: String
    let total_calls: String
    let answered_calls: String
    var id: String { day }
}



// MARK: - 网关详情页
struct GatewayDetailView: View {
    @ObservedObject var vm: LinPhoneViewModel
    let gatewayId: Int

    @State private var gateway: GatewayItem?
    @State private var stats: GatewayStatData?
    @State private var isLoadingInfo = false
    @State private var isLoadingStats = false
    @State private var initialLoaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 基本信息
                GroupBox(label: Text("网关信息")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let g = gateway {
                            HStack {
                                Text(g.gateway_name).font(.headline)
                                Spacer()
                                Text(g.gateway_enabled == 1 ? "启用" : "禁用")
                                    .font(.caption)
                                    .foregroundColor(g.gateway_enabled == 1 ? .green : .red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill((g.gateway_enabled == 1 ? Color.green : Color.red).opacity(0.12)))
                            }
                            Text("类型: \(g.gateway_type == 1 ? "SIP" : "H323")")
                            Text("地址: \(g.gateway_host):\(g.gateway_port)")
                            Text("Realm: \(g.gateway_realm)")
                            Text("用户名: \(g.gateway_username)")
                            Text("备注: \(g.gateway_remark ?? "")").foregroundColor(.secondary)
                        } else if isLoadingInfo {
                            ProgressView("加载中...")
                        } else {
                            Text("暂无网关信息").foregroundColor(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

                // 统计摘要
                GroupBox(label: Text("统计摘要")) {
                    if isLoadingStats {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let s = stats?.summary {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                MetricView(title: "总通话", value: s.total_calls)
                                MetricView(title: "已接通", value: s.answered_calls)
                                MetricView(title: "ASR", value: s.asr_percent)
                            }
                            HStack {
                                MetricView(title: "总接通秒数", value: String(s.total_answered_seconds))
                                MetricView(title: "平均接通秒数", value: s.avg_answered_seconds)
                            }
                        }
                    } else {
                        Text("暂无统计数据").foregroundColor(.secondary)
                    }
                }

                // 细分统计：finalcodes / hangup / error
                if let finalcodes = stats?.finalcodes, !finalcodes.isEmpty {
                    GroupBox(label: Text("最终响应码分布")) {
                        ForEach(finalcodes) { item in
                            HStack {
                                if let code = item.call_finalcode {
                                    Text(finalCodeText(code))
                                } else {
                                    Text("未知")
                                }
                                Spacer()
                                Text(item.cnt).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let hangups = stats?.hangupBreakdown, !hangups.isEmpty {
                    GroupBox(label: Text("挂断原因")) {
                        ForEach(hangups) { item in
                            HStack {
                                Text(hangupCauseText(item.hangup_cause))
                                Spacer()
                                Text(item.cnt).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let errors = stats?.errorBreakdown, !errors.isEmpty {
                    GroupBox(label: Text("错误统计")) {
                        ForEach(errors) { item in
                            HStack {
                                Text(errorCauseText(item.error_cause))
                                Spacer()
                                Text(item.cnt).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 每日趋势
                GroupBox(label: Text("每日统计")) {
                    if let daily = stats?.daily, !daily.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(daily) { day in
                                HStack {
                                    Text(formatUtcString(day.day)) // 使用已有日期格式化函数
                                    Spacer()
                                    Text("总: \(day.total_calls)").foregroundColor(.secondary)
                                    Text("接: \(day.answered_calls)").foregroundColor(.green)
                                }.font(.caption)
                            }
                        }
                    } else {
                        Text("暂无每日数据").foregroundColor(.secondary)
                    }
                }

            }
            .padding()
        }
        .navigationTitle("网关详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !initialLoaded {
                initialLoaded = true
                loadInfo()
                loadStats()
            }
        }
        .refreshable {
            loadInfo()
            loadStats()
        }
        .overlay(
            Group {
                if let err = vm.errorMessage {
                    ToastView(message: err)
                }
            }
        )
    }

    func loadInfo() {
        isLoadingInfo = true
        let params: [String: Any?] = ["gateway_id": gatewayId]
        vm.post(path: "/gateway/info", body: params) { result in
            DispatchQueue.main.async {
                isLoadingInfo = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let infoResp = try JSONDecoder().decode(GatewayInfoResponse.self, from: data)
                            gateway = infoResp.data
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "解析网关信息失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func loadStats() {
        isLoadingStats = true
        let params: [String: Any?] = ["gateway_id": gatewayId]
        vm.post(path: "/gateway/stat", body: params) { result in
            DispatchQueue.main.async {
                isLoadingStats = false
                switch result {
                case .success(let data):
                    do {
                        print("Received data: \(String(data: data, encoding: .utf8) ?? "nil")")
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let statResp = try JSONDecoder().decode(GatewayStatResponse.self, from: data)
                            stats = statResp.data
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "解析数据失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

// 小控件：展示单个指标
private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
    }
}


// ...existing code...

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

    @State private var isLoading = false
    @State private var initialLoaded = false

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
            ZStack {
                Form {
                    Section(header: Text("网关信息")) {
                        TextField("网关名称", text: $gatewayName)
                        Picker("类型", selection: $gatewayType) {
                            ForEach(gatewayTypeOptions, id: \.value) { option in
                                Text(option.name).tag(option.value)
                            }
                        }
                        TextField("主机地址", text: $gatewayHost)
                            .textInputAutocapitalization(.never)
                        TextField("端口", text: $gatewayPort)
                            .keyboardType(.numberPad)
                        TextField("Realm", text: $gatewayRealm)
                        TextField("用户名", text: $gatewayUsername)
                            .textInputAutocapitalization(.never)
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

                if isLoading {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("加载中...").padding().background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
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
                    .disabled(gatewayName.isEmpty || gatewayHost.isEmpty || gatewayPort.isEmpty || gatewayUsername.isEmpty)
                }
            }
            .onAppear {
                if isEdit && !initialLoaded {
                    initialLoaded = true
                    loadGatewayInfoAndInit()
                } else if !isEdit && !initialLoaded {
                    initialLoaded = true
                    // 新增模式保持默认值
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

    // 通过 /gateway/info 获取网关详情并初始化表单
    func loadGatewayInfoAndInit() {
        guard let gid = gateway?.gateway_id else { return }
        isLoading = true
        let params: [String: Any?] = ["gateway_id": gid]
        vm.post(path: "/gateway/info", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let gatewayInfoResp = try JSONDecoder().decode(GatewayInfoResponse.self, from: data)
                            let g = gatewayInfoResp.data
                            gatewayName = g.gateway_name
                            gatewayType = g.gateway_type
                            gatewayHost = g.gateway_host
                            gatewayPort = "\(g.gateway_port)"
                            gatewayRealm = g.gateway_realm
                            gatewayUsername = g.gateway_username
                            gatewayPassword = g.gateway_password
                            gatewayAuthtype = g.gateway_authtype
                            gatewayEnabled = g.gateway_enabled
                            gatewayRemark = g.gateway_remark ?? ""
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
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
    case 1: return "呼叫时系统错误"
    case 2: return "接通时系统错误"
    case 3: return "呼叫时错误码"
    case 4: return "接通时错误码"
    default: return "-"
    }
}

// ...existing code...
struct CallQueryView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var calls: [CallItem] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var limit = 20
    @State private var totalCount = 0
    @State private var isRefreshing = false

    var body: some View {
        //NavigationView {
            List {
                ForEach(calls) { call in
                    NavigationLink(destination: CallDetailView(vm: vm, call: call)) {
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
                    .buttonStyle(PlainButtonStyle())
                }

                if calls.count < totalCount && !isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear { loadMore() }
                        Spacer()
                    }
                }
            }
            .navigationTitle("通话查询")
            .refreshable {
                await refresh()
            }
            .overlay(
                Group {
                    if isLoading && calls.isEmpty {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground).opacity(0.7))
                    }
                }
            )
            .onAppear {
                if calls.isEmpty {
                    Task { await fetchCallsAsync(reset: true) }
                }
            }
        //}
    }

    // 异步刷新入口，供 refreshable 调用
    func refresh() async {
        isRefreshing = true
        page = 1
        await fetchCallsAsync(reset: true)
        isRefreshing = false
    }

    func loadMore() {
        guard !isLoading, calls.count < totalCount else { return }
        page += 1
        Task { await fetchCallsAsync(reset: false) }
    }

    // 使用 vm.post 的回调版本做实际请求
    func fetchCalls(reset: Bool) {
        if reset { page = 1 }
        isLoading = true
        let params: [String: Any?] = ["page": page, "limit": limit]
        vm.post(path: "/call/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let callListResp = try JSONDecoder().decode(CallListResponse.self, from: data)
                            totalCount = callListResp.total
                            if reset {
                                calls = callListResp.data
                            } else {
                                // 防止重复追加同一页
                                if page == 1 {
                                    calls = callListResp.data
                                } else {
                                    calls += callListResp.data
                                }
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // async/await 封装，便于 refreshable 使用
    func fetchCallsAsync(reset: Bool) async {
        await withCheckedContinuation { continuation in
            fetchCalls(reset: reset)
            continuation.resume()
        }
    }
}
// ...existing code...

// 新增：通话详情页
struct CallDetailView: View {
    @ObservedObject var vm: LinPhoneViewModel
    let call: CallItem
    @Environment(\.presentationMode) var presentationMode
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(call.call_direction == 1 ? "呼入" : (call.call_direction == 2 ? "呼出" : "内部"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(call.call_fromuri)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("→  \(call.call_touri)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 12)

            GroupBox(label: Text("时间信息")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("开始"); Spacer(); Text(formatUtcString(call.call_starttime)) }
                    HStack { Text("应答"); Spacer(); Text(formatUtcString(call.call_answertime )) }
                    HStack { Text("结束"); Spacer(); Text(formatUtcString(call.call_endtime)) }
                    HStack { Text("通话时长"); Spacer(); Text("\(call.call_duration ?? 0) 秒") }
                }
                .font(.callout)
            }

            GroupBox(label: Text("通话详情")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("状态"); Spacer(); Text((call.call_status == 2) ? "已接通" : "未接通") }
                    HStack { Text("网关"); Spacer(); Text(call.call_gatewayname ?? "-") }
                    HStack { Text("最终响应码"); Spacer(); Text("\(call.call_finalcode ?? 0)") }
                    HStack { Text("挂断原因"); Spacer(); Text(hangupCauseText(call.call_hangupcause ?? 0)) }
                }
                .font(.callout)
            }

            HStack(spacing: 16) {
                Button(action: {
                    // 重新拨打被叫
                    let target = call.call_touri
                    vm.call(to: target)
                }) {
                    VStack {
                        Image(systemName: "phone.arrow.up.right")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())
                        Text("重拨").font(.caption)
                    }
                }

                Button(action: {
                    // 复制被叫
                    UIPasteboard.general.string = call.call_touri
                    vm.errorMessage = "已复制被叫"
                }) {
                    VStack {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Circle())
                        Text("复制").font(.caption)
                    }
                }

                Button(action: {
                    // 分享基本信息
                    showingShare = true
                }) {
                    VStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Circle())
                        Text("分享").font(.caption)
                    }
                }
                .sheet(isPresented: $showingShare) {
                    let text = shareText()
                    ActivityView(activityItems: [text])
                }
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding()
        .navigationTitle("通话详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    func shareText() -> String {
        var s = "通话详情\n"
        s += "主叫: \(call.call_fromuri)\n"
        s += "被叫: \(call.call_touri)\n"
        s += "开始: \(call.call_starttime ?? "-")\n"
        s += "结束: \(call.call_endtime ?? "-")\n"
        s += "时长: \(call.call_duration ?? 0) 秒\n"
        s += "挂断原因: \(hangupCauseText(call.call_hangupcause ?? 0))\n"
        return s
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


struct RouteItem: Identifiable, Decodable {
    let route_id: Int
    let route_name: String?
    let route_gatewayid: Int
    let route_matchtype: Int // 1 主叫前缀 2 被叫前缀
    let route_matchvalue: String
    let route_enabled: Int // 1启用 2禁用
    let route_priority: Int?
    let route_remark: String?

    var id: Int { route_id }
}


struct RouteInfoResponse: Decodable {
    let code: Int
    let message: String
    let data: RouteItem
}

struct RouteListResponse: Decodable {
    let code: Int
    let message: String
    let data: [RouteItem]
    let total: Int
}

// ...existing code...

// 路由管理视图（列表 + 添加/修改/删除）
struct RouteManagementView: View {
    @ObservedObject var vm: LinPhoneViewModel
    // 可传入 gateway 用于筛选（从网关页面进入时传递）
    let gateway: GatewayItem?

    @State private var routes: [RouteItem] = []
    @State private var page = 1
    @State private var limit = 20
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var showAddRoute = false
    @State private var editRoute: RouteItem? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(routes) { r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.route_name ?? "路由 \(r.route_id)")
                                .font(.headline)
                            Spacer()
                            Text(r.route_enabled == 1 ? "启用" : "禁用")
                                .font(.caption)
                                .foregroundColor(r.route_enabled == 1 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 8).fill((r.route_enabled == 1 ? Color.green : Color.red).opacity(0.12)))
                        }
                        Text("匹配：\(r.route_matchtype == 1 ? "主叫前缀" : "被叫前缀") = \(r.route_matchvalue)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Text("网关 ID: \(r.route_gatewayid)  优先级: \(r.route_priority ?? 0)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 6)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRoute(r)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editRoute = r
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }

                if routes.count < totalCount && !isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .onAppear { loadMore() }
                        Spacer()
                    }
                }
            }
            .navigationTitle(gateway == nil ? "路由管理" : "\(gateway!.gateway_name) 的路由")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddRoute = true
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
                    if isLoading && routes.isEmpty {
                        ProgressView("加载中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground).opacity(0.7))
                    }
                }
            )
            .sheet(isPresented: $showAddRoute) {
                AddEditRouteView(vm: vm, route: nil, defaultGatewayId: gateway?.gateway_id, onSave: { newRoute in
                    addRoute(newRoute)
                }, onCancel: { showAddRoute = false })
            }
            .sheet(item: $editRoute) { r in
                AddEditRouteView(vm: vm, route: r, defaultGatewayId: nil, onSave: { updated in
                    updateRoute(updated)
                }, onCancel: { editRoute = nil })
            }
            .onAppear {
                if routes.isEmpty { Task { await refresh() } }
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        page = 1
        await fetchRoutes(reset: true)
        isRefreshing = false
    }

    func loadMore() {
        guard !isLoading, routes.count < totalCount else { return }
        page += 1
        fetchRoutes(reset: false)
    }

    func fetchRoutes(reset: Bool) {
        if reset { page = 1 }
        isLoading = true
        var params: [String: Any?] = ["page": page, "limit": limit]
        if let gw = gateway { params["route_gatewayid"] = gw.gateway_id }
        vm.post(path: "/route/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let list = try JSONDecoder().decode(RouteListResponse.self, from: data)
                            totalCount = list.total
                            if reset { routes = list.data } else { routes += list.data }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchRoutes(reset: Bool) async {
        await withCheckedContinuation { cont in
            fetchRoutes(reset: reset)
            cont.resume()
        }
    }

    func addRoute(_ route: RouteItem) {
        isLoading = true
        let params: [String: Any?] = [
            "route_name": route.route_name,
            "route_gatewayid": route.route_gatewayid,
            "route_matchtype": route.route_matchtype,
            "route_matchvalue": route.route_matchvalue,
            "route_enabled": route.route_enabled,
            "route_priority": route.route_priority
        ]
        vm.post(path: "/route/add", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            showAddRoute = false
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "添加失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func updateRoute(_ route: RouteItem) {
        isLoading = true
        let params: [String: Any?] = [
            "route_id": route.route_id,
            "route_name": route.route_name,
            // route_gatewayid 不允许编辑时也可以传回原值
            "route_gatewayid": route.route_gatewayid,
            "route_matchtype": route.route_matchtype,
            "route_matchvalue": route.route_matchvalue,
            "route_enabled": route.route_enabled,
            "route_priority": route.route_priority
        ]
        vm.post(path: "/route/update", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            editRoute = nil
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "修改失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func deleteRoute(_ route: RouteItem) {
        isLoading = true
        let params: [String: Any?] = ["route_id": route.route_id]
        vm.post(path: "/route/delete", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            Task { await refresh() }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "删除失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}

// 添加/编辑路由页面；编辑时不可修改 route_gatewayid
struct AddEditRouteView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var route: RouteItem?
    // 如果从网关页面添加，传入默认 gateway id
    let defaultGatewayId: Int?
    var onSave: (RouteItem) -> Void
    var onCancel: () -> Void

    @State private var routeId: Int = 0
    @State private var routeName: String = ""
    @State private var routeGatewayId: Int = 0
    @State private var matchType: Int = 1
    @State private var matchValue: String = ""
    @State private var enabled: Int = 1
    @State private var priority: Int? = nil
    @State private var remark: String = ""

    @State private var gateways: [GatewayItem] = []
    @State private var isLoading = false
    @State private var initialLoaded = false

    var isEdit: Bool { route != nil }

    var body: some View {
        NavigationView {
            ZStack {
                Form {
                    Section(header: Text("基本")) {
                        TextField("名称", text: $routeName)
                        // 网关：编辑时禁用选择
                        Picker("网关", selection: $routeGatewayId) {
                            ForEach(gateways, id: \.gateway_id) { gw in
                                Text("\(gw.gateway_name) (\(gw.gateway_id))").tag(gw.gateway_id)
                            }
                        }
                        .disabled(true) // 编辑时不可修改
                        Picker("匹配类型", selection: $matchType) {
                            Text("主叫前缀").tag(1)
                            Text("被叫前缀").tag(2)
                        }
                        TextField("匹配值", text: $matchValue)
                        Picker("状态", selection: $enabled) {
                            Text("启用").tag(1)
                            Text("禁用").tag(2)
                        }
                        TextField("优先级（可选）", text: Binding(
                            get: { priority == nil ? "" : String(priority!) },
                            set: { priority = Int($0) }
                        ))
                        .keyboardType(.numberPad)
                    }
                }

                if isLoading {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("加载中...").padding().background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                }
            }
            .navigationTitle(isEdit ? "编辑路由" : "添加路由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "保存" : "添加") {
                        let newRoute = RouteItem(
                            route_id: route?.route_id ?? 0,
                            route_name: routeName.isEmpty ? nil : routeName,
                            route_gatewayid: routeGatewayId,
                            route_matchtype: matchType,
                            route_matchvalue: matchValue,
                            route_enabled: enabled,
                            route_priority: priority,
                            route_remark: remark.isEmpty ? nil : remark
                        )
                        onSave(newRoute)
                    }
                    .disabled(matchValue.isEmpty || routeGatewayId == 0)
                }
            }
            .onAppear {
                if !initialLoaded {
                    initialLoaded = true
                    fetchGateways()
                    if isEdit { loadRouteInfo() }
                    else if let def = defaultGatewayId { routeGatewayId = def }
                }
            }
            .overlay(
                Group {
                    if let err = vm.errorMessage {
                        ToastView(message: err).zIndex(200)
                    }
                }
            )
        }
    }

    func fetchGateways() {
        isLoading = true
        let params: [String: Any?] = ["page": 1, "limit": 1000]
        vm.post(path: "/gateway/list", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let list = try JSONDecoder().decode(GatewayListResponse.self, from: data)
                            gateways = list.data
                            // 如果是新增并有默认 gateway id，则确保存在该 id
                            if !isEdit, let def = defaultGatewayId, gateways.contains(where: { $0.gateway_id == def }) {
                                routeGatewayId = def
                            }
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }

    func loadRouteInfo() {
        guard let rid = route?.route_id else { return }
        isLoading = true
        let params: [String: Any?] = ["route_id": rid]
        vm.post(path: "/route/info", body: params) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let data):
                    do {
                        let resp = try JSONDecoder().decode(CommonResponse.self, from: data)
                        if resp.code == 1 {
                            let info = try JSONDecoder().decode(RouteInfoResponse.self, from: data)
                            let r = info.data
                            routeId = r.route_id
                            routeName = r.route_name ?? ""
                            routeGatewayId = r.route_gatewayid
                            matchType = r.route_matchtype
                            matchValue = r.route_matchvalue
                            enabled = r.route_enabled
                            priority = r.route_priority
                            remark = r.route_remark ?? ""
                        } else {
                            vm.errorMessage = resp.message
                        }
                    } catch {
                        vm.errorMessage = "数据解析失败"
                    }
                case .failure(let error):
                    vm.errorMessage = "网络错误: \(error.localizedDescription)"
                }
            }
        }
    }
}






