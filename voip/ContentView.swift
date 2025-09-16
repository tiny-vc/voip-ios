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
        .frame(minWidth: 400, minHeight: 500)
        .overlay(
            Group {
                if let call = vm.currentCall {
                    CallStatusOverlay(call: call, vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }, alignment: .top
        )
        //.animation(.easeInOut, value: vm.currentCall)
    }
}


struct LoginView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var domain = "180.97.215.207:5555"
    @State private var username = "jack"
    @State private var password = "1"
    @State private var transport = "udp"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "phone.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            Text("SIP 登录")
                .font(.largeTitle)
                .fontWeight(.bold)
            VStack(spacing: 16) {
                TextField("服务器", text: $domain)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                TextField("用户名", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                SecureField("密码", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Picker("传输协议", selection: $transport) {
                    Text("UDP").tag("udp")
                    Text("TCP").tag("tcp")
                    Text("TLS").tag("tls")
                }
                .pickerStyle(SegmentedPickerStyle())
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
                Text("登录")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.isInitialized ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(!vm.isInitialized)
            .padding(.horizontal, 32)
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
            Spacer()
        }
        //.padding()
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemGray6))
                .shadow(radius: 8)
        )
    }
}


struct CallStatusOverlay: View {
    let call: Call
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("通话中: \(call.remoteAddress?.asString() ?? "未知")")
                    .font(.headline)
                Spacer()
                Button(action: {
                    vm.hangup(call: call)
                }) {
                    Image(systemName: "phone.down.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding()
            //.background(BlurView(style: .systemMaterial))
            .cornerRadius(12)
            .shadow(radius: 8)
        }
        .padding()
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
            VStack(spacing: 20) {
                Spacer()
                TextField("", text: $dialNumber)
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .disabled(true)
                    .padding(.horizontal, 30)
                Spacer()
                VStack(spacing: 12) {
                    ForEach(dialPadRows, id: \.self) { row in
                        HStack(spacing: 24) {
                            ForEach(row, id: \.self) { digit in
                                Button(action: {
                                    dialNumber.append(digit)
                                }) {
                                    Text(digit)
                                        .font(.system(size: 32, weight: .medium))
                                        .frame(width: 64, height: 64)
                                        .background(Color.blue.opacity(0.10))
                                        .foregroundColor(.primary)
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }
                    HStack(spacing: 32) {
                        Button(action: {
                            if !dialNumber.isEmpty {
                                dialNumber.removeLast()
                            }
                        }) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 28, weight: .regular))
                                .frame(width: 56, height: 56)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(Circle())
                        }
                        Button(action: {
                            showTextInput = true
                        }) {
                            Image(systemName: "text.cursor")
                                .font(.system(size: 24, weight: .regular))
                                .frame(width: 56, height: 56)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .clipShape(Circle())
                        }
                        Button(action: {
                            vm.call(to: dialNumber)
                            dialNumber = ""
                        }) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28, weight: .bold))
                                .frame(width: 56, height: 56)
                                .background(dialNumber.isEmpty ? Color.gray.opacity(0.15) : Color.green)
                                .foregroundColor(dialNumber.isEmpty ? .gray : .white)
                                .clipShape(Circle())
                        }
                        .disabled(dialNumber.isEmpty)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("拨号键盘")
            // 弹出文本输入框
            .alert("输入SIP地址或用户名", isPresented: $showTextInput) {
                TextField("如 jack 或 sip:jack@domain", text: $textInput)
                Button("呼叫") {
                    vm.call(to: textInput)
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
            username: "jack",
            displayName: "Jack",
            sipAddress: "sip:jack@180.97.215.207",
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
                            vm.call(to: contact.sipAddress)
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

struct CallLog: Identifiable, Hashable {
    enum CallType: String, CaseIterable {
        case incoming = "来电"
        case outgoing = "去电"
        case missed = "未接"
    }

    let id: UUID = UUID()
    let type: CallType           // 通话类型
    let peer: String             // 对方用户名或SIP地址
    let displayName: String?     // 对方显示名（可选）
    let time: Date               // 通话时间
    let duration: Int            // 通话时长（秒）
    let isSuccess: Bool          // 是否接通
}

struct CallsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var showDialPad = false
    @State private var list: [CallLog] = [
        CallLog(type: .incoming, peer: "sip:jack@180.97.215.207", displayName: "Jack", time: Date(), duration: 120, isSuccess: true),
        CallLog(type: .missed, peer: "sip:rose@180.97.215.208", displayName: "Rose", time: Date(), duration: 0, isSuccess: false),
    ]

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 16) {
                    List(list, id: \.id) { call in
                        HStack(alignment: .top, spacing: 12) {
                            // 图标区分通话类型
                            ZStack {
                                Circle()
                                    .fill(call.type == .missed ? Color.red.opacity(0.2) : (call.type == .incoming ? Color.green.opacity(0.2) : Color.blue.opacity(0.2)))
                                    .frame(width: 44, height: 44)
                                Image(systemName:
                                    call.type == .missed ? "phone.down.fill" :
                                    (call.type == .incoming ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                                )
                                .foregroundColor(call.type == .missed ? .red : (call.type == .incoming ? .green : .blue))
                                .font(.title2)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(call.displayName ?? call.peer)
                                        .font(.headline)
                                    if call.type == .missed {
                                        Text("未接")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.1))
                                            .cornerRadius(6)
                                        }
                                    }
                                    Text(call.peer)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    HStack(spacing: 16) {
                                        Text("时间: \(call.time.formatted(.dateTime.hour().minute()))")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        if call.duration > 0 {
                                            Text("时长: \(call.duration)秒")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                            }
                            Spacer()
                            // 状态图标
                            if call.isSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else if call.type == .missed {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                        )
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                    }
                    .listStyle(PlainListStyle())
                    Spacer()
                }
                // 悬浮按钮
                Button(action: {
                    showDialPad = true
                }) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(24)
                .accessibilityLabel("打开拨号键盘")
            }
            .navigationTitle("通话记录")
            // 弹出拨号键盘
            .sheet(isPresented: $showDialPad) {
                DialPadTabView(vm: vm)
            }
            
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



